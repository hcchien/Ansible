import '../entities/reaction.dart';

abstract class ReactionRepository {
  Future<void> create(Reaction reaction);
  Future<void> delete(String id);
  Future<List<Reaction>> listByTarget(String targetType, String targetId);
  Future<Reaction?> getByUserAndTarget(String userId, String targetType, String targetId);
}
