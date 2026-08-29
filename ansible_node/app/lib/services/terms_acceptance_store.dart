import 'package:shared_preferences/shared_preferences.dart';

/// Versioned local proof that the user explicitly accepted the community
/// Terms/EULA before registering or resuming an existing identity.
class TermsAcceptanceStore {
  static const currentVersion = '2026-08-29';
  static const preferenceKey = 'elix.terms.accepted.version';

  const TermsAcceptanceStore();

  Future<bool> hasAcceptedCurrent() async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getString(preferenceKey) == currentVersion;
  }

  Future<void> acceptCurrent() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(preferenceKey, currentVersion);
  }
}
