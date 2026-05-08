import 'package:drift/drift.dart';

import 'boards.dart';
import 'content_items.dart';
import 'posts.dart';
import 'threads.dart';

class MurmurMetadata extends Table {
  TextColumn get contentItemId =>
      text().references(ContentItems, #contentItemId)();
  TextColumn get tone => text().nullable()();
  TextColumn get sourceType => text().nullable()();
  TextColumn get privateTagsJson => text().nullable()();
  BoolColumn get isSensitive => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {contentItemId};
}

class NoteMetadata extends Table {
  TextColumn get contentItemId =>
      text().references(ContentItems, #contentItemId)();
  TextColumn get thesis => text().nullable()();
  TextColumn get outlineJson => text().nullable()();
  TextColumn get summary => text().nullable()();
  TextColumn get assistantPersona => text().nullable()();

  @override
  Set<Column> get primaryKey => {contentItemId};
}

class PostMetadata extends Table {
  TextColumn get contentItemId =>
      text().references(ContentItems, #contentItemId)();
  TextColumn get threadId => text().nullable().references(Threads, #threadId)();
  TextColumn get boardId => text().nullable().references(Boards, #boardId)();
  TextColumn get parentPostId => text().nullable().references(Posts, #postId)();
  TextColumn get replyToUri => text().nullable()();

  @override
  Set<Column> get primaryKey => {contentItemId};
}

class DiscussionMetadata extends Table {
  TextColumn get contentItemId =>
      text().references(ContentItems, #contentItemId)();
  TextColumn get threadId => text().nullable().references(Threads, #threadId)();
  TextColumn get discussionShape => text().nullable()();
  TextColumn get participationPolicy => text().nullable()();
  TextColumn get forkPolicy => text().nullable()();
  TextColumn get consensusState => text().nullable()();

  @override
  Set<Column> get primaryKey => {contentItemId};
}
