import 'package:drift/drift.dart';

import 'publication_intents.dart';

class PublicationTargets extends Table {
  TextColumn get targetId => text()();
  TextColumn get intentId => text().references(PublicationIntents, #intentId)();
  TextColumn get protocol => text()();
  TextColumn get endpoint => text()();
  TextColumn get status => text().withDefault(const Constant('pending'))();
  TextColumn get remoteId => text().nullable()();
  DateTimeColumn get lastAttemptAt => dateTime().nullable()();
  TextColumn get error => text().nullable()();

  @override
  Set<Column> get primaryKey => {targetId};
}
