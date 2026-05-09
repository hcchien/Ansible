import 'package:ansible_store/ansible_store.dart';

import 'nostr_event.dart';

class NostrProjectionException implements Exception {
  final String message;

  const NostrProjectionException(this.message);

  @override
  String toString() => 'NostrProjectionException: $message';
}

class NostrContentProjection {
  static NostrEventDraft projectContent(
    ContentItem item, {
    required String pubkey,
  }) {
    _ensureDistributable(item.visibility);
    final createdAt = _unixSeconds(item.publishedAt ?? item.createdAt);

    return switch (item.mode) {
      ContentMode.murmur => NostrEventDraft(
        pubkey: pubkey,
        createdAt: createdAt,
        kind: 1,
        tags: const [],
        content: item.body,
      ),
      ContentMode.note => NostrEventDraft(
        pubkey: pubkey,
        createdAt: createdAt,
        kind: 30023,
        tags: [
          ['d', item.id],
          if (item.title != null && item.title!.trim().isNotEmpty)
            ['title', item.title!.trim()],
          ['published_at', createdAt.toString()],
        ],
        content: item.body,
      ),
      _ => throw NostrProjectionException(
        'Content mode ${item.mode.name} is not supported by Nostr projection.',
      ),
    };
  }

  static NostrEventDraft projectDelete({
    required String contentId,
    required String priorEventId,
    required String pubkey,
    required DateTime deletedAt,
  }) {
    if (!RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(priorEventId)) {
      throw const NostrProjectionException('Prior Nostr event id is invalid.');
    }
    return NostrEventDraft(
      pubkey: pubkey,
      createdAt: _unixSeconds(deletedAt),
      kind: 5,
      tags: [
        ['e', priorEventId.toLowerCase()],
      ],
      content: 'delete $contentId',
    );
  }

  static NostrEventDraft projectFollowList({
    required String pubkey,
    required DateTime updatedAt,
    required List<FollowEdge> edges,
    required List<FollowTarget> targets,
  }) {
    final targetsById = {for (final target in targets) target.targetId: target};
    final tags = <List<String>>[];

    for (final edge in edges) {
      final target = targetsById[edge.targetId];
      if (target == null ||
          edge.direction != FollowDirection.outbound ||
          edge.status != FollowStatus.accepted ||
          edge.visibility != FollowVisibility.federated ||
          edge.targetType != FollowTargetType.user ||
          target.isDeleted) {
        continue;
      }
      final followedPubkey = _nostrPubkeyFromTarget(target);
      if (followedPubkey == null) continue;
      tags.add([
        'p',
        followedPubkey,
        if (target.canonicalUri?.startsWith('wss://') == true)
          target.canonicalUri!
        else
          '',
        target.displayName,
      ]);
    }

    return NostrEventDraft(
      pubkey: pubkey,
      createdAt: _unixSeconds(updatedAt),
      kind: 3,
      tags: tags,
      content: '',
    );
  }

  static NostrEventDraft projectRelayList({
    required String pubkey,
    required DateTime updatedAt,
    required List<NostrRelayPreference> relays,
  }) {
    return NostrEventDraft(
      pubkey: pubkey,
      createdAt: _unixSeconds(updatedAt),
      kind: 10002,
      tags: [
        for (final relay in relays)
          [
            'r',
            relay.url,
            if (relay.read != relay.write) relay.read ? 'read' : 'write',
          ],
      ],
      content: '',
    );
  }

  static void _ensureDistributable(ContentVisibility visibility) {
    if (visibility == ContentVisibility.private) {
      throw const NostrProjectionException(
        'Private content cannot be projected to Nostr.',
      );
    }
  }

  static int _unixSeconds(DateTime value) {
    return value.toUtc().millisecondsSinceEpoch ~/ 1000;
  }

  static String? _nostrPubkeyFromTarget(FollowTarget target) {
    final did = target.did;
    if (did == null || !did.startsWith('did:nostr:')) return null;
    final pubkey = did.substring('did:nostr:'.length).toLowerCase();
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(pubkey)) return null;
    return pubkey;
  }
}

class NostrRelayPreference {
  final String url;
  final bool read;
  final bool write;

  const NostrRelayPreference({
    required this.url,
    this.read = false,
    this.write = false,
  }) : assert(read || write, 'Relay preference must enable read or write');
}
