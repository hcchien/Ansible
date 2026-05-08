import '../entities/projection.dart';

abstract class ProjectionRepository {
  Future<void> create(Projection projection);
  Future<Projection?> getById(String id);
}
