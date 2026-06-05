import 'package:drift/drift.dart';

/// Locally-cached reputation tier per author DID, populated from relay op
/// deltas / AppView timeline / the local user's own VP presentation. Used to
/// render a verified-tier badge on posts without a per-post field.
@DataClassName('DidReputationRow')
class DidReputations extends Table {
  TextColumn get did => text()();
  TextColumn get tier => text()();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {did};
}
