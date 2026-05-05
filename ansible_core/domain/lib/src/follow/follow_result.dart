enum FollowResultStatus { success, duplicate, targetNotFound, failed }

class FollowResult {
  final FollowResultStatus status;
  final String? followId;
  final String? message;

  const FollowResult._({required this.status, this.followId, this.message});

  const FollowResult.success(String followId)
    : this._(status: FollowResultStatus.success, followId: followId);

  const FollowResult.duplicate(String followId)
    : this._(status: FollowResultStatus.duplicate, followId: followId);

  const FollowResult.targetNotFound(String message)
    : this._(status: FollowResultStatus.targetNotFound, message: message);

  const FollowResult.failed(String message)
    : this._(status: FollowResultStatus.failed, message: message);
}
