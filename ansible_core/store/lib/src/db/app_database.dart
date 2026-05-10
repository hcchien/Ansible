import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;

import '../schema/activity_log.dart';
import '../schema/board_publication_targets.dart';
import '../schema/board_acl.dart';
import '../schema/board_subscriptions.dart';
import '../schema/board_sync_configs.dart';
import '../schema/boards.dart';
import '../schema/ai_provider_configs.dart';
import '../schema/content_items.dart';
import '../schema/content_metadata.dart';
import '../schema/content_relations.dart';
import '../schema/context_packs.dart';
import '../schema/discussion_nodes.dart';
import '../schema/follow_activity_events.dart';
import '../schema/follow_edges.dart';
import '../schema/follow_targets.dart';
import '../schema/forum_hosts.dart';
import '../schema/hosted_board_projections.dart';
import '../schema/identities.dart';
import '../schema/identity_bindings.dart';
import '../schema/local_collections.dart';
import '../schema/ops_queue.dart';
import '../schema/outbound_follow_activities.dart';
import '../schema/ownership_policies.dart';
import '../schema/posts.dart';
import '../schema/publication_intents.dart';
import '../schema/publication_targets.dart';
import '../schema/projections.dart';
import '../schema/reactions.dart';
import '../schema/remote_nodes.dart';
import '../schema/summary_jobs.dart';
import '../schema/threads.dart';
import '../schema/transformation_jobs.dart';
import '../schema/wallet_credential_payloads.dart';
import '../schema/wallet_credentials.dart';
import '../schema/wallet_presentations.dart';

part 'app_database.g.dart';

@DriftDatabase(
  tables: [
    Boards,
    ForumHosts,
    HostedBoardProjections,
    BoardSubscriptions,
    BoardPublicationTargets,
    Threads,
    Posts,
    Reactions,
    BoardAcl,
    ActivityLog,
    RemoteNodes,
    BoardSyncConfigs,
    Identities,
    OpsQueue,
    WalletCredentials,
    WalletCredentialPayloads,
    WalletPresentations,
    FollowTargets,
    FollowEdges,
    FollowActivityEvents,
    OutboundFollowActivities,
    ContentItems,
    MurmurMetadata,
    NoteMetadata,
    PostMetadata,
    DiscussionMetadata,
    ContentRelations,
    TransformationJobs,
    TransformationSources,
    Projections,
    DiscussionNodes,
    OwnershipPolicies,
    AiProviderConfigs,
    ContextPacks,
    SummaryJobs,
    PublicationIntents,
    PublicationTargets,
    IdentityBindings,
    LocalCollections,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? e]) : super(e ?? _openConnection());

  @override
  int get schemaVersion => 14;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    onUpgrade: (m, from, to) async {
      if (from < 6) {
        await _createTableIfMissing(m, remoteNodes);
        await _createTableIfMissing(m, boardSyncConfigs);
      }
      if (from < 8) {
        await _createTableIfMissing(m, walletCredentials);
        await _createTableIfMissing(m, walletCredentialPayloads);
        await _createTableIfMissing(m, walletPresentations);
      }
      if (from < 9) {
        await _createTableIfMissing(m, identities);
        await _createTableIfMissing(m, opsQueue);
      }
      if (from < 10) {
        await _createTableIfMissing(m, followTargets);
        await _createTableIfMissing(m, followEdges);
        await _createTableIfMissing(m, followActivityEvents);
        await _createTableIfMissing(m, outboundFollowActivities);
      }
      if (from < 11) {
        await _createTableIfMissing(m, contentItems);
        await _createTableIfMissing(m, murmurMetadata);
        await _createTableIfMissing(m, noteMetadata);
        await _createTableIfMissing(m, postMetadata);
        await _createTableIfMissing(m, discussionMetadata);
        await _createTableIfMissing(m, contentRelations);
        await _createTableIfMissing(m, transformationJobs);
        await _createTableIfMissing(m, transformationSources);
        await _createTableIfMissing(m, projections);
        await _createTableIfMissing(m, discussionNodes);
        await _createTableIfMissing(m, ownershipPolicies);
        await _createTableIfMissing(m, aiProviderConfigs);
        await _createTableIfMissing(m, contextPacks);
        await _createTableIfMissing(m, summaryJobs);
      }
      if (from < 12) {
        await _createTableIfMissing(m, publicationIntents);
        await _createTableIfMissing(m, publicationTargets);
        await _createTableIfMissing(m, identityBindings);
      }
      if (from < 13) {
        await _createTableIfMissing(m, forumHosts);
        await _createTableIfMissing(m, hostedBoardProjections);
        await _createTableIfMissing(m, boardSubscriptions);
        await _createTableIfMissing(m, boardPublicationTargets);
      }
      if (from < 14) {
        await _createTableIfMissing(m, localCollections);
      }
      await _addColumnIfMissing(
        m,
        boardSyncConfigs,
        boardSyncConfigs.retentionDays,
      );
    },
  );

  Future<void> _createTableIfMissing(
    Migrator migrator,
    TableInfo<Table, Object?> table,
  ) async {
    final exists = await customSelect(
      'SELECT 1 FROM sqlite_master WHERE type = ? AND name = ? LIMIT 1',
      variables: [
        const Variable<String>('table'),
        Variable<String>(table.actualTableName),
      ],
    ).getSingleOrNull();
    if (exists == null) {
      await migrator.createTable(table);
    }
  }

  Future<void> _addColumnIfMissing(
    Migrator migrator,
    TableInfo<Table, Object?> table,
    GeneratedColumn<Object> column,
  ) async {
    final exists = await customSelect(
      'SELECT 1 FROM pragma_table_info(?) WHERE name = ? LIMIT 1',
      variables: [
        Variable<String>(table.actualTableName),
        Variable<String>(column.$name),
      ],
    ).getSingleOrNull();
    if (exists == null) {
      await migrator.addColumn(table, column);
    }
  }
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dbFolder = Directory.current;
    final file = File(p.join(dbFolder.path, 'ansible.db'));
    return NativeDatabase.createInBackground(file);
  });
}
