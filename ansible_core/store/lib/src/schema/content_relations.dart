import 'package:drift/drift.dart';

import 'content_items.dart';

class ContentRelations extends Table {
  TextColumn get relationId => text()();
  @ReferenceName('derivedRelations')
  TextColumn get fromContentItemId =>
      text().references(ContentItems, #contentItemId)();
  @ReferenceName('sourceRelations')
  TextColumn get toContentItemId =>
      text().references(ContentItems, #contentItemId)();
  TextColumn get relationType => text()();
  TextColumn get createdByDid => text()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  BoolColumn get localOnly => boolean().withDefault(const Constant(true))();

  @override
  Set<Column> get primaryKey => {relationId};
}
