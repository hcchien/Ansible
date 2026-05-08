import '../entities/context_pack.dart';

abstract class ContextPackRepository {
  Future<void> create(ContextPack contextPack);
  Future<ContextPack?> getById(String id);
}
