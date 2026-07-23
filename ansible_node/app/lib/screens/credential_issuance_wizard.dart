import 'dart:async';
import 'dart:convert';

import 'package:ansible_store/ansible_store.dart';
import 'package:ansible_vc/ansible_vc.dart';
import 'package:flutter/material.dart';

import '../l10n/app_l10n.dart';
import '../services/atproto_client.dart';
import '../services/credential_payload_codec.dart';
import '../services/external_url_launcher.dart';
import '../services/passport_local_id_service.dart';
import '../services/vc_issuer_client.dart';
import '../services/zkpassport_srs_service.dart';
import 'mobilemoica_rp_credential_screen.dart';

enum CredentialIssuanceFlow { twProvider, passportNfc, emailOtp }

enum _EmailOtpPhase { idle, requesting, waitingOtp, issuing, presenting, done }

enum _PassportNfcPhase { idle, scanning, issuing, done }

class CredentialIssuanceWizard extends StatefulWidget {
  const CredentialIssuanceWizard({
    super.key,
    required this.holderDid,
    this.vcIssuerClient,
    this.relayClient,
    this.credentialWallet,
    this.vpBuilder,
    this.urlLauncher,
    this.walletRepository,
    this.passportReader,
    this.passportMrzScanner,
    this.passportLocalIdService,
    this.passportZkpProver,
    this.pollInterval = const Duration(seconds: 2),
    this.pollTimeout = const Duration(minutes: 2),
    this.onCredentialStored,
    this.onEmailCredentialAdded,
  });

  final String holderDid;
  final VcIssuerClient? vcIssuerClient;
  final AtProtoClient? relayClient;
  final CredentialWallet? credentialWallet;
  final VpBuilder? vpBuilder;
  final ExternalUrlLauncher? urlLauncher;
  final WalletRepository? walletRepository;
  final NfcPassportReader? passportReader;
  final PassportMrzScanner? passportMrzScanner;
  final PassportLocalIdService? passportLocalIdService;
  final ZkpProver? passportZkpProver;
  final Duration pollInterval;
  final Duration pollTimeout;
  final VoidCallback? onCredentialStored;
  final void Function(String reputationTier)? onEmailCredentialAdded;

  @override
  State<CredentialIssuanceWizard> createState() =>
      _CredentialIssuanceWizardState();
}

class _CredentialIssuanceWizardState extends State<CredentialIssuanceWizard> {
  CredentialIssuanceFlow? _selectedFlow;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    context.uiCopy(zh: '加入憑證', en: 'Add Credential'),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    context.uiCopy(
                      zh: '選擇你要使用的身份驗證方式',
                      en: 'Choose the verification method to use',
                    ),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 20),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    alignment: WrapAlignment.center,
                    children: [
                      _FlowOptionButton(
                        icon: Icons.badge_outlined,
                        label: context.uiCopy(
                          zh: 'TW 身份驗證',
                          en: 'TW Identity Verification',
                        ),
                        selected:
                            _selectedFlow == CredentialIssuanceFlow.twProvider,
                        onTap: () => _select(CredentialIssuanceFlow.twProvider),
                      ),
                      _FlowOptionButton(
                        icon: Icons.nfc,
                        label: 'Passport NFC',
                        selected:
                            _selectedFlow == CredentialIssuanceFlow.passportNfc,
                        onTap: () =>
                            _select(CredentialIssuanceFlow.passportNfc),
                      ),
                      _FlowOptionButton(
                        icon: Icons.email_outlined,
                        label: 'Email OTP / Legacy',
                        selected:
                            _selectedFlow == CredentialIssuanceFlow.emailOtp,
                        onTap: () => _select(CredentialIssuanceFlow.emailOtp),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 180),
                    child: _buildSelectedPanel(),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _select(CredentialIssuanceFlow flow) {
    setState(() => _selectedFlow = flow);
  }

  Widget _buildSelectedPanel() {
    switch (_selectedFlow) {
      case CredentialIssuanceFlow.twProvider:
        return MobileMoicaRPCredentialPanel(
          key: const ValueKey('mobilemoica-rp-panel'),
          holderDid: widget.holderDid,
          vcIssuerClient: widget.vcIssuerClient,
          urlLauncher: widget.urlLauncher,
          walletRepository: widget.walletRepository,
          pollInterval: widget.pollInterval,
          pollTimeout: widget.pollTimeout,
          onCredentialStored: widget.onCredentialStored,
        );
      case CredentialIssuanceFlow.passportNfc:
        return PassportNfcCredentialPanel(
          key: const ValueKey('passport-nfc-panel'),
          holderDid: widget.holderDid,
          vcIssuerClient: widget.vcIssuerClient,
          walletRepository: widget.walletRepository,
          passportReader: widget.passportReader,
          passportMrzScanner: widget.passportMrzScanner,
          passportLocalIdService: widget.passportLocalIdService,
          passportZkpProver: widget.passportZkpProver,
          onCredentialStored: widget.onCredentialStored,
        );
      case CredentialIssuanceFlow.emailOtp:
        return EmailOtpCredentialPanel(
          key: const ValueKey('email-otp-panel'),
          holderDid: widget.holderDid,
          vcIssuerClient: widget.vcIssuerClient,
          relayClient: widget.relayClient,
          credentialWallet: widget.credentialWallet,
          vpBuilder: widget.vpBuilder,
          walletRepository: widget.walletRepository,
          onCredentialStored: widget.onCredentialStored,
          onCredentialAdded: widget.onEmailCredentialAdded ?? (_) {},
        );
      case null:
        return const SizedBox.shrink(key: ValueKey('no-flow-selected'));
    }
  }
}

class PassportNfcCredentialPanel extends StatefulWidget {
  const PassportNfcCredentialPanel({
    super.key,
    required this.holderDid,
    this.vcIssuerClient,
    this.walletRepository,
    this.passportReader,
    this.passportMrzScanner,
    this.passportLocalIdService,
    this.passportZkpProver,
    this.onCredentialStored,
  });

  final String holderDid;
  final VcIssuerClient? vcIssuerClient;
  final WalletRepository? walletRepository;
  final NfcPassportReader? passportReader;
  final PassportMrzScanner? passportMrzScanner;
  final PassportLocalIdService? passportLocalIdService;
  final ZkpProver? passportZkpProver;
  final VoidCallback? onCredentialStored;

  @override
  State<PassportNfcCredentialPanel> createState() =>
      _PassportNfcCredentialPanelState();
}

class _PassportNfcCredentialPanelState
    extends State<PassportNfcCredentialPanel> {
  late final VcIssuerClient _vcIssuerClient;
  late final WalletRepository _walletRepository;
  late final NfcPassportReader _passportReader;
  late final PassportMrzScanner _passportMrzScanner;
  late final PassportLocalIdService _passportLocalIdService;
  late final ZkpProver _passportZkpProver;
  ZkpSrsProvider? _passportSrsProvider;

  _PassportNfcPhase _phase = _PassportNfcPhase.idle;
  String? _errorMessage;
  double? _srsDownloadProgress;
  ZkpProverProgress? _proofProgress;
  DateTime? _proofProgressObservedAt;
  Timer? _proofProgressTicker;
  bool _submittingToIssuer = false;
  bool _scanningMrz = false;
  final _documentNumberController = TextEditingController();
  final _dateOfBirthController = TextEditingController();
  final _dateOfExpiryController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _vcIssuerClient = widget.vcIssuerClient ?? VcIssuerClient();
    final walletRepository = widget.walletRepository;
    if (walletRepository == null) {
      throw StateError(
        'PassportNfcCredentialPanel requires a WalletRepository',
      );
    }
    _walletRepository = walletRepository;
    _passportReader =
        widget.passportReader ?? const PlatformNfcPassportReader();
    _passportMrzScanner =
        widget.passportMrzScanner ?? const PlatformPassportMrzScanner();
    _passportLocalIdService =
        widget.passportLocalIdService ?? const PassportLocalIdService();
    final injectedProver = widget.passportZkpProver;
    if (injectedProver != null) {
      _passportZkpProver = injectedProver;
    } else {
      _passportSrsProvider = ZkPassportSrsService(
        onProgress: (received, total) {
          if (!mounted || total <= 0) return;
          setState(() {
            _srsDownloadProgress = (received / total).clamp(0, 1);
          });
        },
      );
      _passportZkpProver = ZkpProverImpl(
        srsProvider: _passportSrsProvider!,
        onProgress: _recordProofProgress,
      );
    }
  }

  void _recordProofProgress(ZkpProverProgress progress) {
    if (!mounted) return;
    _proofProgressTicker ??= Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {});
    });
    setState(() {
      _proofProgress = progress;
      _proofProgressObservedAt = DateTime.now();
    });
  }

  void _stopProofProgressTicker() {
    _proofProgressTicker?.cancel();
    _proofProgressTicker = null;
    _proofProgressObservedAt = null;
  }

  String _copy({required String zh, required String en}) =>
      context.uiCopy(zh: zh, en: en);

  @override
  void dispose() {
    _stopProofProgressTicker();
    _documentNumberController.dispose();
    _dateOfBirthController.dispose();
    _dateOfExpiryController.dispose();
    unawaited(_passportReader.cancel());
    super.dispose();
  }

  Future<void> _startScan() async {
    final accessData = PassportAccessData(
      documentNumber: _documentNumberController.text,
      dateOfBirth: _dateOfBirthController.text,
      dateOfExpiry: _dateOfExpiryController.text,
    );
    String? preloadedSrsPath;
    try {
      accessData.validate();
    } on FormatException {
      setState(() {
        _errorMessage = _copy(
          zh: '請輸入護照號碼，以及 YYMMDD 格式的出生日期與有效期限。',
          en: 'Enter the passport number, birth date, and expiry date in YYMMDD format.',
        );
      });
      return;
    }
    if (!await _passportReader.isAvailable()) {
      if (!mounted) return;
      setState(() {
        _errorMessage = _copy(
          zh: '這台裝置不支援護照 NFC，或 NFC 目前無法使用。',
          en: 'Passport NFC is not supported or is currently unavailable on this device.',
        );
      });
      return;
    }
    setState(() {
      _phase = _PassportNfcPhase.scanning;
      _errorMessage = null;
      _srsDownloadProgress = null;
      _proofProgress = null;
      _proofProgressObservedAt = null;
      _submittingToIssuer = false;
    });

    try {
      PassportData? scanned;
      String? scanError;
      await _passportReader.scan(
        accessData: accessData,
        onPassportRead: (data) => scanned = data,
        onError: (message) => scanError = message,
      );
      final error = scanError;
      if (error != null) {
        throw StateError(error);
      }
      final data = scanned;
      if (data == null) {
        throw StateError(
          _copy(
            zh: '護照 NFC 讀取失敗，請重新嘗試。',
            en: 'Passport NFC read failed. Please try again.',
          ),
        );
      }
      if (!data.sodSignatureVerified || !data.dataGroupHashesVerified) {
        throw StateError(
          _copy(
            zh: '晶片資料未通過 SOD 簽章與資料完整性驗證，未建立憑證。',
            en: 'The chip failed SOD signature or data-integrity verification. No credential was created.',
          ),
        );
      }
      if (!data.countrySigningCertificateVerified) {
        throw StateError(
          _copy(
            zh: '已讀取護照晶片，但簽發國憑證不在目前受信任清單中，因此未建立真人憑證。',
            en: 'The passport chip was read, but its country certificate is not in the current trust list. No humanity credential was created.',
          ),
        );
      }

      final passportLocalUniqueId = await _passportLocalIdService
          .deriveWithStoredSecret(
            nationality: data.nationality,
            documentNumber: data.documentNumber,
          );
      final existing = await _walletRepository
          .getPassportExtensionByLocalUniqueId(passportLocalUniqueId);
      if (existing != null) {
        if (!mounted) return;
        setState(() {
          _phase = _PassportNfcPhase.idle;
          _errorMessage = _copy(
            zh: '這本護照已在此 Wallet 驗證過。',
            en: 'This passport has already been verified in this Wallet.',
          );
        });
        return;
      }

      if (!mounted) return;
      setState(() => _phase = _PassportNfcPhase.issuing);

      // Download the large public parameter file before requesting the
      // bounded, single-use Issuer challenge.
      preloadedSrsPath = await _passportSrsProvider?.acquire();
      final challenge = await _vcIssuerClient.requestPassportChallenge(
        did: widget.holderDid,
      );
      if (!challenge.expiresAt.isAfter(DateTime.now().toUtc())) {
        throw StateError('Issuer returned an expired passport challenge.');
      }
      final passportProof = await _passportZkpProver.prove(
        passport: data,
        challenge: ZkpChallengeBinding(
          challengeId: challenge.challengeId,
          nonce: challenge.nonce,
          did: widget.holderDid,
          issuer: challenge.issuer.toString(),
          scope: challenge.scope,
        ),
      );
      if (!mounted) return;
      _stopProofProgressTicker();
      setState(() => _submittingToIssuer = true);
      final vcJson = await _vcIssuerClient.issuePassportCredential(
        did: widget.holderDid,
        challengeId: challenge.challengeId,
        challengeNonce: challenge.nonce,
        nationality: data.nationality,
        nationalIdHash: passportProof.nationalIdHash,
        passportNumberHash: passportProof.passportNumberHash,
        zkpProof: passportProof.proofHex,
        zkpCircuitVersion: ZkpProof.kCircuitVersion,
        verificationKeyHash: 'sha256:${passportProof.vkHash}',
      );
      final credential = TrisAuraCredential.fromJson(
        Map<String, Object?>.from(vcJson),
      );
      if (credential.claims['assuranceMethod'] != 'passport_nfc') {
        throw StateError('Issuer returned an unsupported passport credential.');
      }
      if (credential.claims['nationality'] != data.nationality) {
        throw StateError('Issuer returned a mismatched passport credential.');
      }

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
          displayName: 'Passport Verified Human',
          createdAt: now,
          updatedAt: now,
        ),
        encryptedPayload: payloadEnvelope.encodedPayload,
        encryptionVersion: payloadEnvelope.encryptionVersion,
      );
      await _walletRepository.savePassportExtension(
        PassportWalletExtension(
          credentialId: credential.id,
          passportLocalUniqueId: passportLocalUniqueId,
          nationalIdHash: passportProof.nationalIdHash,
          passportNumberHash: passportProof.passportNumberHash,
          nationality: data.nationality,
          assuranceMethod: 'passport_nfc',
          verifiedAt: now,
        ),
      );
      widget.onCredentialStored?.call();

      if (!mounted) return;
      _stopProofProgressTicker();
      setState(() => _phase = _PassportNfcPhase.done);
    } catch (error) {
      if (!mounted) return;
      _stopProofProgressTicker();
      setState(() {
        _phase = _PassportNfcPhase.idle;
        _submittingToIssuer = false;
        _errorMessage = _formatError(error);
      });
    } finally {
      final path = preloadedSrsPath;
      if (path != null) {
        await _passportSrsProvider?.release(path);
      }
    }
  }

  Future<void> _scanMrz() async {
    setState(() {
      _scanningMrz = true;
      _errorMessage = null;
    });
    try {
      final accessData = await _passportMrzScanner.scan();
      if (!mounted) return;
      _documentNumberController.text = accessData.documentNumber;
      _dateOfBirthController.text = accessData.dateOfBirth;
      _dateOfExpiryController.text = accessData.dateOfExpiry;
      setState(() => _scanningMrz = false);
    } on Object {
      if (!mounted) return;
      setState(() {
        _scanningMrz = false;
        _errorMessage = _copy(
          zh: '無法辨識護照資料頁。請保持文字清晰、完整入鏡後再試一次。',
          en: 'The passport data page could not be recognized. Keep the MRZ sharp and fully in frame, then try again.',
        );
      });
    }
  }

  String _formatError(Object error) {
    if (error is VcIssuerException) {
      if (error.error == 'personhood_already_bound') {
        return _copy(
          zh: '這本護照已綁定到另一個有效帳號。',
          en: 'This passport is already bound to another active account.',
        );
      }
      if (error.error == 'passport_verifier_unconfigured') {
        return _copy(
          zh: '護照驗證服務尚未啟用。',
          en: 'The passport verification service is not enabled.',
        );
      }
      if (error.error == 'invalid_passport_proof') {
        return _copy(
          zh: '護照驗證結果無法通過伺服器驗證。',
          en: 'The passport proof could not be verified by the server.',
        );
      }
      if (error.statusCode >= 500) {
        return _copy(
          zh: '發行伺服器暫時無法使用，請稍後再試。',
          en: 'The issuer is temporarily unavailable. Please try again later.',
        );
      }
      return _copy(
        zh: '護照憑證發行失敗，請重新嘗試。',
        en: 'Passport credential issuance failed. Please try again.',
      );
    }
    if (error is StateError) {
      return error.message;
    }
    if (error is ZkpProverException) {
      final diagnostic = error.cause
          .toString()
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      return _copy(
        zh: '護照零知識證明在 ${error.stage} 階段失敗：$diagnostic',
        en: 'The passport zero-knowledge proof failed during ${error.stage}: $diagnostic',
      );
    }
    return _copy(
      zh: '護照 NFC 驗證暫時無法完成，請稍後再試。',
      en: 'Passport NFC verification cannot be completed right now. Please try again later.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final busy =
        _scanningMrz ||
        _phase == _PassportNfcPhase.scanning ||
        _phase == _PassportNfcPhase.issuing;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Icon(Icons.nfc, size: 56, color: Color(0xFF1A56A4)),
        const SizedBox(height: 16),
        Text(
          'Passport NFC',
          textAlign: TextAlign.center,
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Text(
          _copy(
            zh: '護照號碼不會送出或保存原文，只會產生本機識別值與伺服器去重用的不可逆 UID。',
            en: 'The passport number is never sent or stored as raw text. Only a local identifier and an irreversible server deduplication UID are derived.',
          ),
          textAlign: TextAlign.center,
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: Colors.grey[600]),
        ),
        const SizedBox(height: 24),
        OutlinedButton.icon(
          key: const ValueKey('passport-scan-mrz'),
          onPressed: busy ? null : _scanMrz,
          icon: _scanningMrz
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.document_scanner_outlined),
          label: Text(
            _copy(zh: '先掃描護照資料頁（MRZ）', en: 'Scan passport data page (MRZ)'),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          _copy(
            zh: 'MRZ 只在本機辨識，用來開啟護照晶片；無法掃描時才需要手動輸入下列資料。',
            en: 'MRZ recognition stays on device and is used only to unlock the chip. Enter the fields below only if scanning is unavailable.',
          ),
          textAlign: TextAlign.center,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: Colors.grey[600]),
        ),
        const SizedBox(height: 8),
        Text(
          _copy(
            zh: '產生一次性護照證明時會下載約 128 MB 的公開密碼學參數；驗證雜湊後只在本機暫存，完成或失敗後立即刪除。',
            en: 'Creating the one-time passport proof downloads about 128 MB of public cryptographic parameters. They are hash-verified, kept temporarily on this device, and deleted after success or failure.',
          ),
          textAlign: TextAlign.center,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: Colors.grey[600]),
        ),
        const SizedBox(height: 16),
        TextField(
          key: const ValueKey('passport-document-number'),
          controller: _documentNumberController,
          enabled: !busy,
          textCapitalization: TextCapitalization.characters,
          autocorrect: false,
          decoration: InputDecoration(
            labelText: _copy(zh: '護照號碼', en: 'Passport number'),
            hintText: '123456789',
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                key: const ValueKey('passport-date-of-birth'),
                controller: _dateOfBirthController,
                enabled: !busy,
                keyboardType: TextInputType.number,
                maxLength: 6,
                decoration: InputDecoration(
                  labelText: _copy(zh: '出生日期', en: 'Date of birth'),
                  hintText: 'YYMMDD',
                  counterText: '',
                  border: const OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                key: const ValueKey('passport-date-of-expiry'),
                controller: _dateOfExpiryController,
                enabled: !busy,
                keyboardType: TextInputType.number,
                maxLength: 6,
                decoration: InputDecoration(
                  labelText: _copy(zh: '有效期限', en: 'Date of expiry'),
                  hintText: 'YYMMDD',
                  counterText: '',
                  border: const OutlineInputBorder(),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        if (_errorMessage != null) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.red.shade50,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              _errorMessage!,
              style: TextStyle(color: Colors.red.shade800),
            ),
          ),
          const SizedBox(height: 16),
        ],
        if (_phase == _PassportNfcPhase.issuing &&
            _srsDownloadProgress != null) ...[
          LinearProgressIndicator(value: _srsDownloadProgress),
          const SizedBox(height: 8),
          Text(
            _copy(
              zh: '下載本機證明參數 ${(_srsDownloadProgress! * 100).round()}%',
              en: 'Downloading local proof parameters ${(_srsDownloadProgress! * 100).round()}%',
            ),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
        ],
        if (_phase == _PassportNfcPhase.issuing &&
            _srsDownloadProgress == 1 &&
            (_proofProgress != null || _submittingToIssuer)) ...[
          const LinearProgressIndicator(),
          const SizedBox(height: 8),
          Text(
            _passportProgressLabel(),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
        ],
        if (_phase == _PassportNfcPhase.done)
          FilledButton.icon(
            onPressed: null,
            icon: const Icon(Icons.check_circle),
            label: Text(_copy(zh: '護照憑證已加入', en: 'Passport credential added')),
          )
        else
          FilledButton.icon(
            onPressed: busy ? null : _startScan,
            icon: busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.nfc),
            label: Text(
              _phase == _PassportNfcPhase.issuing
                  ? _passportProgressLabel()
                  : _phase == _PassportNfcPhase.scanning
                  ? _copy(zh: '讀取護照中', en: 'Reading passport')
                  : _copy(zh: '掃描護照 NFC', en: 'Scan passport NFC'),
            ),
          ),
      ],
    );
  }

  String _passportProgressLabel() {
    if (_submittingToIssuer) {
      return _copy(zh: '向簽發者送出證明', en: 'Submitting proof to issuer');
    }
    final progress = _proofProgress;
    if (progress == null) {
      return _copy(zh: '準備本機證明', en: 'Preparing local proof');
    }
    final observedAt = _proofProgressObservedAt;
    final elapsed =
        progress.elapsed +
        (observedAt == null
            ? Duration.zero
            : DateTime.now().difference(observedAt));
    final elapsedSeconds = elapsed.inSeconds;
    final suffix = progress.circuitCount > 0
        ? ' ${progress.circuitIndex}/${progress.circuitCount}'
        : '';
    return switch (progress.stage) {
      ZkpProverStage.planning => _copy(
        zh: '${_planningStageLabel(progress.circuitName, zh: true)} · ${elapsedSeconds}s',
        en: '${_planningStageLabel(progress.circuitName, zh: false)} · ${elapsedSeconds}s',
      ),
      ZkpProverStage.initializingSrs => _copy(
        zh: '初始化證明參數 · ${elapsedSeconds}s',
        en: 'Initializing proof parameters · ${elapsedSeconds}s',
      ),
      ZkpProverStage.preparing => _copy(
        zh: '準備本機證明$suffix · ${elapsedSeconds}s',
        en: 'Preparing local proof$suffix · ${elapsedSeconds}s',
      ),
      ZkpProverStage.proving => _copy(
        zh: '產生本機證明$suffix · ${elapsedSeconds}s',
        en: 'Generating local proof$suffix · ${elapsedSeconds}s',
      ),
      ZkpProverStage.verifying => _copy(
        zh: '驗證本機證明$suffix · ${elapsedSeconds}s',
        en: 'Verifying local proof$suffix · ${elapsedSeconds}s',
      ),
    };
  }

  String _planningStageLabel(String? stage, {required bool zh}) {
    if (stage == null) {
      return zh ? '準備護照證明資料' : 'Planning passport proof';
    }
    if (stage.startsWith('download:')) {
      return zh ? '下載護照證明電路' : 'Downloading proof circuit';
    }
    if (stage.startsWith('validated:')) {
      return zh ? '驗證護照證明電路' : 'Validating proof circuit';
    }
    return switch (stage) {
      'passport:parse' => zh ? '解析護照晶片資料' : 'Parsing passport chip data',
      'passport:supported' => zh ? '選擇護照證明電路' : 'Selecting passport circuits',
      'registry:ready' =>
        zh ? '準備已驗證公開參數' : 'Preparing verified public metadata',
      'dsc:select' => zh ? '選擇護照簽章電路' : 'Selecting passport signature circuit',
      'dsc:inputs' => zh ? '建立護照簽章證明資料' : 'Building passport signature inputs',
      'dsc:ready' => zh ? '護照簽章資料完成' : 'Passport signature inputs ready',
      'id:select' => zh ? '選擇護照資料電路' : 'Selecting passport data circuit',
      'id:inputs' => zh ? '建立護照資料證明' : 'Building passport data inputs',
      'id:ready' => zh ? '護照資料證明完成' : 'Passport data inputs ready',
      'integrity:inputs' => zh ? '建立資料完整性證明' : 'Building integrity inputs',
      'disclose:inputs' => zh ? '建立最小揭露證明' : 'Building disclosure inputs',
      'bind:inputs' => zh ? '綁定本機身分與挑戰' : 'Binding identity and challenge',
      'plan:ready' => zh ? '護照證明資料已備妥' : 'Passport proof plan ready',
      _ => zh ? '準備護照證明資料' : 'Planning passport proof',
    };
  }
}

class EmailOtpCredentialPanel extends StatefulWidget {
  const EmailOtpCredentialPanel({
    super.key,
    required this.holderDid,
    required this.onCredentialAdded,
    this.vcIssuerClient,
    this.relayClient,
    this.credentialWallet,
    this.vpBuilder,
    this.walletRepository,
    this.onCredentialStored,
  });

  final String holderDid;
  final void Function(String reputationTier) onCredentialAdded;
  final VcIssuerClient? vcIssuerClient;
  final AtProtoClient? relayClient;
  final CredentialWallet? credentialWallet;
  final VpBuilder? vpBuilder;
  final WalletRepository? walletRepository;
  final VoidCallback? onCredentialStored;

  @override
  State<EmailOtpCredentialPanel> createState() =>
      _EmailOtpCredentialPanelState();
}

class _EmailOtpCredentialPanelState extends State<EmailOtpCredentialPanel> {
  _EmailOtpPhase _phase = _EmailOtpPhase.idle;
  String? _errorMessage;

  final _emailController = TextEditingController();
  final _otpController = TextEditingController();

  late final VcIssuerClient _vcClient;
  late final AtProtoClient _relayClient;
  late final CredentialWallet _wallet;
  late final VpBuilder _vpBuilder;

  @override
  void initState() {
    super.initState();
    _vcClient = widget.vcIssuerClient ?? VcIssuerClient();
    _relayClient = widget.relayClient ?? AtProtoClient();
    _wallet = widget.credentialWallet ?? const CredentialWallet();
    _vpBuilder = widget.vpBuilder ?? VpBuilder();
  }

  String _copy({required String zh, required String en}) =>
      context.uiCopy(zh: zh, en: en);

  @override
  void dispose() {
    _emailController.dispose();
    _otpController.dispose();
    super.dispose();
  }

  Future<void> _requestOtp() async {
    final email = _emailController.text.trim();
    if (!_isValidEmail(email)) {
      setState(
        () => _errorMessage = _copy(
          zh: '請輸入有效的 Email 地址。',
          en: 'Enter a valid email address.',
        ),
      );
      return;
    }

    setState(() {
      _phase = _EmailOtpPhase.requesting;
      _errorMessage = null;
    });

    try {
      final challenge = await _vcClient.requestEmailVerification(
        did: widget.holderDid,
        email: email,
      );

      setState(() {
        _phase = _EmailOtpPhase.waitingOtp;
        if (challenge.isMockOtp) {
          _otpController.text = challenge.otp!;
        }
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _phase = _EmailOtpPhase.idle;
        _errorMessage = _formatError(error);
      });
    }
  }

  Future<void> _submitOtp() async {
    final email = _emailController.text.trim();
    final otp = _otpController.text.trim();

    if (otp.isEmpty) {
      setState(
        () => _errorMessage = _copy(
          zh: '請輸入驗證碼。',
          en: 'Enter the verification code.',
        ),
      );
      return;
    }

    setState(() {
      _phase = _EmailOtpPhase.issuing;
      _errorMessage = null;
    });

    try {
      final vcJson = await _vcClient.issueCredential(
        did: widget.holderDid,
        email: email,
        otp: otp,
      );
      final vc = VerifiableCredential.fromJson(vcJson);

      await _wallet.store(vc);

      setState(() => _phase = _EmailOtpPhase.presenting);
      final vp = await _vpBuilder.build(
        holderDid: widget.holderDid,
        credentials: [vc],
      );

      final tier = await _relayClient.presentVp(
        holderDid: widget.holderDid,
        vp: vp.toJson(),
      );

      await _storeInWalletRepository(vc);

      setState(() => _phase = _EmailOtpPhase.done);
      widget.onCredentialStored?.call();
      widget.onCredentialAdded(tier);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _phase =
            (error is VcIssuerException &&
                (error.error == 'invalid_otp' || error.error == 'expired_otp'))
            ? _EmailOtpPhase.waitingOtp
            : _EmailOtpPhase.idle;
        _errorMessage = _formatError(error);
      });
    }
  }

  Future<void> _storeInWalletRepository(VerifiableCredential vc) async {
    final repository = widget.walletRepository;
    if (repository == null) return;

    final now = DateTime.now().toUtc();
    final validFrom = DateTime.parse(vc.issuanceDate).toUtc();
    final validUntil = vc.expirationDate == null
        ? validFrom.add(const Duration(days: 90))
        : DateTime.parse(vc.expirationDate!).toUtc();

    final payloadEnvelope = await const SecureCredentialPayloadCodec().seal(
      credentialId: vc.id,
      payloadJson: jsonEncode(vc.toJson()),
    );

    await repository.saveCredential(
      metadata: WalletCredential(
        credentialId: vc.id,
        issuerDid: vc.issuer,
        holderDid: vc.holderDid ?? widget.holderDid,
        credentialType: vc.type.contains('EmailCredential')
            ? 'EmailCredential'
            : vc.type.contains('TrisAuraHumanityCredential')
            ? 'TrisAuraHumanityCredential'
            : vc.type.last,
        status: WalletCredentialStatus.active,
        validFrom: validFrom,
        validUntil: validUntil,
        displayName: vc.type.contains('EmailCredential')
            ? 'Email Verified'
            : 'Verified Human',
        createdAt: now,
        updatedAt: now,
      ),
      encryptedPayload: payloadEnvelope.encodedPayload,
      encryptionVersion: payloadEnvelope.encryptionVersion,
    );
  }

  String _formatError(Object error) {
    if (error is VcIssuerException) {
      switch (error.error) {
        case 'invalid_otp':
          return _copy(
            zh: '驗證碼不正確，請重新輸入。',
            en: 'The verification code is incorrect. Please try again.',
          );
        case 'expired_otp':
          return _copy(
            zh: '驗證碼已逾期，請重新申請。',
            en: 'The verification code has expired. Request a new one.',
          );
        case 'invalid_email':
          return _copy(
            zh: 'Email 格式無效，請重新輸入。',
            en: 'The email format is invalid. Please re-enter it.',
          );
        case 'invalid_did':
          return _copy(
            zh: 'DID 格式無效，請重新啟動。',
            en: 'The DID format is invalid. Please restart.',
          );
      }
      if (error.statusCode >= 500) {
        return _copy(
          zh: '發行伺服器暫時無法使用，請稍後再試。',
          en: 'The issuer is temporarily unavailable. Please try again later.',
        );
      }
    }
    if (error is AtProtoException) {
      switch (error.error) {
        case 'invalid_vp':
        case 'invalid_vc':
          return _copy(
            zh: '憑證驗證失敗，請重新嘗試。',
            en: 'Credential verification failed. Please try again.',
          );
        case 'vc_expired':
          return _copy(
            zh: '憑證已逾期，請重新取得。',
            en: 'The credential has expired. Please get a new one.',
          );
        case 'already_verified':
          return _copy(
            zh: '此帳號已完成驗證。',
            en: 'This account is already verified.',
          );
      }
      if (error.statusCode >= 500) {
        return _copy(
          zh: 'Relay 暫時無法使用，請稍後再試。',
          en: 'The Relay is temporarily unavailable. Please try again later.',
        );
      }
    }
    return error.toString();
  }

  bool _isValidEmail(String email) {
    return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Icon(
          Icons.verified_user_outlined,
          size: 56,
          color: Color(0xFF1A56A4),
        ),
        const SizedBox(height: 16),
        Text(
          _copy(zh: 'Email 聯絡方式驗證', en: 'Email Contact Verification'),
          textAlign: TextAlign.center,
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Text(
          _copy(
            zh: '驗證 Email 後可取得聯絡方式驗證狀態',
            en: 'Verify email to receive contact verification status.',
          ),
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: Colors.grey[600]),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 32),
        TextField(
          controller: _emailController,
          enabled: _phase == _EmailOtpPhase.idle,
          keyboardType: TextInputType.emailAddress,
          autocorrect: false,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) {
            if (_phase == _EmailOtpPhase.idle) _requestOtp();
          },
          decoration: InputDecoration(
            labelText: _copy(zh: 'Email 地址', en: 'Email address'),
            prefixIcon: const Icon(Icons.email_outlined),
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        if (_phase == _EmailOtpPhase.waitingOtp ||
            _phase == _EmailOtpPhase.issuing ||
            _phase == _EmailOtpPhase.presenting) ...[
          TextField(
            controller: _otpController,
            enabled: _phase == _EmailOtpPhase.waitingOtp,
            keyboardType: TextInputType.number,
            maxLength: 6,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) {
              if (_phase == _EmailOtpPhase.waitingOtp) _submitOtp();
            },
            decoration: InputDecoration(
              labelText: _copy(zh: '6 位數驗證碼', en: '6-digit verification code'),
              prefixIcon: const Icon(Icons.pin_outlined),
              border: OutlineInputBorder(),
              counterText: '',
            ),
          ),
          const SizedBox(height: 16),
        ],
        _buildPhaseIndicator(),
        const SizedBox(height: 24),
        if (_errorMessage != null) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.red.shade50,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              _errorMessage!,
              style: TextStyle(color: Colors.red.shade800),
            ),
          ),
          const SizedBox(height: 16),
        ],
        _buildActionButton(),
        const SizedBox(height: 16),
        Text(
          _copy(
            zh: 'Email 地址不會上傳至伺服器記錄\n憑證加密存於裝置本地',
            en: 'The email address is not stored in server records.\nCredentials are encrypted on this device.',
          ),
          textAlign: TextAlign.center,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: Colors.grey),
        ),
      ],
    );
  }

  Widget _buildActionButton() {
    final busy =
        _phase != _EmailOtpPhase.idle && _phase != _EmailOtpPhase.waitingOtp;

    if (_phase == _EmailOtpPhase.idle) {
      return FilledButton.icon(
        onPressed: _requestOtp,
        icon: const Icon(Icons.send),
        label: Text(_copy(zh: '發送驗證碼', en: 'Send verification code')),
      );
    }

    if (_phase == _EmailOtpPhase.waitingOtp) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FilledButton.icon(
            onPressed: _submitOtp,
            icon: const Icon(Icons.check),
            label: Text(_copy(zh: '驗證並取得憑證', en: 'Verify and get credential')),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => setState(() {
              _phase = _EmailOtpPhase.idle;
              _otpController.clear();
              _errorMessage = null;
            }),
            child: Text(_copy(zh: '重新發送驗證碼', en: 'Resend verification code')),
          ),
        ],
      );
    }

    if (_phase == _EmailOtpPhase.done) {
      return FilledButton.icon(
        onPressed: null,
        icon: const Icon(Icons.check_circle),
        label: Text(_copy(zh: '憑證已加入', en: 'Credential added')),
      );
    }

    return FilledButton(
      onPressed: null,
      child: busy
          ? const SizedBox(
              height: 20,
              width: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Text(_copy(zh: '請稍候…', en: 'Please wait...')),
    );
  }

  Widget _buildPhaseIndicator() {
    if (_phase == _EmailOtpPhase.idle) return const SizedBox.shrink();

    final steps = [
      (
        label: _copy(zh: '📧 發送驗證碼', en: '📧 Send code'),
        phase: _EmailOtpPhase.requesting,
      ),
      (
        label: _copy(zh: '🔢 輸入驗證碼', en: '🔢 Enter code'),
        phase: _EmailOtpPhase.waitingOtp,
      ),
      (
        label: _copy(zh: '📜 取得憑證', en: '📜 Get credential'),
        phase: _EmailOtpPhase.issuing,
      ),
      (
        label: _copy(zh: '☁️ 提交 Relay', en: '☁️ Submit to Relay'),
        phase: _EmailOtpPhase.presenting,
      ),
      (
        label: _copy(zh: '✅ 信任等級升級', en: '✅ Trust tier updated'),
        phase: _EmailOtpPhase.done,
      ),
    ];

    return Column(
      children: steps.map((step) {
        final isDone =
            _phase.index > step.phase.index ||
            (_phase == _EmailOtpPhase.done &&
                step.phase == _EmailOtpPhase.done);
        final isCurrent =
            _phase == step.phase && step.phase != _EmailOtpPhase.done;
        return ListTile(
          dense: true,
          leading: isCurrent
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(
                  isDone ? Icons.check_circle : Icons.radio_button_unchecked,
                  color: isDone ? Colors.green : Colors.grey,
                  size: 24,
                ),
          title: Text(
            step.label,
            style: TextStyle(
              color: isCurrent ? const Color(0xFF1A56A4) : null,
              fontWeight: isCurrent ? FontWeight.bold : null,
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _FlowOptionButton extends StatelessWidget {
  const _FlowOptionButton({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected
        ? Theme.of(context).colorScheme.primary
        : Theme.of(context).colorScheme.onSurfaceVariant;

    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, color: color),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        foregroundColor: color,
        side: BorderSide(
          color: selected
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).dividerColor,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
    );
  }
}
