import '../../entities/reaction.dart';
import '../reaction_repository.dart';

class InMemoryReactionRepository implements ReactionRepository {
  final Map<String, Reaction> _reactions = {};

  @override
  Future<void> create(Reaction reaction) async {
    _reactions[reaction.id] = reaction;
  }

  @override
  Future<void> delete(String id) async {
    _reactions.remove(id);
  }

  @override
  Future<List<Reaction>> listByTarget(String targetType, String targetId) async {
    return _reactions.values
        .where((r) => r.targetType.name == targetType && r.targetId == targetId)
        .toList();
  }

  @override
  Future<Reaction?> getByUserAndTarget(
      String userId, String targetType, String targetId) async {
    for (final reaction in _reactions.values) {
      if (reaction.userId == userId &&
          reaction.targetType.name == targetType &&
          reaction.targetId == targetId) {
        return reaction;
      }
    }
    return null;
  }
}
