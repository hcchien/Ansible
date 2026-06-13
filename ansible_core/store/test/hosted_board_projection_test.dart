import 'package:ansible_store/ansible_store.dart';
import 'package:test/test.dart';

void main() {
  HostedBoardProjection projectionWith(Map<String, Object?> postingPolicy) {
    final now = DateTime.utc(2026, 6, 13);
    return HostedBoardProjection(
      localBoardId: 'local-board',
      forumHostId: 'host-1',
      hostedBoardId: 'hosted-1',
      canonicalBoardUri: 'https://relay.example/boards/hosted-1',
      remoteSlug: 'general',
      localSlug: 'general',
      title: 'General',
      postingPolicy: postingPolicy,
      createdAt: now,
      updatedAt: now,
    );
  }

  group('HostedBoardProjection.externalInclusion', () {
    test('is true when posting_policy external_inclusion == true', () {
      final projection = projectionWith({'external_inclusion': true});
      expect(projection.externalInclusion, isTrue);
    });

    test('is false when posting_policy external_inclusion == false', () {
      final projection = projectionWith({'external_inclusion': false});
      expect(projection.externalInclusion, isFalse);
    });

    test('is false when external_inclusion key is absent', () {
      final projection = projectionWith(const {});
      expect(projection.externalInclusion, isFalse);
    });

    test('is false for non-bool external_inclusion values (fail closed)', () {
      expect(projectionWith({'external_inclusion': 'true'}).externalInclusion,
          isFalse);
      expect(projectionWith({'external_inclusion': 1}).externalInclusion,
          isFalse);
    });
  });
}
