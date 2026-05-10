import '../../entities/forum_host.dart';
import '../forum_host_repository.dart';

class InMemoryForumHostRepository implements ForumHostRepository {
  final Map<String, ForumHost> _hosts = {};

  @override
  Future<ForumHost?> getById(String forumHostId) async => _hosts[forumHostId];

  @override
  Future<List<ForumHost>> list({bool includeInactive = true}) async {
    final hosts = _hosts.values.where((host) {
      return includeInactive || host.isActive;
    }).toList()..sort((a, b) => a.displayName.compareTo(b.displayName));
    return hosts;
  }

  @override
  Future<List<ForumHost>> listActive() async {
    return list(includeInactive: false);
  }

  @override
  Future<void> upsert(ForumHost host) async {
    _hosts[host.forumHostId] = host;
  }
}
