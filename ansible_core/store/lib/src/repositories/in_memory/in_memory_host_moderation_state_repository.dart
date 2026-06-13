import '../../entities/host_moderation_state.dart';
import '../host_moderation_state_repository.dart';

class InMemoryHostModerationStateRepository
    implements HostModerationStateRepository {
  /// localBoardId → (targetKind:targetRef → entry).
  final Map<String, Map<String, HostModerationState>> _byBoard = {};

  @override
  Future<List<HostModerationState>> replaceForBoard(
    String localBoardId,
    List<HostModerationState> entries,
  ) async {
    final previousKeys = (_byBoard[localBoardId]?.values ??
            const Iterable<HostModerationState>.empty())
        .map((entry) => entry.diffKey)
        .toSet();

    final next = <String, HostModerationState>{};
    for (final entry in entries) {
      next.putIfAbsent('${entry.targetKind}:${entry.targetRef}', () => entry);
    }
    _byBoard[localBoardId] = next;

    return next.values
        .where((entry) => !previousKeys.contains(entry.diffKey))
        .toList();
  }

  @override
  Future<List<HostModerationState>> listForBoard(String localBoardId) async {
    return (_byBoard[localBoardId]?.values.toList() ??
        const <HostModerationState>[]);
  }

  @override
  Future<HostModerationState?> entryFor(
    String targetKind,
    String targetRef,
  ) async {
    for (final board in _byBoard.values) {
      final entry = board['$targetKind:$targetRef'];
      if (entry != null) return entry;
    }
    return null;
  }
}
