import 'package:drift/drift.dart';

import 'content_items.dart';

class OwnershipPolicies extends Table {
  TextColumn get contentItemId =>
      text().references(ContentItems, #contentItemId)();
  TextColumn get ownerDid => text()();
  TextColumn get editPolicy => text()();
  TextColumn get deletePolicy => text()();
  TextColumn get commentPolicy => text()();
  TextColumn get forkPolicy => text()();
  TextColumn get moderationPolicy => text()();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {contentItemId};
}
