// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Italian (`it`).
class AppLocalizationsIt extends AppLocalizations {
  AppLocalizationsIt([String locale = 'it']) : super(locale);

  @override
  String get appTitle => 'Elix';

  @override
  String get settingsTitle => 'IMPOSTAZIONI';

  @override
  String get done => 'Fine';

  @override
  String get localIdentity => 'Identità locale';

  @override
  String get localDid => 'DID locale';

  @override
  String get edit => 'Modifica';

  @override
  String get identityAndDevice => 'Identità e dispositivo';

  @override
  String get wallet => 'Portafoglio';

  @override
  String get walletSubtitleEmpty => 'Nessuna credenziale';

  @override
  String walletSubtitleCount(int count) {
    return '$count credenziali';
  }

  @override
  String get empty => 'Vuoto';

  @override
  String get sync => 'Sincronizza';

  @override
  String get syncSubtitle => 'Impostazioni Elix Relay';

  @override
  String get configured => 'Impostazioni';

  @override
  String get accessAudit => 'Accesso e audit';

  @override
  String get accessAuditSubtitle => 'Chi può vedere quale identità';

  @override
  String get noSuspiciousAccess => '0 accessi sospetti';

  @override
  String get language => 'Lingua';

  @override
  String get languageSubtitle => 'Scegli la lingua dell’interfaccia';

  @override
  String get systemDefault => 'Lingua di sistema';

  @override
  String get daily => 'Quotidiano';

  @override
  String get inbox => 'Posta in arrivo';

  @override
  String get inboxSubtitle => 'Risposte, nuovi membri e sincronizzazione';

  @override
  String get notifications => 'Notifiche';

  @override
  String get notificationsSubtitle => 'Scegli cosa può interromperti';

  @override
  String get light => 'Light';

  @override
  String get readingPreferences => 'Preferenze di lettura';

  @override
  String get readingPreferencesSubtitle =>
      'Dimensione testo, interlinea e tema';

  @override
  String get defaultValue => 'Predefinito';

  @override
  String get boundaries => 'Confini';

  @override
  String get lock => 'Lock';

  @override
  String get lockSubtitle => 'Turn the app into a blank cover';

  @override
  String get off => 'Off';

  @override
  String get backupRestore => 'Backup e ripristino';

  @override
  String get backupRestoreSubtitle =>
      'Passphrase e migrazione su un nuovo dispositivo';

  @override
  String get notSet => 'Non impostato';

  @override
  String get blockedList => 'Elenco bloccati';

  @override
  String get blockedListSubtitle => 'Non potete vedervi a vicenda';

  @override
  String get about => 'Informazioni su Elix';

  @override
  String get aboutSubtitle => 'Un segnale attraverso la distanza interstellare';

  @override
  String get manual => 'Manuale';

  @override
  String get signOutDevice => 'Disconnetti da questo dispositivo';

  @override
  String get signOutSubtitle =>
      'Conserva i dati; la prossima volta servirà una passkey';

  @override
  String get languagePickerTitle => 'Lingua';

  @override
  String get languageSystemDescription => 'Usa la lingua di questo dispositivo';

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
  String get search => 'Cerca';

  @override
  String get settingsNav => 'Impostazioni';

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
  String get networkChecking => 'Verifica';

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
  String get cancel => 'Annulla';

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
    return 'Sincronizzazione non riuscita: $error';
  }

  @override
  String get justNow => 'Adesso';

  @override
  String minutesAgo(int count) {
    return '$count min fa';
  }

  @override
  String hoursAgo(int count) {
    return '$count h fa';
  }

  @override
  String daysAgo(int count) {
    return '$count g fa';
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
