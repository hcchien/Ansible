import 'package:drift/drift.dart';

import 'content_items.dart';

class Projections extends Table {
  TextColumn get projectionId => text()();
  @ReferenceName('sourceProjections')
  TextColumn get sourceContentItemId =>
      text().references(ContentItems, #contentItemId)();
  @ReferenceName('targetDiscussionProjections')
  TextColumn get targetDiscussionId =>
      text().references(ContentItems, #contentItemId)();
  TextColumn get projectedExcerpt => text()();
  TextColumn get participationPolicy => text()();
  BoolColumn get ownershipTransferAcknowledged =>
      boolean().withDefault(const Constant(false))();
  DateTimeColumn get acknowledgedAt => dateTime().nullable()();
  TextColumn get createdByDid => text()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {projectionId};
}
