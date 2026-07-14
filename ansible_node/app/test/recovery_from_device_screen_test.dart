import 'dart:io';

import 'package:ansible_node/screens/recovery_from_device_screen.dart';
import 'package:ansible_node/services/atproto_client.dart';
import 'package:ansible_node/services/recovery_approval_service.dart';
import 'package:ansible_node/services/relay_anchor_client.dart';
import 'package:ansible_store/ansible_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Never touches the network: overrides the two methods the screen calls.
/// [request] null models "handle resolved but the relay has no active anchor".
class _FakeApprovalService extends RecoveryApprovalService {
  _FakeApprovalService(this.request)
    : super(relayClient: RelayAnchorClient(baseUrl: 'http://localhost:1'));

  final RecoveryApprovalRequest? request;

  @override
  Future<RecoveryApprovalRequest?> buildRequest({
    required String did,
    required String handle,
  }) async => request;

  @override
  Future<PendingAnchor?> pendingFor(String did) async => null;
}

Future<void> _pumpBuildStep(
  WidgetTester tester, {
  required Future<String> Function(String) handleResolver,
  RecoveryApprovalRequest? request,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: RecoveryFromDeviceScreen(
        installRecoveredKey: (_) async {},
        service: _FakeApprovalService(request),
        handleResolver: handleResolver,
      ),
    ),
  );
  await tester.enterText(
    find.byKey(const Key('recovery_from_device_handle')),
    'hcchien.elix.cool',
  );
  await tester.tap(find.byKey(const Key('recovery_from_device_build')));
  await tester.pump();
  await tester.pump();
}

void errorMessageTests() {
  testWidgets('unknown handle (404) shows a handle-not-found message', (
    tester,
  ) async {
    await _pumpBuildStep(
      tester,
      handleResolver: (_) async => throw const AtProtoException(
        statusCode: 404,
        error: 'handle_not_found',
      ),
    );
    expect(find.textContaining('找不到這個 handle'), findsOneWidget);
  });

  testWidgets('unreachable relay shows a connection error, not handle-not-found',
      (tester) async {
    await _pumpBuildStep(
      tester,
      handleResolver: (_) async =>
          throw const SocketException('Connection refused'),
    );
    expect(find.textContaining('連不到伺服器'), findsOneWidget);
    expect(find.textContaining('找不到這個 handle'), findsNothing);
  });

  testWidgets('resolved handle with no active anchor explains the legacy case',
      (tester) async {
    await _pumpBuildStep(
      tester,
      handleResolver: (_) async => 'did:plc:fpgqc2vajbhtqwwwo5ue5xozmu',
      request: null, // buildRequest returns null → no anchor on the relay
    );
    expect(find.textContaining('還沒有身分 anchor'), findsOneWidget);
    expect(find.textContaining('找不到這個 handle'), findsNothing);
  });
}

void main() {
  errorMessageTests();

  testWidgets('copy button puts the full QR payload on the clipboard', (
    tester,
  ) async {
    final deviceKey = await DeviceKey.generate();
    final request = RecoveryApprovalRequest(
      anchor: IdentityAnchor(
        did: 'did:plc:abc23456789',
        handle: 'tris.elix.cool',
        identityKey: 'ab12cd34ef56ab78ab12cd34ef56ab78',
        alsoKnownAs: const [],
        custodyClass: CustodyClass.software,
        devices: const [],
        prevAnchorCid: 'prevcid',
        reason: AnchorReason.recovery,
        createdAt: DateTime.utc(2026, 7, 14),
        sig: 'sig',
      ),
      identitySeedHex: 'aa' * 32,
      deviceKey: deviceKey,
    );

    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String?;
        }
        return null;
      },
    );

    await tester.pumpWidget(
      MaterialApp(
        home: RecoveryFromDeviceScreen(
          installRecoveredKey: (_) async {},
          service: _FakeApprovalService(request),
          handleResolver: (_) async => 'did:plc:abc23456789',
        ),
      ),
    );

    await tester.enterText(
      find.byKey(const Key('recovery_from_device_handle')),
      'tris.elix.cool',
    );
    await tester.tap(find.byKey(const Key('recovery_from_device_build')));
    await tester.pump();
    await tester.pump();

    final copyButton = find.byKey(
      const Key('recovery_from_device_copy_button'),
    );
    await tester.scrollUntilVisible(
      copyButton,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(copyButton);
    await tester.pump();

    expect(copied, request.toQrPayload());

    // Tear the screen down so the pending poll timer is cancelled.
    await tester.pumpWidget(const SizedBox());
  });
}
