import 'package:flutter/services.dart';

/// Minimal Dart facade over the pinned native Swoir/Swoirenberg backend.
///
/// Callers must verify artifact hashes before [prepare]. This backend performs
/// no network I/O and keeps witness inputs only for the duration of [prove].
class SwoirZkPassportBackend {
  const SwoirZkPassportBackend();

  static const _channel = MethodChannel('elix/zkpassport_prover');
  static bool _progressHandlerInstalled = false;
  static void Function(String stage)? _planProgressCallback;

  static void _installProgressHandler() {
    if (_progressHandlerInstalled) return;
    _progressHandlerInstalled = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'plan_progress') {
        final stage = call.arguments as String?;
        if (stage != null) _planProgressCallback?.call(stage);
      }
    });
  }

  Future<String> prepare({
    required String manifestJson,
    required int circuitSize,
  }) async {
    final id = await _channel.invokeMethod<String>('prepare', {
      'manifest_json': manifestJson,
      'circuit_size': circuitSize,
    });
    if (id == null || id.isEmpty) {
      throw StateError('Swoir did not return a circuit identifier.');
    }
    return id;
  }

  Future<void> initializeSrs({
    required int circuitSize,
    required String srsPath,
  }) => _channel.invokeMethod<void>('initialize_srs', {
    'circuit_size': circuitSize,
    'srs_path': srsPath,
  });

  Future<Map<String, Object?>> createProofPlan({
    required String runtimeJavaScript,
    required Map<String, Object?> request,
    void Function(String stage)? onProgress,
  }) async {
    _installProgressHandler();
    _planProgressCallback = onProgress;
    try {
      final plan = await _channel.invokeMapMethod<String, Object?>('plan', {
        'runtime_javascript': runtimeJavaScript,
        'request': request,
      });
      if (plan == null) {
        throw StateError('ZKPassport input runtime returned no proof plan.');
      }
      return plan;
    } finally {
      _planProgressCallback = null;
    }
  }

  Future<Uint8List> prove({
    required String circuitId,
    required Map<String, Object?> inputs,
    required Uint8List verificationKey,
  }) async {
    final proof = await _channel.invokeMethod<Uint8List>('prove', {
      'circuit_id': circuitId,
      'inputs': inputs,
      'verification_key': verificationKey,
    });
    if (proof == null || proof.isEmpty) {
      throw StateError('Swoir did not return a proof.');
    }
    return proof;
  }

  Future<bool> verify({
    required String circuitId,
    required Uint8List proof,
    required Uint8List verificationKey,
  }) async =>
      await _channel.invokeMethod<bool>('verify', {
        'circuit_id': circuitId,
        'proof': proof,
        'verification_key': verificationKey,
      }) ??
      false;

  Future<void> clear() => _channel.invokeMethod<void>('clear', const {});
}
