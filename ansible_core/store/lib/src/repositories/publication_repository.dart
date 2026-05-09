import '../entities/identity_binding.dart';
import '../entities/publication_intent.dart';
import '../entities/publication_target.dart';

abstract class PublicationRepository {
  Future<void> enqueueIntent(
    PublicationIntent intent, {
    List<PublicationTarget> targets = const [],
  });

  Future<PublicationIntent?> getIntentById(String intentId);

  Future<PublicationTarget?> getTargetById(String targetId);

  Future<List<PublicationTarget>> listTargets({
    PublicationProtocol? protocol,
    PublicationStatus? status,
    int limit = 50,
  });

  Future<List<PublicationTarget>> listTargetsForIntent(String intentId);

  Future<List<PublicationTarget>> listPendingTargets({
    PublicationProtocol? protocol,
    int limit = 50,
  });

  Future<void> markTargetPublished(String targetId, {String? remoteId});

  Future<void> markTargetFailed(String targetId, String error);

  Future<void> resetTargetForRetry(String targetId);

  Future<void> markIntentComplete(String intentId);

  Future<void> saveIdentityBinding(IdentityBinding binding);

  Future<List<IdentityBinding>> bindingsForAccount(String localAccountDid);
}
