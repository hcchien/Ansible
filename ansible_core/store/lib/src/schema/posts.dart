import 'package:drift/drift.dart';
import 'threads.dart';
import 'boards.dart';

class Posts extends Table {
  TextColumn get postId => text()();
  TextColumn get threadId => text().references(Threads, #threadId)();
  TextColumn get boardId => text().references(Boards, #boardId)();
  TextColumn get authorId => text()();
  TextColumn get content => text()();
  TextColumn get parentPostId => text().nullable().references(Posts, #postId)();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get lastEditAt => dateTime()();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();

  /// True once the post's authoring op carried a valid Ed25519 signature —
  /// signed locally on create, or verified on sync (the relay only admits
  /// signature-verified ops). Surfaces a "signed" badge in the UI.
  BoolColumn get signatureVerified =>
      boolean().withDefault(const Constant(false))();

  /// Signed public mention references (`[{did, token}]`) used only to render
  /// profile links. Private-board values reach this column only after local
  /// decryption; they never leave the encrypted envelope in cleartext.
  TextColumn get mentionsJson => text().withDefault(const Constant('[]'))();

  @override
  Set<Column> get primaryKey => {postId};
}
