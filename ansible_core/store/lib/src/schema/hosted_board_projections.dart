import 'package:drift/drift.dart';

class HostedBoardProjections extends Table {
  TextColumn get localBoardId => text()();
  TextColumn get forumHostId => text()();
  TextColumn get hostedBoardId => text()();
  TextColumn get canonicalBoardUri => text()();
  TextColumn get remoteSlug => text()();
  TextColumn get localSlug => text().unique()();
  TextColumn get title => text()();
  TextColumn get description => text().nullable()();
  TextColumn get permissionsJson => text().withDefault(const Constant('{}'))();
  TextColumn get postingPolicyJson =>
      text().withDefault(const Constant('{}'))();
  TextColumn get accessPolicyJson => text().withDefault(
    const Constant(
      '{"version":1,"discovery":"public","read":{"requirement":"public"},"post":{"requirement":"posting_policy"},"moderate":{"requirement":"board_moderator"},"requirements":{},"capability_ttl_seconds":300,"content_visibility":"public","federation":"enabled"}',
    ),
  )();
  IntColumn get accessPolicyVersion =>
      integer().withDefault(const Constant(1))();
  TextColumn get contentVisibility =>
      text().withDefault(const Constant('public'))();
  IntColumn get encryptionEpoch => integer().withDefault(const Constant(0))();
  TextColumn get encryptionState =>
      text().withDefault(const Constant('disabled'))();
  TextColumn get federationPolicyJson =>
      text().withDefault(const Constant('{"mode":"enabled"}'))();
  IntColumn get lastSeenCursor => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {localBoardId};

  @override
  List<Set<Column>> get uniqueKeys => [
    {forumHostId, hostedBoardId},
  ];
}
