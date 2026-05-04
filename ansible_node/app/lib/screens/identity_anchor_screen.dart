import 'dart:async';
import 'dart:convert';

import 'package:ansible_did/ansible_did.dart';
import 'package:ansible_vc/ansible_vc.dart';
import 'package:flutter/material.dart';

import '../services/relay_identity_client.dart';

/// Phase 1 — Identity Anchoring screen.
///
/// V1.1 Comp A: guides the user through:
///   1. Passport data via [MockNfcPassportReader]  (real NFC deferred to Q3)
///   2. ZKP proof generation — Rust/arkworks-rs Groth16    ← Q2 LIVE
///   3. Ed25519 keypair generation + did:key encode         ← Q1 LIVE
///   4. DID + ZKP envelope + Nullifier upload to Relay
///   5. Relay marks DID as "Verified" → HomeShell

class IdentityAnchorScreen extends StatefulWidget {
  /// Called with the anchored DID string when Phase 1 completes.
  final void Function(String did) onAnchored;
  final DidManager? didManager;
  final DidSigner? didSigner;
  final RelayIdentityClient? relayClient;

  const IdentityAnchorScreen({
    super.key,
    required this.onAnchored,
    this.didManager,
    this.didSigner,
    this.relayClient,
  });

  @override
  State<IdentityAnchorScreen> createState() => _IdentityAnchorScreenState();
}

class _IdentityAnchorScreenState extends State<IdentityAnchorScreen> {
  _Phase _phase = _Phase.idle;
  String? _errorMessage;

  /// Holds the passport data from a completed NFC scan.
  /// Will be passed to the ZKP prover (Agent B) once wired in Q2.
  PassportData? _passportData;

  late final DidManager _didManager;
  late final DidSigner _didSigner;
  late final RelayIdentityClient _relayClient;
  late final ZkpProver _zkpProver;

  /// Passport reader — always the mock until Q3 NFC hardware support lands.
  final NfcPassportReader _nfcReader = const MockNfcPassportReader();

  @override
  void initState() {
    super.initState();
    _didManager  = widget.didManager  ?? DidManagerImpl();
    _didSigner   = widget.didSigner   ?? DidSignerImpl();
    _relayClient = widget.relayClient ?? RelayIdentityClient();
    _zkpProver   = const ZkpProverImpl();
  }

  Future<void> _startAnchoring() async {
    setState(() {
      _phase = _Phase.nfcScan;
      _errorMessage = null;
      _passportData = null;
    });

    // ── Step 1: NFC passport scan ─────────────────────────────────────────
    // NfcPassportReaderImpl communicates results via callbacks so we bridge
    // them back to async/await with a Completer.
    final completer = Completer<PassportData>();

    await _nfcReader.scan(
      onPassportRead: (data) {
        if (!completer.isCompleted) completer.complete(data);
      },
      onError: (message) {
        if (!completer.isCompleted) {
          completer.completeError(Exception(message));
        }
      },
    );

    try {
      final data = await completer.future;
      if (!mounted) return;
      setState(() {
        _passportData = data;
        _phase = _Phase.generating;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.idle;
        _errorMessage = e is Exception ? e.toString().replaceFirst('Exception: ', '') : e.toString();
      });
      return;
    }

    try {
      // ── Step 2: ZKP proof generation (Q2 LIVE via Rust/arkworks-rs) ─────
      // ZkpProverImpl calls RustLib.instance.apiZkpGenerateProof(), which runs
      // the Groth16 circuit on a Rust thread. Falls back to a dev stub when
      // setup_codegen.sh has not yet been run (UnimplementedError).
      final zkpProof = await _zkpProver.prove(
        passportSecretHex: _passportData?.passportSecret ??
            '0' * 64, // dev fallback when NFC was mocked
      );

      setState(() => _phase = _Phase.uploading);

      // ── Step 3: Generate Ed25519 DID keypair (Q1 LIVE via Rust) ──
      // Stores private key in Secure Enclave / StrongBox.
      // Throws if RustLib has not been initialised or if Secure Enclave is
      // unavailable.  Gracefully falls back to UnimplementedError until
      // setup_codegen.sh has been run.
      late final OwnedDid ownedDid;
      try {
        ownedDid = await _didManager.generate();
      } on UnimplementedError {
        // Codegen not yet run — use a deterministic stub DID so the
        // rest of the UI can be exercised without native crypto.
        ownedDid = const OwnedDid(
          did: 'did:key:z6MkStubRunSetupCodegenToReplaceThis',
          publicKeyHex:
              '0000000000000000000000000000000000000000000000000000000000000001',
        );
      }

      // ── Step 4: Upload anchor request to Relay ────────────────────
      await _anchorWithRelay(ownedDid, zkpProof);

      if (!mounted) return;
      setState(() => _phase = _Phase.done);
      widget.onAnchored(ownedDid.did);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.idle;
        _errorMessage = _formatError(e);
      });
    }
  }

  Future<void> _anchorWithRelay(OwnedDid ownedDid, ZkpProof zkpProof) async {
    final challenge = await _relayClient.issueChallenge(ownedDid.did);
    final signatureHex = await _signChallenge(challenge.challenge);

    await _relayClient.anchor(
      IdentityAnchorRequest(
        did: ownedDid.did,
        zkpProof: zkpProof.proofHex,
        zkpCircuitVersion: ZkpProof.kCircuitVersion,
        verificationKeyHash: 'sha256:${zkpProof.vkHash}',
        nullifier: zkpProof.nullifierHex,
        publicKeyHex: ownedDid.publicKeyHex,
        challenge: challenge.challenge,
        challengeSignatureHex: signatureHex,
      ),
    );
  }

  Future<String> _signChallenge(String challenge) async {
    try {
      final signature = await _didSigner.sign(utf8.encode(challenge));
      return signature.hex;
    } on UnimplementedError {
      return _devSignatureForChallenge(challenge);
    } on StateError {
      return _devSignatureForChallenge(challenge);
    }
  }

  String _devNullifierForDid(String did) {
    return 'dev-nullifier-${base64Url.encode(utf8.encode(did)).replaceAll('=', '')}';
  }

  String _devSignatureForChallenge(String challenge) {
    final encoded = base64Url
        .encode(utf8.encode(challenge))
        .replaceAll('=', '');
    return 'dev-signature-$encoded';
  }

  String _formatError(Object error) {
    if (error is RelayIdentityException) {
      switch (error.error) {
        case 'duplicate_nullifier':
          return '這本護照已完成身份錨定。';
        case 'invalid_challenge_signature':
          return 'Challenge 簽章無效，請重新掃描。';
        case 'invalid_challenge':
        case 'expired_challenge':
          return 'Challenge 已失效，請重新掃描。';
        case 'unsupported_zkp_circuit':
        case 'verification_key_hash_mismatch':
          return 'Relay 不接受目前的 ZKP 版本。';
        case 'missing_required_fields':
          return '身份錨定資料不完整：${error.fields.join(', ')}';
      }
    }
    return error.toString();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.verified_user_outlined,
                  size: 72,
                  color: Color(0xFF1A56A4),
                ),
                const SizedBox(height: 24),
                Text(
                  'Ansible',
                  style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF1A56A4),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '護照身份驗證',
                  style: Theme.of(
                    context,
                  ).textTheme.titleMedium?.copyWith(color: Colors.grey),
                ),
                const SizedBox(height: 40),
                _buildPhaseIndicator(),
                const SizedBox(height: 32),
                if (_errorMessage != null)
                  Container(
                    padding: const EdgeInsets.all(12),
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _errorMessage!,
                      style: TextStyle(color: Colors.red.shade800),
                    ),
                  ),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _phase == _Phase.idle ? _startAnchoring : null,
                    icon: const Icon(Icons.nfc),
                    label: const Text('掃描護照 NFC 晶片'),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  '系統僅驗證「你是真實人類」\n護照號碼與姓名不會被上傳',
                  textAlign: TextAlign.center,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: Colors.grey),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPhaseIndicator() {
    if (_phase == _Phase.idle) return const SizedBox.shrink();

    final steps = [
      (icon: Icons.nfc, label: 'NFC 讀取中', phase: _Phase.nfcScan),
      (icon: Icons.lock_outline, label: 'ZKP 生成中', phase: _Phase.generating),
      (
        icon: Icons.cloud_upload_outlined,
        label: '上傳 Relay',
        phase: _Phase.uploading,
      ),
      (icon: Icons.check_circle_outline, label: '身份錨定完成', phase: _Phase.done),
    ];

    return Column(
      children: steps.map((s) {
        final isDone = _phase.index > s.phase.index;
        final isCurrent = _phase == s.phase;
        return ListTile(
          dense: true,
          leading: isCurrent
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(
                  isDone ? Icons.check_circle : s.icon,
                  color: isDone ? Colors.green : Colors.grey,
                  size: 24,
                ),
          title: Text(
            s.label,
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

enum _Phase { idle, nfcScan, generating, uploading, done }
