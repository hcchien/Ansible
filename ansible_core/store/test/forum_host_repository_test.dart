import 'package:ansible_store/ansible_store.dart';
import 'package:drift/native.dart';
import 'package:test/test.dart';

void main() {
  group('forum host repositories', () {
    late AppDatabase db;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
    });

    tearDown(() async {
      await db.close();
    });

    test('drift stores active Forum Host metadata', () async {
      await _exercisesForumHostRepository(DriftForumHostRepository(db));
    });

    test('in-memory stores active Forum Host metadata', () async {
      await _exercisesForumHostRepository(InMemoryForumHostRepository());
    });
  });
}

Future<void> _exercisesForumHostRepository(
  ForumHostRepository repository,
) async {
  final now = DateTime.utc(2026, 5, 10);
  await repository.upsert(
    ForumHost(
      forumHostId: 'host-1',
      displayName: 'Tris Aura Forum',
      baseUrl: 'https://forum.example',
      canonicalHostUri: 'https://forum.example',
      serverKind: 'ansibleForumHost',
      capabilities: const {'create_boards': true, 'cross_post': true},
      isActive: true,
      createdAt: now,
      updatedAt: now,
    ),
  );

  final stored = await repository.getById('host-1');
  expect(stored, isNotNull);
  expect(stored!.displayName, 'Tris Aura Forum');
  expect(stored.capabilities['create_boards'], isTrue);

  final active = await repository.listActive();
  expect(active.map((host) => host.forumHostId), ['host-1']);

  await repository.upsert(
    stored.copyWith(
      isActive: false,
      updatedAt: now.add(const Duration(days: 1)),
    ),
  );
  expect(await repository.listActive(), isEmpty);
}
