import '../../entities/context_pack.dart';
import '../context_pack_repository.dart';

class InMemoryContextPackRepository implements ContextPackRepository {
  final Map<String, ContextPack> _contextPacks = {};

  @override
  Future<void> create(ContextPack contextPack) async {
    _contextPacks[contextPack.id] = contextPack;
  }

  @override
  Future<ContextPack?> getById(String id) async {
    return _contextPacks[id];
  }
}
