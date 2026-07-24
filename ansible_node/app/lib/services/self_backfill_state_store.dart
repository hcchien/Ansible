import 'package:shared_preferences/shared_preferences.dart';

/// Device-local checkpoint for the one-time replay that restores content the
/// current DID explicitly published to a Relay.
///
/// This is deliberately not a server-side backup flag. Deleting the app
/// deletes the checkpoint, so a clean install replays the Relay log again.
abstract class SelfBackfillStateStore {
  Future<bool> isComplete({required String remoteNodeId, required String did});

  Future<void> markComplete({
    required String remoteNodeId,
    required String did,
  });
}

class SharedPreferencesSelfBackfillStateStore
    implements SelfBackfillStateStore {
  const SharedPreferencesSelfBackfillStateStore();

  // v2 replays histories once more after legacy raw P-256 signatures became
  // verifiable by the app. Keeping the version in the key makes the migration
  // retryable without mutating or deleting the user's existing local data.
  static const _keyPrefix = 'elix-relay-self-backfill-v2';

  String _key(String remoteNodeId, String did) =>
      '$_keyPrefix::$remoteNodeId::$did';

  @override
  Future<bool> isComplete({
    required String remoteNodeId,
    required String did,
  }) async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getBool(_key(remoteNodeId, did)) ?? false;
  }

  @override
  Future<void> markComplete({
    required String remoteNodeId,
    required String did,
  }) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_key(remoteNodeId, did), true);
  }
}

/// Compatibility default for service-level callers that do not opt in to the
/// application lifecycle checkpoint. Production AppSync injects the persistent
/// store explicitly.
class CompletedSelfBackfillStateStore implements SelfBackfillStateStore {
  const CompletedSelfBackfillStateStore();

  @override
  Future<bool> isComplete({
    required String remoteNodeId,
    required String did,
  }) async => true;

  @override
  Future<void> markComplete({
    required String remoteNodeId,
    required String did,
  }) async {}
}

class InMemorySelfBackfillStateStore implements SelfBackfillStateStore {
  InMemorySelfBackfillStateStore({bool complete = false})
    : _complete = complete;

  bool _complete;
  int markCompleteCalls = 0;

  @override
  Future<bool> isComplete({
    required String remoteNodeId,
    required String did,
  }) async => _complete;

  @override
  Future<void> markComplete({
    required String remoteNodeId,
    required String did,
  }) async {
    _complete = true;
    markCompleteCalls++;
  }
}
