import 'package:ansible_store/ansible_store.dart';
import 'package:drift/native.dart';
import 'package:test/test.dart';

HostModerationState _entry({
  String localBoardId = 'board-1',
  String targetKind = 'post',
  String targetRef = 'post-1',
  String action = 'removed',
  String reasonCode = 'spam',
  DateTime? updatedAt,
}) {
  return HostModerationState(
    localBoardId: localBoardId,
    targetKind: targetKind,
    targetRef: targetRef,
    action: action,
    reasonCode: reasonCode,
    updatedAt: updatedAt ?? DateTime.utc(2026, 6, 13, 12),
  );
}

void main() {
  group('HostModerationStateRepository', () {
    for (final (label, makeRepo)
        in <(String, HostModerationStateRepository Function(AppDatabase db))>[
          ('drift', DriftHostModerationStateRepository.new),
          ('in-memory', (_) => InMemoryHostModerationStateRepository()),
        ]) {
      group(label, () {
        late AppDatabase db;
        late HostModerationStateRepository repo;

        setUp(() {
          db = AppDatabase(NativeDatabase.memory());
          repo = makeRepo(db);
        });

        tearDown(() => db.close());

        test('first snapshot reports every entry as new', () async {
          final fresh = await repo.replaceForBoard('board-1', [
            _entry(targetRef: 'post-1'),
            _entry(
              targetKind: 'thread',
              targetRef: 'thread-1',
              action: 'locked',
              reasonCode: 'off_topic',
            ),
          ]);

          expect(fresh, hasLength(2));
          expect(await repo.listForBoard('board-1'), hasLength(2));
        });

        test('re-applied snapshot reports nothing new', () async {
          List<HostModerationState> snapshot() => [
            _entry(targetRef: 'post-1'),
            _entry(
              targetKind: 'thread',
              targetRef: 'thread-1',
              action: 'locked',
            ),
          ];

          await repo.replaceForBoard('board-1', snapshot());
          final fresh = await repo.replaceForBoard('board-1', snapshot());

          expect(fresh, isEmpty);
          expect(await repo.listForBoard('board-1'), hasLength(2));
        });

        test('snapshot apply removes entries no longer served', () async {
          await repo.replaceForBoard('board-1', [
            _entry(targetRef: 'post-1'),
            _entry(
              targetKind: 'thread',
              targetRef: 'thread-1',
              action: 'locked',
            ),
          ]);

          // Host unlocked the thread: next snapshot only has the removal.
          final fresh = await repo.replaceForBoard('board-1', [
            _entry(targetRef: 'post-1'),
          ]);

          expect(fresh, isEmpty);
          final remaining = await repo.listForBoard('board-1');
          expect(remaining, hasLength(1));
          expect(remaining.single.targetRef, 'post-1');
          expect(await repo.entryFor('thread', 'thread-1'), isNull);
        });

        test('only additions count as new in a mixed snapshot', () async {
          await repo.replaceForBoard('board-1', [
            _entry(targetRef: 'post-1'),
          ]);

          final fresh = await repo.replaceForBoard('board-1', [
            _entry(targetRef: 'post-1'),
            _entry(targetRef: 'post-2', reasonCode: 'harassment'),
          ]);

          expect(fresh, hasLength(1));
          expect(fresh.single.targetRef, 'post-2');
          expect(fresh.single.reasonCode, 'harassment');
        });

        test('boards are isolated from each other', () async {
          await repo.replaceForBoard('board-1', [_entry(targetRef: 'post-1')]);
          await repo.replaceForBoard('board-2', [
            _entry(localBoardId: 'board-2', targetRef: 'post-9'),
          ]);

          // Replacing board-2 must not touch board-1.
          await repo.replaceForBoard('board-2', []);

          expect(await repo.listForBoard('board-1'), hasLength(1));
          expect(await repo.listForBoard('board-2'), isEmpty);
        });

        test('entryFor finds the entry by target kind and ref', () async {
          await repo.replaceForBoard('board-1', [
            _entry(targetRef: 'post-1', reasonCode: 'impersonation'),
            _entry(
              targetKind: 'thread',
              targetRef: 'thread-1',
              action: 'locked',
              reasonCode: 'off_topic',
            ),
          ]);

          final removed = await repo.entryFor('post', 'post-1');
          expect(removed, isNotNull);
          expect(removed!.action, 'removed');
          expect(removed.reasonCode, 'impersonation');

          final locked = await repo.entryFor('thread', 'thread-1');
          expect(locked, isNotNull);
          expect(locked!.action, 'locked');
          expect(locked.reasonCode, 'off_topic');

          // Kind must match, not just the ref.
          expect(await repo.entryFor('thread', 'post-1'), isNull);
          expect(await repo.entryFor('post', 'missing'), isNull);
        });

        test('round-trips all fields', () async {
          await repo.replaceForBoard('board-1', [
            _entry(
              targetKind: 'thread',
              targetRef: 'thread-7',
              action: 'locked',
              reasonCode: 'illegal_content',
              updatedAt: DateTime.utc(2026, 6, 13, 8, 30),
            ),
          ]);

          final stored = (await repo.listForBoard('board-1')).single;
          expect(stored.localBoardId, 'board-1');
          expect(stored.targetKind, 'thread');
          expect(stored.targetRef, 'thread-7');
          expect(stored.action, 'locked');
          expect(stored.reasonCode, 'illegal_content');
          // Drift round-trips instants, not zones — compare in UTC.
          expect(stored.updatedAt.toUtc(), DateTime.utc(2026, 6, 13, 8, 30));
        });
      });
    }
  });
}
