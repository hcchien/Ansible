import '../../entities/content_item.dart';
import '../../entities/identity_binding.dart';
import '../../entities/publication_intent.dart';
import '../../entities/publication_target.dart';
import '../publication_repository.dart';

class InMemoryPublicationRepository implements PublicationRepository {
  final Map<String, PublicationIntent> _intents = {};
  final Map<String, PublicationTarget> _targets = {};
  final Map<String, IdentityBinding> _bindings = {};

  @override
  Future<void> enqueueIntent(
    PublicationIntent intent, {
    List<PublicationTarget> targets = const [],
  }) async {
    _validateIntent(intent);
    for (final target in targets) {
      if (target.intentId != intent.intentId) {
        throw ArgumentError('Publication target must reference intent id');
      }
    }

    _intents[intent.intentId] = intent;
    for (final target in targets) {
      _targets[target.targetId] = target;
    }
  }

  @override
  Future<PublicationIntent?> getIntentById(String intentId) async {
    return _intents[intentId];
  }

  @override
  Future<PublicationTarget?> getTargetById(String targetId) async {
    return _targets[targetId];
  }

  @override
  Future<List<PublicationTarget>> listTargets({
    PublicationProtocol? protocol,
    PublicationStatus? status,
    int limit = 50,
  }) async {
    final targets = _targets.values.where((target) {
      if (protocol != null && target.protocol != protocol) return false;
      if (status != null && target.status != status) return false;
      return true;
    }).toList()..sort((a, b) => a.targetId.compareTo(b.targetId));
    return targets.take(limit).toList();
  }

  @override
  Future<List<PublicationTarget>> listTargetsForIntent(String intentId) async {
    return _targets.values
        .where((target) => target.intentId == intentId)
        .toList()
      ..sort((a, b) => a.targetId.compareTo(b.targetId));
  }

  @override
  Future<List<PublicationTarget>> listPendingTargets({
    PublicationProtocol? protocol,
    int limit = 50,
  }) async {
    final targets =
        _targets.values.where((target) {
          if (target.status != PublicationStatus.pending) return false;
          if (protocol != null && target.protocol != protocol) return false;
          final intent = _intents[target.intentId];
          return intent != null && intent.canDistribute;
        }).toList()..sort((a, b) {
          final aIntent = _intents[a.intentId]!;
          final bIntent = _intents[b.intentId]!;
          final byCreated = aIntent.createdAt.compareTo(bIntent.createdAt);
          return byCreated == 0 ? a.targetId.compareTo(b.targetId) : byCreated;
        });
    return targets.take(limit).toList();
  }

  @override
  Future<void> markTargetPublished(String targetId, {String? remoteId}) async {
    final target = _targets[targetId];
    if (target == null) return;
    _targets[targetId] = PublicationTarget(
      targetId: target.targetId,
      intentId: target.intentId,
      protocol: target.protocol,
      endpoint: target.endpoint,
      status: PublicationStatus.published,
      remoteId: remoteId,
      lastAttemptAt: DateTime.now().toUtc(),
    );
  }

  @override
  Future<void> markTargetFailed(String targetId, String error) async {
    final target = _targets[targetId];
    if (target == null) return;
    _targets[targetId] = target.copyWith(
      status: PublicationStatus.failed,
      lastAttemptAt: DateTime.now().toUtc(),
      error: error,
    );
  }

  @override
  Future<void> resetTargetForRetry(String targetId) async {
    final target = _targets[targetId];
    if (target == null) return;
    _targets[targetId] = PublicationTarget(
      targetId: target.targetId,
      intentId: target.intentId,
      protocol: target.protocol,
      endpoint: target.endpoint,
      status: PublicationStatus.pending,
    );
  }

  @override
  Future<void> markIntentComplete(String intentId) async {
    final intent = _intents[intentId];
    if (intent == null) return;
    _intents[intentId] = intent.copyWith(
      status: PublicationStatus.complete,
      updatedAt: DateTime.now().toUtc(),
      error: '',
    );
  }

  @override
  Future<void> saveIdentityBinding(IdentityBinding binding) async {
    _bindings[binding.bindingId] = binding;
  }

  @override
  Future<List<IdentityBinding>> bindingsForAccount(
    String localAccountDid,
  ) async {
    return _bindings.values
        .where((binding) => binding.localAccountDid == localAccountDid)
        .toList()
      ..sort((a, b) {
        if (a.isPrimary != b.isPrimary) return a.isPrimary ? -1 : 1;
        return a.createdAt.compareTo(b.createdAt);
      });
  }

  void _validateIntent(PublicationIntent intent) {
    if (intent.visibility == ContentVisibility.private) {
      throw ArgumentError('Private content cannot create publication intents');
    }
  }
}
