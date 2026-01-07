
import 'package:ansible_store/ansible_store.dart';

void main() async {
  final db = AppDatabase();
  final repo = DriftUserRepository(db);

  final user = User(
    userId: 'user-1',
    username: 'user-1',
    passwordHash: 'password', // Plaintext for POC
    displayName: 'Test User 1',
    createdAt: DateTime.now(),
    updatedAt: DateTime.now(),
  );

  try {
    await repo.create(user);
    print('User created: ${user.username}');
  } catch (e) {
    print('Failed to create user: $e');
  } finally {
    await db.close();
  }
}
