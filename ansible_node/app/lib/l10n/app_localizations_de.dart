// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for German (`de`).
class AppLocalizationsDe extends AppLocalizations {
  AppLocalizationsDe([String locale = 'de']) : super(locale);

  @override
  String get appTitle => 'Elix';

  @override
  String get settingsTitle => 'EINSTELLUNGEN';

  @override
  String get done => 'Fertig';

  @override
  String get localIdentity => 'Lokale Identität';

  @override
  String get localDid => 'Lokale DID';

  @override
  String get edit => 'Bearbeiten';

  @override
  String get identityAndDevice => 'Identität und Gerät';

  @override
  String get wallet => 'Wallet';

  @override
  String get walletSubtitleEmpty => 'Keine Nachweise';

  @override
  String walletSubtitleCount(int count) {
    return '$count Nachweise';
  }

  @override
  String get empty => 'Leer';

  @override
  String get sync => 'Synchronisieren';

  @override
  String get syncSubtitle => 'Elix Relay-Einstellungen';

  @override
  String get configured => 'Einstellungen';

  @override
  String get accessAudit => 'Zugriff und Audit';

  @override
  String get accessAuditSubtitle => 'Wer welche Identität sehen kann';

  @override
  String get noSuspiciousAccess => '0 verdächtige Zugriffe';

  @override
  String get language => 'Sprache';

  @override
  String get languageSubtitle => 'Sprache der App-Oberfläche wählen';

  @override
  String get systemDefault => 'Systemsprache';

  @override
  String get daily => 'Alltag';

  @override
  String get inbox => 'Posteingang';

  @override
  String get inboxSubtitle => 'Antworten, neue Mitglieder, Synchronisierung';

  @override
  String get notifications => 'Benachrichtigungen';

  @override
  String get notificationsSubtitle => 'Festlegen, was dich unterbrechen darf';

  @override
  String get light => 'Light';

  @override
  String get readingPreferences => 'Leseeinstellungen';

  @override
  String get readingPreferencesSubtitle => 'Textgröße, Zeilenhöhe, Thema';

  @override
  String get defaultValue => 'Standard';

  @override
  String get boundaries => 'Grenzen';

  @override
  String get lock => 'Lock';

  @override
  String get lockSubtitle => 'Turn the app into a blank cover';

  @override
  String get off => 'Off';

  @override
  String get backupRestore => 'Sichern und Wiederherstellen';

  @override
  String get backupRestoreSubtitle => 'Passphrase, Umzug auf ein neues Gerät';

  @override
  String get notSet => 'Nicht eingerichtet';

  @override
  String get blockedList => 'Blockierliste';

  @override
  String get blockedListSubtitle => 'Ihr könnt euch gegenseitig nicht sehen';

  @override
  String get about => 'Über Elix';

  @override
  String get aboutSubtitle => 'Ein Signal über interstellare Distanz';

  @override
  String get manual => 'Handbuch';

  @override
  String get signOutDevice => 'Von diesem Gerät abmelden';

  @override
  String get signOutSubtitle =>
      'Daten behalten; beim nächsten Mal ist ein Passkey nötig';

  @override
  String get languagePickerTitle => 'Sprache';

  @override
  String get languageSystemDescription =>
      'Spracheinstellung dieses Geräts verwenden';

  @override
  String get feedAll => 'Feed';

  @override
  String get feedFollowing => 'Following';

  @override
  String get feedBoards => 'Boards';

  @override
  String get searchBack => '← Meadow';

  @override
  String get clear => 'Clear';

  @override
  String get searchHint => 'Search murmurs, notes, discussions';

  @override
  String get searchScopeAll => 'All';

  @override
  String get searchScopeMy => 'My';

  @override
  String get searchScopeCircle => 'Circle';

  @override
  String get searchScopePublic => 'Public';

  @override
  String searchResultCount(int count) {
    return 'Found $count mentions';
  }

  @override
  String get searchSortRelevant => '↓ Relevant';

  @override
  String notesSectionCount(int count) {
    return 'Notes · $count';
  }

  @override
  String murmursSectionCount(int count) {
    return 'Murmurs · $count';
  }

  @override
  String threadsSectionCount(int count) {
    return 'Threads · $count';
  }

  @override
  String get noNotesYet => 'No notes yet';

  @override
  String get noMatchingNotes => 'No matching notes';

  @override
  String get noMurmursYet => 'No murmurs yet';

  @override
  String get noMatchingMurmurs => 'No matching murmurs';

  @override
  String get noThreadsYet => 'No threads yet';

  @override
  String get noMatchingThreads => 'No matching threads';

  @override
  String get murmurTitle => 'MURMUR';

  @override
  String get local => 'Local';

  @override
  String get send => 'Send';

  @override
  String get murmurPrompt => 'What half-formed thing\nis on your mind?';

  @override
  String get murmurPrivateHint =>
      'A sentence, an instinct, an unresolved question all fit here. No one else will see it.';

  @override
  String get murmurSyncHint =>
      'A sentence, an instinct, an unresolved question all fit here. This one will be marked syncable.';

  @override
  String get murmurInputHint => 'What I have been thinking about lately is';

  @override
  String get murmurPrivateVisibilityHint => 'Only for me';

  @override
  String get murmurUnlistedVisibilityHint => 'Syncable but unlisted';

  @override
  String get murmurPublicVisibilityHint => 'Publish publicly';

  @override
  String get looseMurmurs => 'Loose';

  @override
  String get looseMurmursEmpty => 'Sent murmurs stay here first.';

  @override
  String get sent => 'Sent';

  @override
  String get deletedMurmur => 'Murmur deleted';

  @override
  String get unused => 'Unused';

  @override
  String referenceCount(int count) {
    return '$count references';
  }

  @override
  String get search => 'Suchen';

  @override
  String get settingsNav => 'Einstellungen';

  @override
  String get publicIdentity => 'Public identity';

  @override
  String get murmurTab => 'Murmur';

  @override
  String get notesTab => 'Notes';

  @override
  String get discussionsTab => 'Boards';

  @override
  String get discussionsTabCompact => 'Boards';

  @override
  String get networkOnline => 'Online';

  @override
  String get networkOffline => 'Offline';

  @override
  String get networkChecking => 'Wird geprüft';

  @override
  String get workingNotes => 'Working Notes';

  @override
  String get newest => 'Newest';

  @override
  String get oldest => 'Oldest';

  @override
  String get newNote => 'New Note';

  @override
  String get drawInAction => '↗ Draw in';

  @override
  String get noLooseMurmursYet => 'No loose murmurs yet.';

  @override
  String get lineage => 'Lineage';

  @override
  String get noteCreated => 'Note created';

  @override
  String get cancel => 'Abbrechen';

  @override
  String get draftLocal => 'Draft stays local';

  @override
  String get editing => 'Editing';

  @override
  String get noteTitleHint => 'Note title';

  @override
  String get noteTitleRequired => 'Enter a title';

  @override
  String get noteBodyHint => 'Keep writing, or drag a murmur in from below...';

  @override
  String get noteBodyRequired => 'Enter note body';

  @override
  String get noteSubjectLabel => 'this note';

  @override
  String get drawIn => 'Draw in';

  @override
  String get noMurmursToDraw => 'No murmurs to draw in yet.';

  @override
  String get noNotesDescription =>
      'Murmurs stay loose locally first; when they start to connect, shape them into a note.';

  @override
  String get noteUpdated => 'Note updated';

  @override
  String get visibilityUpdated => 'Visibility updated';

  @override
  String get lineageDescription =>
      'Notes shaped from murmurs keep their source lineage here.';

  @override
  String get notePrivateSummary => 'No one else can see this yet';

  @override
  String get noteNostrSummary => 'Publishing sends this to Nostr relays';

  @override
  String get noteActivityPubSummary =>
      'Publishing sends this to the ActivityPub relay';

  @override
  String get noteBothSummary =>
      'Publishing sends this to Nostr relays and the ActivityPub relay';

  @override
  String get noteLocalPublicSummary => 'Public state, but not sent yet';

  @override
  String get createDiscussion => 'Create Discussion';

  @override
  String get chooseHostedBoard => 'Choose board';

  @override
  String get hostedBoardMissing => 'Join or create an Elix Relay board first';

  @override
  String get hostedBoardRequired => 'Choose a board';

  @override
  String get titleLabel => 'Title';

  @override
  String get discussionTitleHint => 'Enter discussion title';

  @override
  String get titleRequired => 'Title is required';

  @override
  String get contentLabel => 'Content';

  @override
  String get discussionContentHint => 'Enter discussion content';

  @override
  String get contentRequired => 'Content is required';

  @override
  String get create => 'Create';

  @override
  String get uncategorized => 'Uncategorized';

  @override
  String get addForumHostFirst =>
      'Add an Elix Relay in Sync settings first. Discussion boards are created by Elix Relays.';

  @override
  String syncedPublicCount(int count) {
    return 'Synced $count public items';
  }

  @override
  String get publicQueuedRelayFailed =>
      'Public content was queued, but relay publishing failed';

  @override
  String get noWritableNostrRelay => 'No writable Nostr relay is configured';

  @override
  String syncFailedMessage(String error) {
    return 'Synchronisierung fehlgeschlagen: $error';
  }

  @override
  String get justNow => 'Gerade eben';

  @override
  String minutesAgo(int count) {
    return 'Vor $count Min.';
  }

  @override
  String hoursAgo(int count) {
    return 'Vor $count Std.';
  }

  @override
  String daysAgo(int count) {
    return 'Vor $count Tagen';
  }

  @override
  String get circleSection => 'Circle';

  @override
  String get allActivity => 'All Activity';

  @override
  String boardCount(int count) {
    return '$count boards';
  }

  @override
  String get manageSubscriptions => 'Manage Subscriptions';

  @override
  String get newPost => 'New Post';

  @override
  String get addBoardTooltip => 'Add Board';

  @override
  String get newDiscussion => 'New Board Thread';

  @override
  String get createNewDiscussion => 'Create Board Thread';

  @override
  String get boardsShort => 'Boards';

  @override
  String get manageBoardsShort => 'Manage Boards';

  @override
  String get aiAssistant => 'AI Assistant';

  @override
  String get aiSummary => 'AI Summary';

  @override
  String get noPostsYet => 'No feed posts yet';

  @override
  String get subscribe => 'Subscribe';

  @override
  String get discussionAreaTitle => 'Feed';

  @override
  String get feedSocialIdentitySubtitle =>
      'Notes and Murmurs are personal posts. People who follow you see them in their feed; boards add shared discussions.';

  @override
  String get publicOpen => 'People + Boards';

  @override
  String get noContentYet => '(No content yet)';

  @override
  String commentsCount(int count) {
    return '$count comments';
  }

  @override
  String get manageBoards => 'Manage Boards';

  @override
  String get noBoardsYet => 'No boards yet';

  @override
  String get deleteBoard => 'Delete Board';

  @override
  String deleteBoardConfirm(String title) {
    return 'Delete \"$title\"? This cannot be undone.';
  }

  @override
  String get delete => 'Delete';

  @override
  String get close => 'Close';

  @override
  String get addBoard => 'Add Board';
}
