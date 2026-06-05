// === Domain entities (Aggregator materialized-view layer) ===
export 'src/entities/board.dart';
export 'src/entities/thread.dart';
export 'src/entities/post.dart';
export 'src/entities/reaction.dart';
export 'src/entities/board_acl.dart';
export 'src/entities/activity_log.dart'; // ActivityLog = Op log (CRDT ops received)
export 'src/entities/remote_node.dart';
export 'src/entities/forum_host.dart';
export 'src/entities/hosted_board_projection.dart';
export 'src/entities/board_subscription.dart';
export 'src/entities/board_publication_target.dart';
export 'src/entities/local_collection.dart';
export 'src/entities/messenger_entities.dart';
export 'src/entities/board_sync_config.dart';
export 'src/entities/contact_entities.dart';
export 'src/entities/did_reputation.dart';
export 'src/entities/follow_target.dart';
export 'src/entities/follow_edge.dart';
export 'src/entities/follow_activity_event.dart';
export 'src/entities/outbound_follow_activity.dart';
export 'src/entities/identity.dart'; // DID-based identity (replaces User+passwordHash)
export 'src/entities/ops_queue.dart'; // Local Op queue for offline-first / Comp B
export 'src/entities/wallet_credential.dart';
export 'src/entities/wallet_presentation.dart';
export 'src/entities/passport_wallet_extension.dart';
export 'src/entities/content_item.dart';
export 'src/entities/content_relation.dart';
export 'src/entities/publication_intent.dart';
export 'src/entities/publication_target.dart';
export 'src/entities/identity_binding.dart';
export 'src/entities/transformation_job.dart';
export 'src/entities/projection.dart';
export 'src/entities/discussion_node.dart';
export 'src/entities/ownership_policy.dart';
export 'src/entities/ai_provider_config.dart';
export 'src/entities/context_pack.dart';
export 'src/entities/summary_job.dart';

// === Repository interfaces ===
export 'src/repositories/board_repository.dart';
export 'src/repositories/thread_repository.dart';
export 'src/repositories/post_repository.dart';
export 'src/repositories/reaction_repository.dart';
export 'src/repositories/board_acl_repository.dart';
export 'src/repositories/activity_log_repository.dart';
export 'src/repositories/remote_node_repository.dart';
export 'src/repositories/forum_host_repository.dart';
export 'src/repositories/hosted_board_repository.dart';
export 'src/repositories/local_collection_repository.dart';
export 'src/repositories/board_sync_config_repository.dart';
export 'src/repositories/follow_repository.dart';
export 'src/repositories/follow_activity_outbox_repository.dart';
export 'src/repositories/ops_queue_repository.dart';
export 'src/repositories/wallet_repository.dart';
export 'src/repositories/content_item_repository.dart';
export 'src/repositories/content_relation_repository.dart';
export 'src/repositories/publication_repository.dart';
export 'src/repositories/transformation_job_repository.dart';
export 'src/repositories/projection_repository.dart';
export 'src/repositories/discussion_node_repository.dart';
export 'src/repositories/ai_provider_config_repository.dart';
export 'src/repositories/context_pack_repository.dart';
export 'src/repositories/summary_job_repository.dart';
export 'src/repositories/messenger_repository.dart';
export 'src/repositories/contact_repository.dart';

// === CRDT Op Builder (V1.1 Comp B) ===
export 'src/crdt/crdt_op_builder.dart';

// === In-memory implementations (testing / offline) ===
export 'src/repositories/in_memory/in_memory_board_repository.dart';
export 'src/repositories/in_memory/in_memory_forum_host_repository.dart';
export 'src/repositories/in_memory/in_memory_hosted_board_repository.dart';
export 'src/repositories/in_memory/in_memory_local_collection_repository.dart';
export 'src/repositories/in_memory/in_memory_board_sync_config_repository.dart';
export 'src/repositories/in_memory/in_memory_thread_repository.dart';
export 'src/repositories/in_memory/in_memory_post_repository.dart';
export 'src/repositories/in_memory/in_memory_reaction_repository.dart';
export 'src/repositories/did_reputation_repository.dart';
export 'src/repositories/in_memory/in_memory_did_reputation_repository.dart';
export 'src/repositories/in_memory/in_memory_follow_repository.dart';
export 'src/repositories/in_memory/in_memory_follow_activity_outbox_repository.dart';
export 'src/repositories/in_memory/in_memory_ops_queue_repository.dart';
export 'src/repositories/in_memory/in_memory_wallet_repository.dart';
export 'src/repositories/in_memory/in_memory_content_item_repository.dart';
export 'src/repositories/in_memory/in_memory_content_relation_repository.dart';
export 'src/repositories/in_memory/in_memory_publication_repository.dart';
export 'src/repositories/in_memory/in_memory_transformation_job_repository.dart';
export 'src/repositories/in_memory/in_memory_projection_repository.dart';
export 'src/repositories/in_memory/in_memory_discussion_node_repository.dart';
export 'src/repositories/in_memory/in_memory_ai_provider_config_repository.dart';
export 'src/repositories/in_memory/in_memory_context_pack_repository.dart';
export 'src/repositories/in_memory/in_memory_summary_job_repository.dart';

// === Drift (SQLite) implementations ===
export 'src/repositories/drift/drift_board_repository.dart';
export 'src/repositories/drift/drift_forum_host_repository.dart';
export 'src/repositories/drift/drift_hosted_board_repository.dart';
export 'src/repositories/drift/drift_local_collection_repository.dart';
export 'src/repositories/drift/drift_thread_repository.dart';
export 'src/repositories/drift/drift_post_repository.dart';
export 'src/repositories/drift/drift_reaction_repository.dart';
export 'src/repositories/drift/drift_board_acl_repository.dart';
export 'src/repositories/drift/drift_activity_log_repository.dart';
export 'src/repositories/drift/drift_remote_node_repository.dart';
export 'src/repositories/drift/drift_board_sync_config_repository.dart';
export 'src/repositories/drift/drift_did_reputation_repository.dart';
export 'src/repositories/drift/drift_follow_repository.dart';
export 'src/repositories/drift/drift_follow_activity_outbox_repository.dart';
export 'src/repositories/drift/drift_ops_queue_repository.dart';
export 'src/repositories/drift/drift_wallet_repository.dart';
export 'src/repositories/drift/drift_content_item_repository.dart';
export 'src/repositories/drift/drift_content_relation_repository.dart';
export 'src/repositories/drift/drift_publication_repository.dart';
export 'src/repositories/drift/drift_transformation_job_repository.dart';
export 'src/repositories/drift/drift_projection_repository.dart';
export 'src/repositories/drift/drift_discussion_node_repository.dart';
export 'src/repositories/drift/drift_ai_provider_config_repository.dart';
export 'src/repositories/drift/drift_context_pack_repository.dart';
export 'src/repositories/drift/drift_summary_job_repository.dart';
export 'src/repositories/drift/drift_messenger_repository.dart';
export 'src/repositories/drift/drift_contact_repository.dart';
export 'src/repositories/murmur_embedding_repository.dart';
export 'src/db/app_database.dart'
    hide
        Board,
        Thread,
        Post,
        Reaction,
        RemoteNode,
        ForumHost,
        HostedBoardProjection,
        BoardSubscription,
        BoardPublicationTarget,
        LocalCollection,
        BoardSyncConfig,
        FollowTarget,
        FollowEdge,
        FollowActivityEvent,
        OutboundFollowActivity,
        Identity,
        WalletCredential,
        WalletPresentation,
        PassportWalletExtensionRecord,
        ContentItem,
        ContentRelation,
        PublicationIntent,
        PublicationTarget,
        IdentityBinding,
        TransformationJob,
        TransformationSource,
        Projection,
        DiscussionNode,
        OwnershipPolicy,
        AiProviderConfig,
        ContextPack,
        SummaryJob,
        MessengerDevice,
        MessengerPreKey,
        MessengerSession,
        MessengerConversation,
        MessengerMessage,
        MessengerMailboxCursor,
        ContactRecord;
