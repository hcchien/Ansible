import 'package:drift/drift.dart';

class AiProviderConfigs extends Table {
  TextColumn get providerConfigId => text()();
  TextColumn get displayName => text()();
  TextColumn get providerType => text()();
  TextColumn get baseUrl => text().nullable()();
  TextColumn get modelName => text().nullable()();
  TextColumn get apiKeyRef => text().nullable()();
  BoolColumn get defaultForTransformations =>
      boolean().withDefault(const Constant(false))();
  BoolColumn get defaultForSummaries =>
      boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {providerConfigId};
}
