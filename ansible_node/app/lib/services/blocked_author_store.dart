import 'package:shared_preferences/shared_preferences.dart';

/// Reversible, device-local author blocks. The owning DID is part of the key so
/// multiple identities on one device never inherit one another's block list.
class BlockedAuthorStore {
  const BlockedAuthorStore();

  String _key(String ownerDid) => 'elix.blocked-authors.v1.$ownerDid';

  Future<Set<String>> load(String ownerDid) async {
    final preferences = await SharedPreferences.getInstance();
    return (preferences.getStringList(_key(ownerDid)) ?? const <String>[])
        .where((did) => did.trim().isNotEmpty)
        .toSet();
  }

  Future<bool> isBlocked(String ownerDid, String subjectDid) async {
    return (await load(ownerDid)).contains(subjectDid);
  }

  Future<void> block(String ownerDid, String subjectDid) async {
    if (ownerDid == subjectDid || subjectDid.trim().isEmpty) return;
    final preferences = await SharedPreferences.getInstance();
    final blocked = await load(ownerDid);
    blocked.add(subjectDid);
    final sorted = blocked.toList()..sort();
    await preferences.setStringList(_key(ownerDid), sorted);
  }

  Future<void> unblock(String ownerDid, String subjectDid) async {
    final preferences = await SharedPreferences.getInstance();
    final blocked = await load(ownerDid);
    blocked.remove(subjectDid);
    final sorted = blocked.toList()..sort();
    await preferences.setStringList(_key(ownerDid), sorted);
  }
}
