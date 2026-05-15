import 'package:ansible_store/ansible_store.dart';

class ContactSourceSyncService {
  ContactSourceSyncService({
    required this.followRepository,
    required this.contactRepository,
    this.messengerRepository,
    DateTime Function()? now,
  }) : now = now ?? (() => DateTime.now().toUtc());

  final FollowRepository followRepository;
  final ContactRepository contactRepository;
  final MessengerRepository? messengerRepository;
  final DateTime Function() now;

  Future<int> syncForIdentity(
    String localDid, {
    String? localUserTargetId,
  }) async {
    final timestamp = now();
    final candidates = <_ContactCandidate>[];

    final following = await followRepository.listFollowing(
      localDid,
      targetType: FollowTargetType.user,
    );
    for (final edge in following) {
      final target = await followRepository.getTarget(edge.targetId);
      if (target == null || target.isDeleted) continue;
      final subjectDid = _clean(target.did);
      if (subjectDid == null || subjectDid == localDid) continue;

      candidates.add(
        _ContactCandidate(
          subjectDid: subjectDid,
          handle: _clean(target.handle),
          displayName: _clean(target.displayName),
          relationship: ContactRelationship.following,
          source: 'follow',
        ),
      );
    }

    final targetId = _clean(localUserTargetId);
    if (targetId != null) {
      final followers = await followRepository.listFollowers(targetId);
      for (final edge in followers) {
        final subjectDid = _clean(edge.followerDid);
        if (subjectDid == null || subjectDid == localDid) continue;
        candidates.add(
          _ContactCandidate(
            subjectDid: subjectDid,
            relationship: ContactRelationship.follower,
            source: 'follow',
          ),
        );
      }
    }

    final conversations = await messengerRepository?.conversationList();
    if (conversations != null) {
      for (final conversation in conversations) {
        final subjectDid = _clean(conversation.peerDid);
        if (subjectDid == null || subjectDid == localDid) continue;
        candidates.add(
          _ContactCandidate(
            subjectDid: subjectDid,
            displayName: _clean(conversation.title),
            relationship: ContactRelationship.conversation,
            source: 'conversation',
          ),
        );
      }
    }

    var synced = 0;
    for (final candidate in _merge(candidates)) {
      await _upsert(candidate, timestamp);
      synced += 1;
    }
    return synced;
  }

  Future<void> _upsert(_ContactCandidate candidate, DateTime timestamp) async {
    final existing = await contactRepository.contactForDid(
      candidate.subjectDid,
    );
    var handle = candidate.handle ?? existing?.handle;
    final contactForHandle = handle == null
        ? null
        : await contactRepository.contactForHandle(handle);
    if (contactForHandle != null &&
        contactForHandle.subjectDid != candidate.subjectDid) {
      await contactRepository.upsertContact(
        _rebuild(
          contactForHandle,
          trustState: ContactTrustState.changed,
          updatedAt: timestamp,
          lastResolvedAt: timestamp,
        ),
      );
      handle = existing?.handle;
    }

    final trustState = existing?.trustState == ContactTrustState.blocked
        ? ContactTrustState.blocked
        : ContactTrustState.known;
    await contactRepository.upsertContact(
      ContactRecord(
        subjectDid: candidate.subjectDid,
        handle: handle,
        displayName: candidate.displayName ?? existing?.displayName,
        localAlias: existing?.localAlias,
        avatarUrl: existing?.avatarUrl,
        relationship: _relationshipFor(existing, candidate.relationship),
        source: candidate.source,
        trustState: trustState,
        messengerAvailability:
            existing?.messengerAvailability ?? MessengerAvailability.unresolved,
        createdAt: existing?.createdAt ?? timestamp,
        updatedAt: timestamp,
        lastResolvedAt: timestamp,
      ),
    );
  }

  ContactRelationship _relationshipFor(
    ContactRecord? existing,
    ContactRelationship next,
  ) {
    if (existing == null ||
        existing.relationship == ContactRelationship.unknown) {
      return next;
    }
    if (existing.relationship == ContactRelationship.blocked) {
      return ContactRelationship.blocked;
    }
    if ((existing.relationship == ContactRelationship.following &&
            next == ContactRelationship.follower) ||
        (existing.relationship == ContactRelationship.follower &&
            next == ContactRelationship.following)) {
      return ContactRelationship.mutual;
    }
    if (existing.relationship == ContactRelationship.conversation &&
        (next == ContactRelationship.following ||
            next == ContactRelationship.follower ||
            next == ContactRelationship.mutual)) {
      return next;
    }
    if (next == ContactRelationship.conversation) {
      return existing.relationship;
    }
    return existing.relationship == ContactRelationship.mutual
        ? ContactRelationship.mutual
        : next;
  }

  List<_ContactCandidate> _merge(List<_ContactCandidate> candidates) {
    final merged = <String, _ContactCandidate>{};
    for (final candidate in candidates) {
      final existing = merged[candidate.subjectDid];
      if (existing == null) {
        merged[candidate.subjectDid] = candidate;
        continue;
      }
      merged[candidate.subjectDid] = existing.merge(candidate);
    }
    return merged.values.toList(growable: false);
  }

  ContactRecord _rebuild(
    ContactRecord contact, {
    ContactTrustState? trustState,
    DateTime? updatedAt,
    DateTime? lastResolvedAt,
  }) {
    return ContactRecord(
      subjectDid: contact.subjectDid,
      handle: contact.handle,
      displayName: contact.displayName,
      localAlias: contact.localAlias,
      avatarUrl: contact.avatarUrl,
      relationship: contact.relationship,
      source: contact.source,
      trustState: trustState ?? contact.trustState,
      messengerAvailability: contact.messengerAvailability,
      createdAt: contact.createdAt,
      updatedAt: updatedAt ?? contact.updatedAt,
      lastResolvedAt: lastResolvedAt ?? contact.lastResolvedAt,
    );
  }

  String? _clean(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    return trimmed;
  }
}

class _ContactCandidate {
  const _ContactCandidate({
    required this.subjectDid,
    this.handle,
    this.displayName,
    required this.relationship,
    required this.source,
  });

  final String subjectDid;
  final String? handle;
  final String? displayName;
  final ContactRelationship relationship;
  final String source;

  _ContactCandidate merge(_ContactCandidate other) {
    return _ContactCandidate(
      subjectDid: subjectDid,
      handle: other.handle ?? handle,
      displayName: other.displayName ?? displayName,
      relationship: _mergeRelationship(relationship, other.relationship),
      source: source == other.source ? source : '$source,${other.source}',
    );
  }

  ContactRelationship _mergeRelationship(
    ContactRelationship a,
    ContactRelationship b,
  ) {
    if ((a == ContactRelationship.following &&
            b == ContactRelationship.follower) ||
        (a == ContactRelationship.follower &&
            b == ContactRelationship.following)) {
      return ContactRelationship.mutual;
    }
    if (a == ContactRelationship.mutual || b == ContactRelationship.mutual) {
      return ContactRelationship.mutual;
    }
    return b;
  }
}
