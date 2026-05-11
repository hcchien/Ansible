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

    await controller.setPreference(AppLocalePreference.ja);

    expect(controller.preference, AppLocalePreference.ja);
    expect(controller.locale?.languageCode, 'ja');

    final restored = AppLocaleController(store: store);
    await restored.load();

    expect(restored.preference, AppLocalePreference.ja);
    expect(restored.locale?.languageCode, 'ja');
  });

  test('maps first phase locale preferences', () {
    expect(AppLocalePreference.zhHant.locale?.languageCode, 'zh');
    expect(AppLocalePreference.zhHant.locale?.scriptCode, 'Hant');
    expect(AppLocalePreference.en.locale?.languageCode, 'en');
    expect(AppLocalePreference.ja.locale?.languageCode, 'ja');
    expect(AppLocalePreference.de.locale?.languageCode, 'de');
    expect(AppLocalePreference.ko.locale?.languageCode, 'ko');
    expect(AppLocalePreference.es.locale?.languageCode, 'es');
    expect(AppLocalePreference.fr.locale?.languageCode, 'fr');
    expect(AppLocalePreference.pt.locale?.languageCode, 'pt');
  });
}
