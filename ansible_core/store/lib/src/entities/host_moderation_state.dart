/// A host-declared moderation effect on hosted-board content, synced from the
/// board's Forum Host (`GET /boards/:id/moderation-state`).
///
/// Constitution note (Base Rules 6/7): this is the **host's projection** of
/// its own board only — it never deletes the author's local copy. The reason
/// code is stored so the affected author can always see why.
class HostModerationState {
  /// Local board id (the hosted board's projection on this device).
  final String localBoardId;

  /// `"post"` or `"thread"`.
  final String targetKind;

  /// Op entity id of the moderated post/thread.
  final String targetRef;

  /// `"removed"` (post tombstoned on the host) or `"locked"` (thread accepts
  /// no new posts on the host).
  final String action;

  /// Reason code from the fixed enum: spam, harassment, illegal_content,
  /// off_topic, impersonation, other.
  final String reasonCode;

  final DateTime updatedAt;

  const HostModerationState({
    required this.localBoardId,
    required this.targetKind,
    required this.targetRef,
    required this.action,
    required this.reasonCode,
    required this.updatedAt,
  });

  static const targetKindPost = 'post';
  static const targetKindThread = 'thread';
  static const actionRemoved = 'removed';
  static const actionLocked = 'locked';

  /// Identity used when diffing snapshots: a re-applied snapshot is "new"
  /// only when this key was absent before.
  String get diffKey => '$targetKind:$targetRef:$action';
}
