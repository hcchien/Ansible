import 'package:drift/drift.dart';
import '../../db/app_database.dart';
import '../../entities/user.dart' as entity;
import '../user_repository.dart';

class DriftUserRepository implements UserRepository {
  final AppDatabase _db;

  DriftUserRepository(this._db);

  @override
  Future<void> create(entity.User user) async {
    await _db.into(_db.users).insert(
          UsersCompanion.insert(
            userId: user.userId,
            username: user.username,
            passwordHash: user.passwordHash,
            displayName: Value(user.displayName),
            createdAt: Value(user.createdAt),
            updatedAt: Value(user.updatedAt),
          ),
          mode: InsertMode.insertOrReplace,
        );
  }

  @override
  Future<entity.User?> getById(String userId) async {
    final row = await (_db.select(_db.users)..where((t) => t.userId.equals(userId)))
        .getSingleOrNull();
    if (row == null) return null;
    return _mapRowToEntity(row);
  }

  @override
  Future<entity.User?> getByUsername(String username) async {
    final row = await (_db.select(_db.users)..where((t) => t.username.equals(username)))
        .getSingleOrNull();
    if (row == null) return null;
    return _mapRowToEntity(row);
  }

  @override
  Future<void> update(entity.User user) async {
    await (_db.update(_db.users)..where((t) => t.userId.equals(user.userId))).write(
      UsersCompanion(
        username: Value(user.username),
        passwordHash: Value(user.passwordHash),
        displayName: Value(user.displayName),
        updatedAt: Value(user.updatedAt),
      ),
    );
  }

  @override
  Future<void> delete(String userId) async {
    await (_db.delete(_db.users)..where((t) => t.userId.equals(userId))).go();
  }

  entity.User _mapRowToEntity(User row) {
    return entity.User(
      userId: row.userId,
      username: row.username,
      passwordHash: row.passwordHash,
      displayName: row.displayName,
      createdAt: row.createdAt,
      updatedAt: row.updatedAt,
    );
  }
}
