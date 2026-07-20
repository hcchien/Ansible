import '../entities/local_search_result.dart';

abstract class LocalSearchRepository {
  Future<List<LocalSearchResult>> search(
    String query, {
    LocalSearchScope scope = LocalSearchScope.all,
    int limit = 60,
  });
}
