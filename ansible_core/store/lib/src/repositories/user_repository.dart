import '../entities/user.dart';

abstract class UserRepository {
  Future<void> create(User user);
  Future<User?> getById(String userId);
  Future<User?> getByUsername(String username);
  Future<void> update(User user);
  Future<void> delete(String userId);
}
