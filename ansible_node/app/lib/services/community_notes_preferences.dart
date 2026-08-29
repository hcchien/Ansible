import 'package:shared_preferences/shared_preferences.dart';

abstract class CommunityNotesPreferencesStore {
  Future<bool> showCommunityNotes();

  Future<void> setShowCommunityNotes(bool value);
}

class SharedPreferencesCommunityNotesPreferencesStore
    implements CommunityNotesPreferencesStore {
  const SharedPreferencesCommunityNotesPreferencesStore();

  static const preferenceKey = 'community_notes.show';

  @override
  Future<bool> showCommunityNotes() async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getBool(preferenceKey) ?? true;
  }

  @override
  Future<void> setShowCommunityNotes(bool value) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(preferenceKey, value);
  }
}
