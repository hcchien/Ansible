import 'dart:convert';

import 'package:ansible_store/ansible_store.dart';
import 'package:ansible_vc/ansible_vc.dart';
import 'package:flutter/material.dart';

import '../services/atproto_client.dart';
import '../services/credential_payload_codec.dart';
import '../services/external_url_launcher.dart';
import '../services/passport_local_id_service.dart';
import '../services/vc_issuer_client.dart';
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
                    '加入憑證',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '選擇你要使用的身份驗證方式',
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
                        label: 'TW 身份驗證',
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
    this.passportLocalIdService,
    this.passportZkpProver,
    this.onCredentialStored,
  });

  final String holderDid;
  final VcIssuerClient? vcIssuerClient;
  final WalletRepository? walletRepository;
  final NfcPassportReader? passportReader;
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
  late final PassportLocalIdService _passportLocalIdService;
  late final ZkpProver _passportZkpProver;

  _PassportNfcPhase _phase = _PassportNfcPhase.idle;
  String? _errorMessage;

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
    _passportReader = widget.passportReader ?? const MockNfcPassportReader();
    _passportLocalIdService =
        widget.passportLocalIdService ?? const PassportLocalIdService();
    _passportZkpProver = widget.passportZkpProver ?? const ZkpProverImpl();
  }

  Future<void> _startScan() async {
    setState(() {
      _phase = _PassportNfcPhase.scanning;
      _errorMessage = null;
    });

    try {
      PassportData? scanned;
      String? scanError;
      await _passportReader.scan(
        onPassportRead: (data) => scanned = data,
        onError: (message) => scanError = message,
      );
      final error = scanError;
      if (error != null) {
        throw StateError(error);
      }
      final data = scanned;
      if (data == null) {
        throw StateError('護照 NFC 讀取失敗，請重新嘗試。');
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
          _errorMessage = '這本護照已在此 Wallet 驗證過。';
        });
        return;
      }

      if (!mounted) return;
      setState(() => _phase = _PassportNfcPhase.issuing);

      final passportProof = await _passportZkpProver.prove(
        passportSecretHex: data.passportSecret,
      );
      final vcJson = await _vcIssuerClient.issuePassportCredential(
        did: widget.holderDid,
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
      setState(() => _phase = _PassportNfcPhase.done);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _phase = _PassportNfcPhase.idle;
        _errorMessage = _formatError(error);
      });
    }
  }

  String _formatError(Object error) {
    if (error is VcIssuerException) {
      if (error.error == 'personhood_already_bound') {
        return '這本護照已綁定到另一個有效帳號。';
      }
      if (error.error == 'passport_verifier_unconfigured') {
        return '護照驗證服務尚未啟用。';
      }
      if (error.error == 'invalid_passport_proof') {
        return '護照驗證結果無法通過伺服器驗證。';
      }
      if (error.statusCode >= 500) return '發行伺服器暫時無法使用，請稍後再試。';
      return '護照憑證發行失敗，請重新嘗試。';
    }
    if (error is StateError) {
      return error.message;
    }
    return '護照 NFC 驗證暫時無法完成，請稍後再試。';
  }

  @override
  Widget build(BuildContext context) {
    final busy =
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
          '護照號碼不會送出或保存原文，只會產生本機識別值與伺服器去重用的不可逆 UID。',
          textAlign: TextAlign.center,
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: Colors.grey[600]),
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
        if (_phase == _PassportNfcPhase.done)
          FilledButton.icon(
            onPressed: null,
            icon: const Icon(Icons.check_circle),
            label: const Text('護照憑證已加入'),
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
                  ? '發行憑證中'
                  : _phase == _PassportNfcPhase.scanning
                  ? '讀取護照中'
                  : '掃描護照 NFC',
            ),
          ),
      ],
    );
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

  @override
  void dispose() {
    _emailController.dispose();
    _otpController.dispose();
    super.dispose();
  }

  Future<void> _requestOtp() async {
    final email = _emailController.text.trim();
    if (!_isValidEmail(email)) {
      setState(() => _errorMessage = '請輸入有效的 Email 地址。');
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
      setState(() => _errorMessage = '請輸入驗證碼。');
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
          return '驗證碼不正確，請重新輸入。';
        case 'expired_otp':
          return '驗證碼已逾期，請重新申請。';
        case 'invalid_email':
          return 'Email 格式無效，請重新輸入。';
        case 'invalid_did':
          return 'DID 格式無效，請重新啟動。';
      }
      if (error.statusCode >= 500) return '發行伺服器暫時無法使用，請稍後再試。';
    }
    if (error is AtProtoException) {
      switch (error.error) {
        case 'invalid_vp':
        case 'invalid_vc':
          return '憑證驗證失敗，請重新嘗試。';
        case 'vc_expired':
          return '憑證已逾期，請重新取得。';
        case 'already_verified':
          return '此帳號已完成驗證。';
      }
      if (error.statusCode >= 500) return 'Relay 暫時無法使用，請稍後再試。';
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
          'Email 聯絡方式驗證',
          textAlign: TextAlign.center,
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Text(
          '驗證 Email 後可取得聯絡方式驗證狀態',
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
          decoration: const InputDecoration(
            labelText: 'Email 地址',
            prefixIcon: Icon(Icons.email_outlined),
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
            decoration: const InputDecoration(
              labelText: '6 位數驗證碼',
              prefixIcon: Icon(Icons.pin_outlined),
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
          'Email 地址不會上傳至伺服器記錄\n憑證加密存於裝置本地',
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
        label: const Text('發送驗證碼'),
      );
    }

    if (_phase == _EmailOtpPhase.waitingOtp) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FilledButton.icon(
            onPressed: _submitOtp,
            icon: const Icon(Icons.check),
            label: const Text('驗證並取得憑證'),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => setState(() {
              _phase = _EmailOtpPhase.idle;
              _otpController.clear();
              _errorMessage = null;
            }),
            child: const Text('重新發送驗證碼'),
          ),
        ],
      );
    }

    if (_phase == _EmailOtpPhase.done) {
      return FilledButton.icon(
        onPressed: null,
        icon: const Icon(Icons.check_circle),
        label: const Text('憑證已加入'),
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
          : const Text('請稍候…'),
    );
  }

  Widget _buildPhaseIndicator() {
    if (_phase == _EmailOtpPhase.idle) return const SizedBox.shrink();

    final steps = [
      (label: '📧 發送驗證碼', phase: _EmailOtpPhase.requesting),
      (label: '🔢 輸入驗證碼', phase: _EmailOtpPhase.waitingOtp),
      (label: '📜 取得憑證', phase: _EmailOtpPhase.issuing),
      (label: '☁️ 提交 Relay', phase: _EmailOtpPhase.presenting),
      (label: '✅ 信任等級升級', phase: _EmailOtpPhase.done),
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
