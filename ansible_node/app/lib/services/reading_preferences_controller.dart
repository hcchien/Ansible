import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme/ansible_design.dart';

enum ReadingTextScalePreference {
  small('small', 1.0),
  standard('standard', AnsibleDesign.appTextScale),
  large('large', 1.18),
  extraLarge('extraLarge', 1.3);

  const ReadingTextScalePreference(this.storageValue, this.scale);

  final String storageValue;
  final double scale;

  static ReadingTextScalePreference parse(String? value) {
    return ReadingTextScalePreference.values.firstWhere(
      (preference) => preference.storageValue == value,
      orElse: () => ReadingTextScalePreference.standard,
    );
  }
}

abstract class ReadingPreferencesStore {
  Future<String?> loadTextScale();
  Future<void> saveTextScale(String value);
}

class SharedPreferencesReadingPreferencesStore
    implements ReadingPreferencesStore {
  const SharedPreferencesReadingPreferencesStore();

  static const textScaleKey = 'elix-reading-text-scale';

  @override
  Future<String?> loadTextScale() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(textScaleKey);
  }

  @override
  Future<void> saveTextScale(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(textScaleKey, value);
  }
}

class InMemoryReadingPreferencesStore implements ReadingPreferencesStore {
  InMemoryReadingPreferencesStore({String? textScale}) : _textScale = textScale;

  String? _textScale;

  @override
  Future<String?> loadTextScale() async => _textScale;

  @override
  Future<void> saveTextScale(String value) async {
    _textScale = value;
  }
}

class ReadingPreferencesController extends ChangeNotifier {
  ReadingPreferencesController({
    ReadingPreferencesStore store =
        const SharedPreferencesReadingPreferencesStore(),
  }) : _store = store;

  final ReadingPreferencesStore _store;

  ReadingTextScalePreference _textScale = ReadingTextScalePreference.standard;
  bool _loaded = false;

  ReadingTextScalePreference get textScale => _textScale;
  double get textScaleFactor => _textScale.scale;
  bool get loaded => _loaded;

  Future<void> load() async {
    final saved = await _store.loadTextScale();
    _textScale = ReadingTextScalePreference.parse(saved);
    _loaded = true;
    notifyListeners();
  }

  Future<void> setTextScale(ReadingTextScalePreference preference) async {
    if (_textScale == preference && _loaded) return;
    _textScale = preference;
    _loaded = true;
    notifyListeners();
    await _store.saveTextScale(preference.storageValue);
  }
}
