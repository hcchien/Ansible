import 'package:drift/drift.dart';

import 'ai_provider_configs.dart';
import 'context_packs.dart';

class SummaryJobs extends Table {
  TextColumn get summaryJobId => text()();
  TextColumn get requestedByDid => text()();
  TextColumn get contextPackId =>
      text().references(ContextPacks, #contextPackId)();
  TextColumn get providerConfigId =>
      text().references(AiProviderConfigs, #providerConfigId)();
  TextColumn get summaryType => text()();
  TextColumn get status => text()();
  TextColumn get resultJson => text().nullable()();
  TextColumn get errorMessage => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get completedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {summaryJobId};
}
