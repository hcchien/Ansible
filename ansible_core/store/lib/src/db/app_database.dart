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
import '../schema/contact_records.dart';
import '../schema/content_items.dart';
import '../schema/content_metadata.dart';
import '../schema/content_relations.dart';
import '../schema/context_packs.dart';
import '../schema/did_reputations.dart';
import '../schema/discussion_nodes.dart';
import '../schema/follow_activity_events.dart';
import '../schema/follow_edges.dart';
import '../schema/follow_targets.dart';
import '../schema/forum_hosts.dart';
import '../schema/host_moderation_states.dart';
import '../schema/hosted_board_projections.dart';
import '../schema/identities.dart';
import '../schema/identity_anchors.dart';
import '../schema/identity_bindings.dart';
import '../schema/local_collections.dart';
import '../schema/messenger_conversations.dart';
import '../schema/messenger_devices.dart';
import '../schema/messenger_mailbox_cursors.dart';
import '../schema/messenger_messages.dart';
import '../schema/messenger_pre_keys.dart';
import '../schema/messenger_sessions.dart';
import '../schema/notifications.dart';
import '../schema/ops_queue.dart';
import '../schema/outbound_follow_activities.dart';
import '../schema/ownership_policies.dart';
import '../schema/passport_wallet_extensions.dart';
import '../schema/posts.dart';
import '../schema/publication_intents.dart';
import '../schema/publication_targets.dart';
import '../schema/projections.dart';
import '../schema/reactions.dart';
import '../schema/remote_nodes.dart';
import '../schema/remote_tombstones.dart';
import '../schema/summary_jobs.dart';
import '../schema/threads.dart';
import '../schema/transformation_jobs.dart';
import '../schema/wallet_credential_payloads.dart';
import '../schema/wallet_credentials.dart';
import '../schema/wallet_presentations.dart';
import '../schema/murmur_embeddings.dart';

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
    PassportWalletExtensions,
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
    ContactRecords,
    ContextPacks,
    SummaryJobs,
    PublicationIntents,
    PublicationTargets,
    IdentityBindings,
    LocalCollections,
    MessengerDevices,
    MessengerPreKeys,
    MessengerSessions,
    MessengerConversations,
    MessengerMessages,
    MessengerMailboxCursors,
    MurmurEmbeddings,
    DidReputations,
    Notifications,
    HostModerationStates,
    IdentityAnchors,
    RemoteTombstones,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? e]) : super(e ?? _openConnection());

  @override
  int get schemaVersion => 31;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    // Downgrade guard: drift's onUpgrade only fires for from < to, so opening an
    // OLDER build over a database written by a NEWER schema (from > to) would
    // otherwise skip migration and fail later with an opaque "no such
    // table/column" error. Detect the downgrade before any query runs and fail
    // fast with an actionable message. (This does not alter the forward
    // migration logic below.)
    beforeOpen: (details) async {
      final storedVersion = details.versionBefore;
      if (storedVersion != null && storedVersion > schemaVersion) {
        throw DatabaseDowngradeError(
          storedVersion: storedVersion,
          appVersion: schemaVersion,
        );
      }
    },
    onUpgrade: (m, from, to) async {
      if (from > to) {
        // Defensive: should be unreachable because onUpgrade only runs for
        // from < to, but guard here too so a downgrade can never silently no-op.
        throw DatabaseDowngradeError(storedVersion: from, appVersion: to);
      }
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
      if (from < 15) {
        await _createTableIfMissing(m, messengerDevices);
        await _createTableIfMissing(m, messengerPreKeys);
        await _createTableIfMissing(m, messengerSessions);
        await _createTableIfMissing(m, messengerConversations);
        await _createTableIfMissing(m, messengerMessages);
        await _createTableIfMissing(m, messengerMailboxCursors);
      }
      if (from < 16) {
        await _createTableIfMissing(m, contactRecords);
      }
      if (from < 17) {
        await _createTableIfMissing(m, murmurEmbeddings);
      }
      if (from < 18) {
        await _createTableIfMissing(m, passportWalletExtensions);
      }
      if (from < 19) {
        await _addColumnIfMissing(
          m,
          passportWalletExtensions,
          passportWalletExtensions.nationalIdHash,
        );
        await _addColumnIfMissing(
          m,
          passportWalletExtensions,
          passportWalletExtensions.passportNumberHash,
        );
      }
      if (from < 20) {
        await _createTableIfMissing(m, didReputations);
      }
      if (from < 21) {
        await _addColumnIfMissing(
          m,
          hostedBoardProjections,
          hostedBoardProjections.postingPolicyJson,
        );
      }
      if (from < 22) {
        await _createTableIfMissing(m, notifications);
      }
      if (from < 23) {
        await _createTableIfMissing(m, hostModerationStates);
      }
      if (from < 24) {
        await _createTableIfMissing(m, identityAnchors);
      }
      if (from < 25) {
        await _addColumnIfMissing(m, posts, posts.signatureVerified);
        // Backfill: posts authored by a real DID were signed/verified (synced
        // ops pass signature verification; locally-signed posts use the user's
        // DID). Legacy 'user-local' placeholders stay false.
        await customStatement(
          "UPDATE posts SET signature_verified = 1 WHERE author_id LIKE 'did:%'",
        );
      }
      if (from < 26) {
        // Compliance-review gap #2: persist the host-declared constitution
        // compliance level on saved forum hosts.
        await _addColumnIfMissing(
          m,
          remoteNodes,
          remoteNodes.constitutionCompliance,
        );
      }
      if (from < 27) {
        await _createTableIfMissing(m, remoteTombstones);
      }
      if (from < 28) {
        await _addColumnIfMissing(
          m,
          contentItems,
          contentItems.signatureVerified,
        );
        // Public content authored by a DID was signed before publication. This
        // restores provenance for existing local-first databases instead of
        // making the UI depend on a still-present queue row or network lookup.
        await customStatement(
          "UPDATE content_items SET signature_verified = 1 "
          "WHERE author_did LIKE 'did:%' AND local_only = 0 "
          "AND visibility != 'private'",
        );
      }
      if (from < 29) {
        await _addColumnIfMissing(
          m,
          hostedBoardProjections,
          hostedBoardProjections.accessPolicyJson,
        );
        await _addColumnIfMissing(
          m,
          hostedBoardProjections,
          hostedBoardProjections.accessPolicyVersion,
        );
        await _addColumnIfMissing(
          m,
          hostedBoardProjections,
          hostedBoardProjections.contentVisibility,
        );
        await _addColumnIfMissing(
          m,
          hostedBoardProjections,
          hostedBoardProjections.federationPolicyJson,
        );
      }
      if (from < 30) {
        await _addColumnIfMissing(
          m,
          hostedBoardProjections,
          hostedBoardProjections.encryptionEpoch,
        );
        await _addColumnIfMissing(
          m,
          hostedBoardProjections,
          hostedBoardProjections.encryptionState,
        );
      }
      if (from < 31) {
        // P-256 is the only supported algorithm for new first-party identity
        // writes. Remove obsolete Ed25519 publication delivery state while
        // retaining the local-first content, Wallet credentials, operations,
        // and historical keys needed to read and verify existing records.
        await customStatement(
          'DELETE FROM publication_targets '
          'WHERE intent_id IN ('
          'SELECT intent_id FROM publication_intents '
          "WHERE signature_scheme = 'ed25519'"
          ')',
        );
        await customStatement(
          "DELETE FROM publication_intents "
          "WHERE signature_scheme = 'ed25519'",
        );
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

/// Thrown when the on-disk database was written by a NEWER app build than the
/// one now opening it (a downgrade). Migrations only move forward, so the older
/// build cannot safely read the newer schema; surfacing a clear error is far
/// better than the opaque failures that arise from running against an
/// unexpected schema.
class DatabaseDowngradeError extends Error {
  DatabaseDowngradeError({
    required this.storedVersion,
    required this.appVersion,
  });

  /// Schema version currently stored in the database file (the newer one).
  final int storedVersion;

  /// Schema version the running app expects (the older one).
  final int appVersion;

  @override
  String toString() =>
      'DatabaseDowngradeError: the local database is at schema v$storedVersion '
      'but this build only supports up to v$appVersion. This happens when an '
      'older app build is opened over a database written by a newer build. '
      'Update the app to the latest version, or remove the local database to '
      'start fresh (this discards local data).';
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dbFolder = Directory.current;
    final file = File(p.join(dbFolder.path, 'ansible.db'));
    return NativeDatabase.createInBackground(file);
  });
}
