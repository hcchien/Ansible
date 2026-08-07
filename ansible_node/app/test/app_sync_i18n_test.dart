import 'package:ansible_node/l10n/subpage_l10n.dart';
import 'package:ansible_node/services/app_sync_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const result = AppSyncResult(
    pulledActivities: 3,
    publishSummary: PublicPublishSummary(
      publicItems: 1,
      enqueued: 1,
      published: 1,
    ),
  );

  test('sync summary is localized for every supported UI language', () {
    const expectedFragments = <String, String>{
      'zh': '同步完成',
      'en': 'Sync complete',
      'fr': 'Synchronisation terminée',
      'es': 'Sincronización completada',
      'ja': '同期完了',
      'ko': '동기화 완료',
      'de': 'Synchronisierung abgeschlossen',
      'it': 'Sincronizzazione completata',
    };

    for (final entry in expectedFragments.entries) {
      final message = appSyncSummaryMessage(
        result,
        text: SubpageL10n(entry.key),
      );
      expect(message, contains(entry.value), reason: entry.key);
      expect(message, isNot(contains('public publish')), reason: entry.key);
    }
  });

  test('sync errors use localized labels while preserving server detail', () {
    const failed = AppSyncResult(
      pulledActivities: 0,
      pullErrors: ['relay: 401'],
      reputationErrors: ['credential expired'],
      publishSummary: PublicPublishSummary(
        publicItems: 1,
        failed: 1,
        errorMessage: 'network_error',
      ),
    );

    final message = appSyncSummaryMessage(
      failed,
      text: const SubpageL10n('ja'),
    );

    expect(message, contains('同期完了'));
    expect(message, contains('取得エラー'));
    expect(message, contains('資格情報エラー'));
    expect(message, contains('relay: 401'));
    expect(message, contains('credential expired'));
    expect(message, isNot(contains('network_error')));
  });

  test('external publication failure does not fail Relay sync', () {
    const result = AppSyncResult(
      pulledActivities: 2,
      publishSummary: PublicPublishSummary(
        publicItems: 1,
        failed: 1,
        errorMessage: 'activity_pub_requires_verified_human',
      ),
    );

    expect(result.success, isTrue);
    expect(
      appSyncSummaryMessage(result, text: const SubpageL10n('zh')),
      isNot(contains('activity_pub_requires_verified_human')),
    );
  });
}
