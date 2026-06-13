import 'package:drift/drift.dart';

/// Locally-projected notifications (Phase A of the notification plan).
///
/// Rows are a pure **local projection** over data the device already synced
/// (op delta, messenger mailbox) — nothing in this table is ever sent to a
/// server, and read-state lives only here. [dedupKey] is unique so re-synced
/// ops fold to a no-op instead of duplicating a notification.
@DataClassName('NotificationRow')
class Notifications extends Table {
  TextColumn get id => text()();

  /// Storage value of [NotificationType] (e.g. `reply_to_thread`).
  TextColumn get type => text()();

  /// DID of the user who triggered the notification (replier / follower /
  /// message sender).
  TextColumn get actorDid => text()();

  /// Id of the triggering entity (reply post id, follower DID, message id).
  TextColumn get targetRef => text()();

  // Context refs needed to navigate on tap (nullable per type).
  TextColumn get boardId => text().nullable()();
  TextColumn get threadId => text().nullable()();
  TextColumn get postId => text().nullable()();
  TextColumn get conversationId => text().nullable()();

  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get readAt => dateTime().nullable()();

  /// Stable identity of the underlying event; unique so re-applied ops
  /// cannot duplicate notifications.
  TextColumn get dedupKey => text().unique()();

  @override
  Set<Column> get primaryKey => {id};
}
