import 'package:drift/drift.dart';
import 'content_items.dart';

class MurmurEmbeddings extends Table {
  TextColumn get contentItemId =>
      text().references(ContentItems, #contentItemId)();
  TextColumn get modelVersion => text()();
  TextColumn get vectorBlob => text()(); // base64-encoded float32 list
  DateTimeColumn get computedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {contentItemId};
}
