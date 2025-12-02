import '../entities/activity_log.dart';

abstract class ActivityLogRepository {
  Future<int> create(ActivityLog log);
  Future<ActivityLog?> getByActivityId(String activityId);
  Future<List<ActivityLog>> list({int? afterLogId, int limit = 50});
}
