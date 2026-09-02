import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Notification categories the user can toggle. Phase A drives the local
/// projector; Phase B will reuse the same categories for push opt-ins.
enum NotificationCategory {
  reply('reply'),
  mention('mention'),
  follow('follow'),
  messenger('messenger');

  const NotificationCategory(this.storageValue);

  final String storageValue;
}

abstract class NotificationPreferencesStore {
  /// Returns null when the user never changed the category (defaults to on).
  Future<bool?> loadEnabled(NotificationCategory category);
  Future<void> saveEnabled(NotificationCategory category, bool enabled);
}

class SharedPreferencesNotificationPreferencesStore
    implements NotificationPreferencesStore {
  const SharedPreferencesNotificationPreferencesStore();

  static String keyFor(NotificationCategory category) =>
      'elix-notification-pref.${category.storageValue}';

  @override
  Future<bool?> loadEnabled(NotificationCategory category) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(keyFor(category));
  }

  @override
  Future<void> saveEnabled(NotificationCategory category, bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(keyFor(category), enabled);
  }
}

class InMemoryNotificationPreferencesStore
    implements NotificationPreferencesStore {
  InMemoryNotificationPreferencesStore({
    Map<NotificationCategory, bool>? enabled,
  }) : _enabled = {...?enabled};

  final Map<NotificationCategory, bool> _enabled;

  @override
  Future<bool?> loadEnabled(NotificationCategory category) async =>
      _enabled[category];

  @override
  Future<void> saveEnabled(NotificationCategory category, bool enabled) async {
    _enabled[category] = enabled;
  }
}

/// Per-category notification preferences. Every category defaults to on;
/// persisted through [NotificationPreferencesStore] (SharedPreferences in
/// the app, in-memory in tests) following the reading-preferences pattern.
class NotificationPreferencesController extends ChangeNotifier {
  NotificationPreferencesController({
    NotificationPreferencesStore store =
        const SharedPreferencesNotificationPreferencesStore(),
  }) : _store = store;

  final NotificationPreferencesStore _store;

  final Map<NotificationCategory, bool> _enabled = {
    for (final category in NotificationCategory.values) category: true,
  };
  bool _loaded = false;

  bool get loaded => _loaded;

  bool isEnabled(NotificationCategory category) => _enabled[category] ?? true;

  Future<void> load() async {
    for (final category in NotificationCategory.values) {
      _enabled[category] = await _store.loadEnabled(category) ?? true;
    }
    _loaded = true;
    notifyListeners();
  }

  /// Loads (once) and answers whether [category] is enabled. Used by the
  /// projector so it always respects the persisted preference.
  Future<bool> categoryEnabled(NotificationCategory category) async {
    if (!_loaded) await load();
    return isEnabled(category);
  }

  Future<void> setEnabled(NotificationCategory category, bool enabled) async {
    if (_loaded && _enabled[category] == enabled) return;
    _enabled[category] = enabled;
    _loaded = true;
    notifyListeners();
    await _store.saveEnabled(category, enabled);
  }
}
