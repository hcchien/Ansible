import 'dart:convert';

import 'package:ansible_did/ansible_did.dart';
import 'package:test/test.dart';

void main() {
  // The previous dev-stub bridge (hardcoded did:plc) has been replaced by the
  // real flutter_rust_bridge bindings. This test now exercises the real
  // native did:plc creation when the compiled ansible_rust_core library is
  // available, and is skipped in environments that don't build it (e.g. CI
  // without `cargo build`). The real bridge is validated end-to-end on device.
  test('apiCreateDidPlc produces a valid did:plc (native lib required)',
      () async {
    try {
      await RustLib.init();
    } catch (e) {
      markTestSkipped('Native ansible_rust_core library not available: $e');
      return;
    }

    final result = apiCreateDidPlc(
      signingKeyHex: 'ab' * 32,
      handle: 'alice.elix.cool',
      pdsEndpoint: 'https://elix.cool',
    );

    expect(result.did, matches(RegExp(r'^did:plc:[a-z2-7]{10,}$')));
    final genesis = jsonDecode(result.genesisJson) as Map<String, dynamic>;
    expect(genesis, isNotEmpty);
  });
}
