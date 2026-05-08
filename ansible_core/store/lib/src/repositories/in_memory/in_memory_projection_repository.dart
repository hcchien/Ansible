import '../../entities/projection.dart';
import '../projection_repository.dart';

class InMemoryProjectionRepository implements ProjectionRepository {
  final Map<String, Projection> _projections = {};

  @override
  Future<void> create(Projection projection) async {
    _projections[projection.id] = projection;
  }

  @override
  Future<Projection?> getById(String id) async {
    return _projections[id];
  }
}
