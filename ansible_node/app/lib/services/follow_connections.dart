import 'package:ansible_store/ansible_store.dart';

import 'handle_resolver.dart' show shortenDid;

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
  String get shortDid => shortenDid(did);
  String? get handleLabel => handle == null
      ? null
      : handle!.startsWith('@')
      ? handle
      : '@$handle';
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
      String? nonBlank(String? value) {
        final trimmed = value?.trim();
        return trimmed == null || trimmed.isEmpty ? null : trimmed;
      }

      // Older follow/contact records may store a DID fallback as displayName.
      // Such placeholders must not outrank an available human-readable handle.
      String? displayName(String? value) {
        final name = nonBlank(value);
        return name == peer ||
                name == shortenDid(peer) ||
                name == contact?.shortDid ||
                name == target?.canonicalUri
            ? null
            : name;
      }

      final name =
          displayName(contact?.displayName) ?? displayName(target?.displayName);
      final handle = nonBlank(contact?.handle) ?? nonBlank(target?.handle);
      final connection = FollowConnection(
        did: peer,
        name:
            name ??
            (handle == null
                ? shortenDid(peer)
                : handle.startsWith('@')
                ? handle
                : '@$handle'),
        handle: handle,
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
