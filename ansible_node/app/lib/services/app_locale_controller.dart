import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

enum AppLocalePreference {
  system('system'),
  zhHant('zh-Hant'),
  en('en'),
  ja('ja'),
  de('de'),
  ko('ko'),
  es('es'),
  fr('fr'),
  pt('pt');

  const AppLocalePreference(this.storageValue);

  final String storageValue;

  Locale? get locale {
    return switch (this) {
      AppLocalePreference.system => null,
      AppLocalePreference.zhHant => const Locale.fromSubtags(
        languageCode: 'zh',
        scriptCode: 'Hant',
      ),
      AppLocalePreference.en => const Locale('en'),
      AppLocalePreference.ja => const Locale('ja'),
      AppLocalePreference.de => const Locale('de'),
      AppLocalePreference.ko => const Locale('ko'),
      AppLocalePreference.es => const Locale('es'),
      AppLocalePreference.fr => const Locale('fr'),
      AppLocalePreference.pt => const Locale('pt'),
    };
  }

  String get nativeName {
    return switch (this) {
      AppLocalePreference.system => 'System',
      AppLocalePreference.zhHant => '繁體中文',
      AppLocalePreference.en => 'English',
      AppLocalePreference.ja => '日本語',
      AppLocalePreference.de => 'Deutsch',
      AppLocalePreference.ko => '한국어',
      AppLocalePreference.es => 'Español',
      AppLocalePreference.fr => 'Français',
      AppLocalePreference.pt => 'Português',
    };
  }

  static AppLocalePreference parse(String? value) {
    return AppLocalePreference.values.firstWhere(
      (preference) => preference.storageValue == value,
      orElse: () => AppLocalePreference.system,
    );
  }
}

abstract class AppLocalePreferenceStore {
  Future<String?> read();
  Future<void> write(String value);
}

class SecureStorageAppLocalePreferenceStore
    implements AppLocalePreferenceStore {
  static const storageKey = 'ansible_app_locale_preference';

  const SecureStorageAppLocalePreferenceStore({
    FlutterSecureStorage? secureStorage,
  }) : _secureStorage = secureStorage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _secureStorage;

  @override
  Future<String?> read() => _secureStorage.read(key: storageKey);

  @override
  Future<void> write(String value) =>
      _secureStorage.write(key: storageKey, value: value);
}

class InMemoryAppLocalePreferenceStore implements AppLocalePreferenceStore {
  String? _value;

  @override
  Future<String?> read() async => _value;

  @override
  Future<void> write(String value) async {
    _value = value;
  }
}

class AppLocaleController extends ChangeNotifier {
  AppLocaleController({AppLocalePreferenceStore? store})
    : _store = store ?? const SecureStorageAppLocalePreferenceStore();

  static const supportedLocales = [
    Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
    Locale('en'),
    Locale('ja'),
    Locale('de'),
    Locale('ko'),
    Locale('es'),
    Locale('fr'),
    Locale('pt'),
  ];

  final AppLocalePreferenceStore _store;

  AppLocalePreference _preference = AppLocalePreference.system;
  bool _loaded = false;

  AppLocalePreference get preference => _preference;
  Locale? get locale => _preference.locale;
  bool get loaded => _loaded;

  Future<void> load() async {
    try {
      _preference = AppLocalePreference.parse(await _store.read());
    } catch (_) {
      _preference = AppLocalePreference.system;
    }
    _loaded = true;
    notifyListeners();
  }

  Future<void> setPreference(AppLocalePreference preference) async {
    if (_preference == preference && _loaded) return;
    _preference = preference;
    _loaded = true;
    await _store.write(preference.storageValue);
    notifyListeners();
  }
}
