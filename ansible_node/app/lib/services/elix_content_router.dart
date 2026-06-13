import 'package:ansible_store/ansible_store.dart';

import 'elix_content_link.dart';

/// Outcome of resolving an inbound Elix content deep link against the local
/// store. Pure data so routing can be unit-tested without a Navigator.
sealed class ElixContentResolution {
  const ElixContentResolution();
}

/// The link points at a thread that exists locally — open the thread screen.
class ResolvedThread extends ElixContentResolution {
  final Thread thread;
  final HostedBoardProjection? projection;
  const ResolvedThread(this.thread, {this.projection});
}

/// The link points at a board that exists locally — open the board screen.
class ResolvedBoard extends ElixContentResolution {
  final Board board;
  const ResolvedBoard(this.board);
}

/// The link is well-formed but the content is not available on this device.
/// The caller shows a graceful message (and could later trigger a fetch).
class ContentUnavailable extends ElixContentResolution {
  final ElixContentRef ref;
  const ContentUnavailable(this.ref);
}

/// Resolves an [ElixContentRef] to local content. Thread links resolve by the
/// global thread id (board id is contextual fallback); board links resolve via
/// the hosted-board projection back to the local board row.
class ElixContentRouter {
  final AppDatabase db;

  const ElixContentRouter(this.db);

  Future<ElixContentResolution> resolve(ElixContentRef ref) async {
    if (ref.isThread) {
      final thread = await DriftThreadRepository(db).getById(ref.threadId!);
      if (thread == null) {
        return ContentUnavailable(ref);
      }
      final projection = await DriftHostedBoardRepository(
        db,
      ).getProjectionByLocalBoardId(thread.boardId);
      return ResolvedThread(thread, projection: projection);
    }

    final board = await _boardForHostedId(ref.boardId);
    if (board == null) {
      return ContentUnavailable(ref);
    }
    return ResolvedBoard(board);
  }

  /// Finds the local board backing a hosted board id via its projection.
  Future<Board?> _boardForHostedId(String hostedBoardId) async {
    final projections = await DriftHostedBoardRepository(db).listProjections();
    HostedBoardProjection? match;
    for (final projection in projections) {
      if (projection.hostedBoardId == hostedBoardId) {
        match = projection;
        break;
      }
    }
    if (match == null) return null;
    return DriftBoardRepository(db).getById(match.localBoardId);
  }
}
