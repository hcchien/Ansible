// === Domain entities (Aggregator materialized-view layer) ===
export 'src/entities/board.dart';
export 'src/entities/thread.dart';
export 'src/entities/post.dart';
export 'src/entities/reaction.dart';
export 'src/entities/board_acl.dart';
export 'src/entities/activity_log.dart'; // ActivityLog = Op log (CRDT ops received)
export 'src/entities/remote_node.dart';
export 'src/entities/board_sync_config.dart';
export 'src/entities/follow_target.dart';
export 'src/entities/follow_edge.dart';
export 'src/entities/follow_activity_event.dart';
export 'src/entities/outbound_follow_activity.dart';
export 'src/entities/identity.dart'; // DID-based identity (replaces User+passwordHash)
export 'src/entities/ops_queue.dart'; // Local Op queue for offline-first / Comp B
export 'src/entities/wallet_credential.dart';
export 'src/entities/wallet_presentation.dart';

// === Repository interfaces ===
export 'src/repositories/board_repository.dart';
export 'src/repositories/thread_repository.dart';
export 'src/repositories/post_repository.dart';
export 'src/repositories/reaction_repository.dart';
export 'src/repositories/board_acl_repository.dart';
export 'src/repositories/activity_log_repository.dart';
export 'src/repositories/remote_node_repository.dart';
export 'src/repositories/board_sync_config_repository.dart';
export 'src/repositories/follow_repository.dart';
export 'src/repositories/follow_activity_outbox_repository.dart';
export 'src/repositories/ops_queue_repository.dart';
export 'src/repositories/wallet_repository.dart';

// === CRDT Op Builder (V1.1 Comp B) ===
export 'src/crdt/crdt_op_builder.dart';

// === In-memory implementations (testing / offline) ===
export 'src/repositories/in_memory/in_memory_board_repository.dart';
export 'src/repositories/in_memory/in_memory_board_sync_config_repository.dart';
export 'src/repositories/in_memory/in_memory_thread_repository.dart';
export 'src/repositories/in_memory/in_memory_post_repository.dart';
export 'src/repositories/in_memory/in_memory_reaction_repository.dart';
export 'src/repositories/in_memory/in_memory_follow_repository.dart';
export 'src/repositories/in_memory/in_memory_follow_activity_outbox_repository.dart';
export 'src/repositories/in_memory/in_memory_ops_queue_repository.dart';
export 'src/repositories/in_memory/in_memory_wallet_repository.dart';

// === Drift (SQLite) implementations ===
export 'src/repositories/drift/drift_board_repository.dart';
export 'src/repositories/drift/drift_thread_repository.dart';
export 'src/repositories/drift/drift_post_repository.dart';
export 'src/repositories/drift/drift_reaction_repository.dart';
export 'src/repositories/drift/drift_board_acl_repository.dart';
export 'src/repositories/drift/drift_activity_log_repository.dart';
export 'src/repositories/drift/drift_remote_node_repository.dart';
export 'src/repositories/drift/drift_board_sync_config_repository.dart';
export 'src/repositories/drift/drift_follow_repository.dart';
export 'src/repositories/drift/drift_follow_activity_outbox_repository.dart';
export 'src/repositories/drift/drift_ops_queue_repository.dart';
export 'src/repositories/drift/drift_wallet_repository.dart';
export 'src/db/app_database.dart'
    hide
        Board,
        Thread,
        Post,
        Reaction,
        RemoteNode,
        BoardSyncConfig,
        FollowTarget,
        FollowEdge,
        FollowActivityEvent,
        OutboundFollowActivity,
        Identity,
        WalletCredential,
        WalletPresentation;
