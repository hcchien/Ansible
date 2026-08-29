import 'package:ansible_node/services/community_notes_preferences.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const store = SharedPreferencesCommunityNotesPreferencesStore();

  test(
    'Community Notes are visible by default and preference is local',
    () async {
      SharedPreferences.setMockInitialValues({});

      expect(await store.showCommunityNotes(), isTrue);
      await store.setShowCommunityNotes(false);

      expect(await store.showCommunityNotes(), isFalse);
    },
  );
}
