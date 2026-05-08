import 'package:drift/drift.dart';

import 'content_items.dart';

class DiscussionNodes extends Table {
  TextColumn get discussionNodeId => text()();
  TextColumn get discussionId =>
      text().references(ContentItems, #contentItemId)();
  TextColumn get parentNodeId =>
      text().nullable().references(DiscussionNodes, #discussionNodeId)();
  TextColumn get authorDid => text()();
  TextColumn get nodeType => text()();
  TextColumn get stance => text()();
  TextColumn get body => text()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {discussionNodeId};
}
