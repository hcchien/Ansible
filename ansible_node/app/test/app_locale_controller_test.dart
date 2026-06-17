import 'package:ansible_node/services/app_locale_controller.dart';
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
    expect(AppLocalePreference.system.locale, isNull);
    // Only zh-Hant + en are supported (extra locales removed).
    expect(AppLocalePreference.values.length, 3);
  });
}
