import 'package:ansible_node/services/app_sync_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('public publish errors are reported without throwing sync', () async {
    final summary = await bestEffortPublicPublish(
      () async =>
          throw StateError('Relay publication failed: 401 unverified_did'),
    );

    expect(summary.failed, 1);
    expect(summary.errorMessage, contains('Relay publication failed'));
  });
}
