import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persistence seam for the per-user "show external content" opt-in
/// (inbound-federation design D4: conservative default — external content is
/// hidden until the user explicitly opts in). Mirrors the reading- and
/// notification-preferences store pattern.
abstract class ExternalContentPreferencesStore {
  /// Returns null when the user never changed the setting (defaults to OFF).
  Future<bool?> loadShowExternal();
  Future<void> saveShowExternal(bool enabled);
}

class SharedPreferencesExternalContentPreferencesStore
    implements ExternalContentPreferencesStore {
  const SharedPreferencesExternalContentPreferencesStore();

  static const showExternalKey = 'elix-show-external-content';

  @override
  Future<bool?> loadShowExternal() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(showExternalKey);
  }

  @override
  Future<void> saveShowExternal(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(showExternalKey, enabled);
  }
}

class InMemoryExternalContentPreferencesStore
    implements ExternalContentPreferencesStore {
  InMemoryExternalContentPreferencesStore({bool? showExternal})
    : _showExternal = showExternal;

  bool? _showExternal;

  @override
  Future<bool?> loadShowExternal() async => _showExternal;

  @override
  Future<void> saveShowExternal(bool enabled) async {
    _showExternal = enabled;
  }
}

/// Per-user opt-in gate for curated external (fediverse) content. Default OFF
/// (wedge-protective). Effective board visibility =
/// `board.externalInclusion AND showExternal` (inbound-federation D4).
class ExternalContentPreferencesController extends ChangeNotifier {
  ExternalContentPreferencesController({
    ExternalContentPreferencesStore store =
        const SharedPreferencesExternalContentPreferencesStore(),
  }) : _store = store;

  final ExternalContentPreferencesStore _store;

  bool _showExternal = false;
  bool _loaded = false;

  bool get showExternal => _showExternal;
  bool get loaded => _loaded;

  Future<void> load() async {
    _showExternal = await _store.loadShowExternal() ?? false;
    _loaded = true;
    notifyListeners();
  }

  /// Loads (once) and answers whether external content is allowed. Lets the
  /// board view consult the persisted preference without forcing a prior load.
  Future<bool> externalAllowed() async {
    if (!_loaded) await load();
    return _showExternal;
  }

  Future<void> setShowExternal(bool enabled) async {
    if (_loaded && _showExternal == enabled) return;
    _showExternal = enabled;
    _loaded = true;
    notifyListeners();
    await _store.saveShowExternal(enabled);
  }
}
