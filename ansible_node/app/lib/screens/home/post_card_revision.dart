import 'post_card.dart';

String postCardId(PostCardData post) =>
    '${post.openableThread ? 'thread' : 'content'}:${post.thread.id}';

/// Excludes relative time so an unchanged row does not animate on every read.
Object postCardRevision(PostCardData post) => Object.hashAll([
  post.title,
  post.content,
  post.author,
  post.authorDisplayName,
  post.authorHandle,
  post.authorTier,
  post.signatureVerified,
  post.board,
  post.comments,
  post.reacted,
  Object.hashAll(
    post.reactions.entries.map((entry) => (entry.key, entry.value)),
  ),
  Object.hashAll(
    post.replyPreviews.map(
      (reply) => (
        reply.id,
        reply.content,
        reply.authorDisplayName,
        reply.authorHandle,
        reply.signatureVerified,
      ),
    ),
  ),
]);
