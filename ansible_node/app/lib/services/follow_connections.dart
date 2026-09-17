import 'package:ansible_store/ansible_store.dart';

import 'handle_resolver.dart';

class FollowConnection {
  const FollowConnection({
    required this.did,
    required this.name,
    this.displayName,
    this.handle,
    required this.edge,
  });
  final String did;
  final String name;
  final String? displayName;
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

  FollowConnection withProfile(PublicAuthorProfile? profile) {
    final resolvedName = _displayName(profile?.displayName, did) ?? displayName;
    final resolvedHandle = _nonBlank(profile?.handle) ?? handle;
    return FollowConnection(
      did: did,
      displayName: resolvedName,
      name: _label(did, resolvedName, resolvedHandle),
      handle: resolvedHandle,
      edge: edge,
    );
  }
}

String? _nonBlank(String? value) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}

String? _displayName(String? value, String did) {
  final name = _nonBlank(value);
  return name == did || name == shortenDid(did) ? null : name;
}

String _label(String did, String? name, String? handle) =>
    name ??
    (handle == null
        ? shortenDid(did)
        : handle.startsWith('@')
        ? handle
        : '@$handle');

class FollowConnections {
  const FollowConnections(this.following, this.followers);
  final List<FollowConnection> following;
  final List<FollowConnection> followers;
  int get followingCount => following.where((p) => !p.pending).length;
  int get followerCount => followers.where((p) => !p.pending).length;
}

/// Enrich presentation using the same public profile reads as author bylines.
/// Relationship state stays local: no follow edges, approvals or visibility
/// are submitted, and public metadata is never used as an identity authority.
Future<FollowConnections> resolveFollowConnectionProfiles(
  FollowConnections connections,
  PublicProfileResolver resolver, {
  bool refresh = false,
}) async {
  final peers = {
    for (final person in [...connections.following, ...connections.followers])
      person.did,
  }.toList();
  final profiles = <String, PublicAuthorProfile?>{};
  // Bound concurrent reads for large lists and deduplicate mutual follows.
  for (var offset = 0; offset < peers.length; offset += 6) {
    await Future.wait(
      peers.skip(offset).take(6).map((did) async {
        try {
          profiles[did] = await resolver.profileFor(did, refresh: refresh);
        } catch (_) {
          // Offline or unavailable profiles retain the local fallback.
        }
      }),
    );
  }
  List<FollowConnection> enrich(List<FollowConnection> people) =>
      people.map((person) => person.withProfile(profiles[person.did])).toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  return FollowConnections(
    enrich(connections.following),
    enrich(connections.followers),
  );
}

/// Own local relationship state. Never exports local-only follows or infers an
/// accepted relationship from a request. This local load sends no network data;
/// the list screen separately resolves public presentation metadata.
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
      // Older follow/contact records may store a DID fallback as displayName.
      // Such placeholders must not outrank an available human-readable handle.
      String? displayName(String? value) {
        final name = _nonBlank(value);
        return name == peer ||
                name == shortenDid(peer) ||
                name == contact?.shortDid ||
                name == target?.canonicalUri
            ? null
            : name;
      }

      final name =
          displayName(contact?.displayName) ?? displayName(target?.displayName);
      final handle = _nonBlank(contact?.handle) ?? _nonBlank(target?.handle);
      final connection = FollowConnection(
        did: peer,
        displayName: name,
        name: _label(peer, name, handle),
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
