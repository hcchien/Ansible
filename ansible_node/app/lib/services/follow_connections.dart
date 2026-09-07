import 'package:ansible_store/ansible_store.dart';

class FollowConnection {
  const FollowConnection({
    required this.did,
    required this.name,
    this.handle,
    required this.edge,
  });
  final String did;
  final String name;
  final String? handle;
  final FollowEdge edge;
  bool get pending => edge.status == FollowStatus.pending;
  bool get localOnly => edge.visibility == FollowVisibility.localOnly;
}

class FollowConnections {
  const FollowConnections(this.following, this.followers);
  final List<FollowConnection> following;
  final List<FollowConnection> followers;
  int get followingCount => following.where((p) => !p.pending).length;
  int get followerCount => followers.where((p) => !p.pending).length;
}

/// Own local relationship state. Never exports local-only follows or infers an
/// accepted relationship from a request. Viewing this list sends no network data.
Future<FollowConnections> loadFollowConnections(
  AppDatabase db,
  String did,
) async {
  final repo = DriftFollowRepository(db);
  final contacts = DriftContactRepository(db);
  final outbound = await repo.listOutbound(
    did,
    targetType: FollowTargetType.user,
  );
  final self = await repo.getTargetByCanonicalUri(did);
  final inbound = self == null
      ? <FollowEdge>[]
      : await repo.listInbound(self.targetId);
  bool visible(FollowEdge edge) =>
      edge.targetType == FollowTargetType.user &&
      (edge.status == FollowStatus.accepted ||
          edge.status == FollowStatus.pending);
  Future<List<FollowConnection>> people(
    List<FollowEdge> edges,
    bool incoming,
  ) async {
    final result = <String, FollowConnection>{};
    for (final edge in edges.where(visible)) {
      final target = incoming
          ? await repo.getTargetByCanonicalUri(edge.followerDid)
          : await repo.getTarget(edge.targetId);
      if (target?.isDeleted == true) continue;
      final peer = incoming
          ? edge.followerDid
          : target?.did ?? target?.canonicalUri;
      if (peer == null || peer.isEmpty || peer == did) continue;
      final contact = await contacts.contactForDid(peer);
      final name = contact?.displayName?.trim();
      final targetName = target?.displayName.trim();
      final connection = FollowConnection(
        did: peer,
        name: name?.isNotEmpty == true
            ? name!
            : targetName?.isNotEmpty == true
            ? targetName!
            : peer,
        handle: contact?.handle ?? target?.handle,
        edge: edge,
      );
      if (result[peer] == null || result[peer]!.pending) {
        result[peer] = connection;
      }
    }
    return result.values.toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }

  return FollowConnections(
    await people(outbound, false),
    await people(inbound, true),
  );
}
