import 'dart:async';
import 'dart:convert';

import 'package:ansible_store/ansible_store.dart';
import 'package:ansible_vc/ansible_vc.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';

import '../l10n/app_l10n.dart';
import '../services/credential_payload_codec.dart';
import '../services/external_url_launcher.dart';
import '../services/vc_issuer_client.dart';

const kMobileMoicaRPConsentVersion = 'mobilemoica-rp-v1';
const kMobileMoicaRPDisclosureCopy =
    '這是 MobileMoica / TW FidO relying-party 驗證，不是 zkID，也不是 zero-knowledge proof。'
    'Tris-Aura Issuer 會在你同意後接收你輸入的身分證字號，只用於申請一次性 MobileMoica ticket。'
    'Issuer 可能暫時處理 TW FidO 回傳的簽章與憑證資料來驗證結果，但發出的 VC 不會包含身分證字號、姓名、憑證 subject、簽章回應或 duplicate commitment。';
const kMobileMoicaRPDisclosureCopyEn =
    'This is MobileMoica / TW FidO relying-party verification, not zkID and not a zero-knowledge proof. '
    'After you consent, the Tris-Aura Issuer receives the national ID you enter only to request a one-time MobileMoica ticket. '
    'The Issuer may temporarily process TW FidO signatures and certificate data to verify the result, but the issued VC will not include the national ID, legal name, certificate subject, signature response, or duplicate commitment.';

enum _Phase { idle, starting, polling, issuing, done, error }

class MobileMoicaRPCredentialScreen extends StatelessWidget {
  const MobileMoicaRPCredentialScreen({
    super.key,
    required this.holderDid,
    this.vcIssuerClient,
    this.urlLauncher,
    this.walletRepository,
    this.pollInterval = const Duration(seconds: 4),
    this.pollTimeout = const Duration(minutes: 2),
  });

  final String holderDid;
  final VcIssuerClient? vcIssuerClient;
  final ExternalUrlLauncher? urlLauncher;
  final WalletRepository? walletRepository;
  final Duration pollInterval;
  final Duration pollTimeout;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('MobileMoica Verified Human')),
      body: MobileMoicaRPCredentialPanel(
        holderDid: holderDid,
        vcIssuerClient: vcIssuerClient,
        urlLauncher: urlLauncher,
        walletRepository: walletRepository,
        pollInterval: pollInterval,
        pollTimeout: pollTimeout,
      ),
    );
  }
}

class MobileMoicaRPCredentialPanel extends StatefulWidget {
  const MobileMoicaRPCredentialPanel({
    super.key,
    required this.holderDid,
    this.vcIssuerClient,
    this.urlLauncher,
    this.walletRepository,
    this.pollInterval = const Duration(seconds: 4),
    this.pollTimeout = const Duration(minutes: 2),
    this.onCredentialStored,
  });

  final String holderDid;
  final VcIssuerClient? vcIssuerClient;
  final ExternalUrlLauncher? urlLauncher;
  final WalletRepository? walletRepository;
  final Duration pollInterval;
  final Duration pollTimeout;
  final VoidCallback? onCredentialStored;

  @override
  State<MobileMoicaRPCredentialPanel> createState() =>
      _MobileMoicaRPCredentialPanelState();
}

class _MobileMoicaRPCredentialPanelState
    extends State<MobileMoicaRPCredentialPanel>
    with WidgetsBindingObserver {
  final _nationalIdController = TextEditingController();

  late final VcIssuerClient _vcIssuerClient;
  late final ExternalUrlLauncher _urlLauncher;
  late final WalletRepository _walletRepository;

  _Phase _phase = _Phase.idle;
  bool _acceptedDisclosure = false;
  String? _errorMessage;
  MobileMoicaRPOffer? _offer;
  Timer? _pollTimer;
  Timer? _pollTimeoutTimer;
  bool _isAppForegrounded = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _vcIssuerClient = widget.vcIssuerClient ?? VcIssuerClient();
    _urlLauncher = widget.urlLauncher ?? const UrlLauncherExternalUrlLauncher();
    final walletRepository = widget.walletRepository;
    if (walletRepository == null) {
      throw StateError(
        'MobileMoicaRPCredentialPanel requires a WalletRepository',
      );
    }
    _walletRepository = walletRepository;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cancelPolling();
    _nationalIdController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final foregrounded = state == AppLifecycleState.resumed;
    if (!foregrounded) {
      _isAppForegrounded = false;
      _cancelPolling();
      return;
    }

    final wasForegrounded = _isAppForegrounded;
    _isAppForegrounded = true;
    if (!wasForegrounded && _phase == _Phase.polling) {
      _beginPolling();
    }
  }

  Future<void> _startFlow() async {
    final nationalId = _normalizedNationalId;
    if (!_acceptedDisclosure || !_isValidNationalId(nationalId)) {
      setState(
        () => _errorMessage = _copy(
          zh: '請確認揭露說明並輸入有效的身分證字號。',
          en: 'Confirm the disclosure and enter a valid national ID number.',
        ),
      );
      return;
    }

    setState(() {
      _phase = _Phase.starting;
      _errorMessage = null;
    });

    try {
      final offer = await _vcIssuerClient.startMobileMoicaRPFlow(
        holderDid: widget.holderDid,
        nationalId: nationalId,
        consentVersion: kMobileMoicaRPConsentVersion,
        consentCopyHash: _consentCopyHash,
        locale: _localeTag(context),
      );
      final opened = await _urlLauncher.open(offer.deepLinkUrl);
      if (!mounted) return;
      if (!opened) {
        setState(() {
          _offer = offer;
          _phase = _Phase.error;
          _errorMessage = _copy(
            zh: '開啟 TW FidO 失敗',
            en: 'Could not open TW FidO',
          );
        });
        return;
      }
      setState(() {
        _offer = offer;
        _phase = _Phase.polling;
      });
      _beginPolling();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.error;
        _errorMessage = _formatError(error);
      });
    }
  }

  void _beginPolling() {
    _cancelPolling();
    if (!_isAppForegrounded) return;
    _pollOnce();
    _pollTimer = Timer.periodic(widget.pollInterval, (_) => _pollOnce());
    _pollTimeoutTimer = Timer(widget.pollTimeout, () {
      _pollTimer?.cancel();
      _pollTimer = null;
      if (!mounted) return;
      setState(() {
        _phase = _Phase.error;
        _errorMessage = _copy(
          zh: '尚未收到 TW FidO 驗證結果',
          en: 'TW FidO verification has not completed yet',
        );
      });
    });
  }

  Future<void> _pollOnce() async {
    final offer = _offer;
    if (offer == null || _phase != _Phase.polling) return;

    try {
      final status = await _vcIssuerClient.getMobileMoicaRPStatus(
        offer.offerId,
      );
      if (!mounted || !_isAppForegrounded || _phase != _Phase.polling) {
        return;
      }
      if (!status.isVerified) return;
      await _issueAndStore(offer.offerId);
    } catch (error) {
      if (!mounted || !_isAppForegrounded || _phase != _Phase.polling) {
        return;
      }
      if (error is VcIssuerException &&
          error.error == 'provider_not_verified') {
        setState(() {
          _phase = _Phase.polling;
          _errorMessage = null;
        });
        return;
      }
      setState(() {
        _phase = _Phase.error;
        _errorMessage = _formatError(error);
      });
    }
  }

  Future<void> _issueAndStore(String offerId) async {
    _cancelPolling();
    if (!mounted) return;
    setState(() {
      _phase = _Phase.issuing;
      _errorMessage = null;
    });

    try {
      final vcJson = await _vcIssuerClient.issueMobileMoicaRPCredential(
        holderDid: widget.holderDid,
        offerId: offerId,
      );
      final credential = TrisAuraCredential.fromJson(
        Map<String, Object?>.from(vcJson),
      );
      final now = DateTime.now().toUtc();
      final payloadEnvelope = await const SecureCredentialPayloadCodec().seal(
        credentialId: credential.id,
        payloadJson: jsonEncode(credential.json),
      );
      await _walletRepository.saveCredential(
        metadata: WalletCredential(
          credentialId: credential.id,
          issuerDid: credential.issuerDid,
          holderDid: credential.holderDid,
          credentialType:
              credential.types.contains('TrisAuraHumanityCredential')
              ? 'TrisAuraHumanityCredential'
              : credential.types.last,
          status: WalletCredentialStatus.active,
          validFrom: credential.validFrom,
          validUntil: credential.validUntil,
          displayName: 'MobileMoica Verified Human',
          createdAt: now,
          updatedAt: now,
        ),
        encryptedPayload: payloadEnvelope.encodedPayload,
        encryptionVersion: payloadEnvelope.encryptionVersion,
      );
      widget.onCredentialStored?.call();
      if (!mounted) return;
      setState(() => _phase = _Phase.done);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.error;
        _errorMessage = _formatError(error);
      });
    }
  }

  String _formatError(Object error) {
    if (error is VcIssuerException) {
      if (error.error == 'invalid_national_id') {
        return _copy(
          zh: '身分證字號格式無效，請重新輸入。',
          en: 'The national ID format is invalid. Please re-enter it.',
        );
      }
      if (error.error == 'provider_not_verified') {
        return _copy(
          zh: '等待 TW FidO 驗證完成',
          en: 'Waiting for TW FidO verification to complete',
        );
      }
      if (error.error == 'callback_replay' ||
          error.error == 'state_mismatch' ||
          error.error == 'invalid_provider_proof' ||
          error.error.startsWith('invalid_provider_proof')) {
        return _copy(
          zh: '驗證安全檢查失敗，請重新開始。',
          en: 'The verification security check failed. Please restart.',
        );
      }
      if (error.statusCode >= 500) {
        return _copy(
          zh: '發行伺服器暫時無法使用，請稍後再試。',
          en: 'The issuer is temporarily unavailable. Please try again later.',
        );
      }
    }
    return _copy(
      zh: '發行流程暫時無法完成，請稍後再試。',
      en: 'The issuance flow cannot be completed right now. Please try again later.',
    );
  }

  String _copy({required String zh, required String en}) =>
      context.uiCopy(zh: zh, en: en);

  String get _normalizedNationalId =>
      _nationalIdController.text.trim().toUpperCase();

  bool get _isBusy => _phase == _Phase.starting;

  bool get _canStart =>
      _acceptedDisclosure &&
      _isValidNationalId(_normalizedNationalId) &&
      !_isBusy;

  bool _isValidNationalId(String value) {
    return RegExp(r'^[A-Z][0-9]{9}$').hasMatch(value);
  }

  String get _consentCopyHash {
    final digest = sha256.convert(utf8.encode(_disclosureCopy));
    return 'sha256:$digest';
  }

  String get _disclosureCopy => _copy(
    zh: kMobileMoicaRPDisclosureCopy,
    en: kMobileMoicaRPDisclosureCopyEn,
  );

  String _localeTag(BuildContext context) {
    final locale = Localizations.localeOf(context);
    final script = locale.scriptCode == null ? '' : '-${locale.scriptCode}';
    final country = locale.countryCode == null ? '' : '-${locale.countryCode}';
    return '${locale.languageCode}$script$country';
  }

  void _restart() {
    _cancelPolling();
    setState(() {
      _phase = _Phase.idle;
      _offer = null;
      _errorMessage = null;
      _acceptedDisclosure = false;
      _nationalIdController.clear();
    });
  }

  void _cancelPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
    _pollTimeoutTimer?.cancel();
    _pollTimeoutTimer = null;
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(
                  Icons.verified_user_outlined,
                  size: 56,
                  color: Color(0xFF0E7C7B),
                ),
                const SizedBox(height: 16),
                Text(
                  _title,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  _body,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 18),
                if (_phase == _Phase.idle || _phase == _Phase.starting) ...[
                  CheckboxListTile(
                    value: _acceptedDisclosure,
                    onChanged: _isBusy
                        ? null
                        : (value) {
                            setState(() {
                              _acceptedDisclosure = value ?? false;
                              _errorMessage = null;
                            });
                          },
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: Text(
                      _copy(
                        zh: '我了解並同意這次明確揭露',
                        en: 'I understand and consent to this disclosure',
                      ),
                    ),
                  ),
                  if (_acceptedDisclosure) ...[
                    const SizedBox(height: 12),
                    TextField(
                      key: const ValueKey('mobilemoica-national-id-field'),
                      controller: _nationalIdController,
                      enabled: !_isBusy,
                      textCapitalization: TextCapitalization.characters,
                      autocorrect: false,
                      decoration: InputDecoration(
                        labelText: _copy(zh: '身分證字號', en: 'National ID number'),
                        prefixIcon: const Icon(Icons.badge_outlined),
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (_) => setState(() => _errorMessage = null),
                    ),
                  ],
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    key: const ValueKey('mobilemoica-start-button'),
                    onPressed: _canStart ? _startFlow : null,
                    icon: _isBusy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.open_in_new),
                    label: Text(_copy(zh: '開啟 TW FidO', en: 'Open TW FidO')),
                  ),
                ],
                if (_errorMessage != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    _errorMessage!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Color(0xFFC0392B)),
                  ),
                ],
                if (_phase == _Phase.polling) ...[
                  const SizedBox(height: 18),
                  const LinearProgressIndicator(),
                ],
                if (_phase == _Phase.error) ...[
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: _restart,
                    icon: const Icon(Icons.restart_alt),
                    label: Text(_copy(zh: '重新開始', en: 'Restart')),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  String get _title {
    switch (_phase) {
      case _Phase.idle:
      case _Phase.starting:
        return 'MobileMoica Verified Human';
      case _Phase.polling:
        return _copy(
          zh: '等待 TW FidO 驗證完成',
          en: 'Waiting for TW FidO verification',
        );
      case _Phase.issuing:
        return _copy(zh: '正在發行憑證', en: 'Issuing credential');
      case _Phase.done:
        return _copy(zh: '憑證已加入 Wallet', en: 'Credential added to Wallet');
      case _Phase.error:
        return _copy(zh: '驗證流程暫停', en: 'Verification paused');
    }
  }

  String get _body {
    switch (_phase) {
      case _Phase.idle:
        return _disclosureCopy;
      case _Phase.starting:
        return _copy(
          zh: '正在建立 MobileMoica 驗證工作階段。',
          en: 'Creating a MobileMoica verification session.',
        );
      case _Phase.polling:
        return _copy(
          zh: '完成 TW FidO 授權後，請回到 Elix 等候 Issuer 驗證結果。',
          en: 'After finishing TW FidO authorization, return to Elix and wait for the Issuer result.',
        );
      case _Phase.issuing:
        return _copy(
          zh: 'Issuer 已確認驗證結果，正在建立你的 humanity credential。',
          en: 'The Issuer confirmed the verification result and is creating your humanity credential.',
        );
      case _Phase.done:
        return _copy(
          zh: '你可以回到 Wallet 查看憑證狀態。',
          en: 'You can return to Wallet to view the credential status.',
        );
      case _Phase.error:
        return _copy(
          zh: '你可以稍後重試，或重新開始驗證流程。',
          en: 'You can retry later or restart the verification flow.',
        );
    }
  }
}
