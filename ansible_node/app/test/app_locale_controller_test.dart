import 'package:ansible_node/services/app_locale_controller.dart';
import 'package:ansible_node/l10n/app_l10n.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('defaults to system locale preference', () async {
    final store = InMemoryAppLocalePreferenceStore();
    final controller = AppLocaleController(store: store);

    await controller.load();

    expect(controller.preference, AppLocalePreference.system);
    expect(controller.locale, isNull);
  });

  test('persists selected locale preference', () async {
    final store = InMemoryAppLocalePreferenceStore();
    final controller = AppLocaleController(store: store);

    await controller.setPreference(AppLocalePreference.en);

    expect(controller.preference, AppLocalePreference.en);
    expect(controller.locale?.languageCode, 'en');

    final restored = AppLocaleController(store: store);
    await restored.load();

    expect(restored.preference, AppLocalePreference.en);
    expect(restored.locale?.languageCode, 'en');
  });

  test('maps supported locale preferences', () {
    expect(AppLocalePreference.zhHant.locale?.languageCode, 'zh');
    expect(AppLocalePreference.zhHant.locale?.scriptCode, 'Hant');
    expect(AppLocalePreference.en.locale?.languageCode, 'en');
    expect(AppLocalePreference.fr.locale?.languageCode, 'fr');
    expect(AppLocalePreference.es.locale?.languageCode, 'es');
    expect(AppLocalePreference.ja.locale?.languageCode, 'ja');
    expect(AppLocalePreference.ko.locale?.languageCode, 'ko');
    expect(AppLocalePreference.de.locale?.languageCode, 'de');
    expect(AppLocalePreference.it.locale?.languageCode, 'it');
    expect(AppLocalePreference.system.locale, isNull);
    expect(AppLocalePreference.values.length, 9);
  });

  test('legacy discovery and settings copy is localized in Japanese', () {
    expect(localizeUiCopy('ja', '← Back'), '← 戻る');
    expect(
      localizeUiCopy('ja', 'Search people, boards, posts'),
      'ユーザー、ボード、投稿を検索',
    );
    expect(localizeUiCopy('ja', 'Recover account'), 'アカウントを復旧');
    expect(localizeUiCopy('ja', 'External content'), '外部コンテンツ');
  });
}
