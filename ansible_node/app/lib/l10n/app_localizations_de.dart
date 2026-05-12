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
  String get identityAndDevice => 'Identität & Gerät';

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
  String get syncSubtitle => 'Forum Host / Nostr relay Einstellungen';

  @override
  String get configured => 'Einstellungen';

  @override
  String get accessAudit => 'Zugriff & Audit';

  @override
  String get accessAuditSubtitle => 'Wer welche Identität sehen kann';

  @override
  String get noSuspiciousAccess => '0 verdächtig';

  @override
  String get language => 'Sprache';

  @override
  String get languageSubtitle => 'App-Sprache auswählen';

  @override
  String get systemDefault => 'Systemstandard';

  @override
  String get daily => 'Alltag';

  @override
  String get inbox => 'Posteingang';

  @override
  String get inboxSubtitle => 'Circle-Antworten, neue Mitglieder, Sync';

  @override
  String get notifications => 'Benachrichtigungen';

  @override
  String get notificationsSubtitle => 'Festlegen, was dich unterbrechen darf';

  @override
  String get light => 'Leicht';

  @override
  String get readingPreferences => 'Leseeinstellungen';

  @override
  String get readingPreferencesSubtitle => 'Schriftgröße, Zeilenhöhe, Thema';

  @override
  String get defaultValue => 'Standard';

  @override
  String get boundaries => 'Grenzen';

  @override
  String get lock => 'Sperren';

  @override
  String get lockSubtitle => 'App in eine leere Hülle verwandeln';

  @override
  String get off => 'Aus';

  @override
  String get backupRestore => 'Backup & Wiederherstellung';

  @override
  String get backupRestoreSubtitle => 'Passphrase, Migration auf neues Gerät';

  @override
  String get notSet => 'Nicht gesetzt';

  @override
  String get blockedList => 'Blockierliste';

  @override
  String get blockedListSubtitle =>
      'Du siehst sie nicht, und sie sehen dich nicht';

  @override
  String get about => 'Über Elix';

  @override
  String get aboutSubtitle => 'Ein Signal über stellare Distanz';

  @override
  String get manual => 'Handbuch';

  @override
  String get signOutDevice => 'Von diesem Gerät abmelden';

  @override
  String get signOutSubtitle =>
      'Daten behalten; beim nächsten Mal ist passkey nötig';

  @override
  String get languagePickerTitle => 'Sprache';

  @override
  String get languageSystemDescription =>
      'Spracheinstellung dieses Geräts verwenden';

  @override
  String get feedAll => 'Feed';

  @override
  String get feedFollowing => 'Folge ich';

  @override
  String get feedBoards => 'Boards';

  @override
  String get searchBack => '← Wiese';

  @override
  String get clear => 'Löschen';

  @override
  String get searchHint => 'Murmurs, Notizen, Diskussionen suchen';

  @override
  String get searchScopeAll => 'Alle';

  @override
  String get searchScopeMy => 'Meine';

  @override
  String get searchScopeCircle => 'Circle';

  @override
  String get searchScopePublic => 'Öffentlich';

  @override
  String searchResultCount(int count) {
    return '$count Treffer gefunden';
  }

  @override
  String get searchSortRelevant => '↓ Relevant';

  @override
  String notesSectionCount(int count) {
    return 'Notizen · $count';
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
  String get noNotesYet => 'Noch keine Notizen';

  @override
  String get noMatchingNotes => 'Keine passenden Notizen';

  @override
  String get noMurmursYet => 'Noch keine Murmurs';

  @override
  String get noMatchingMurmurs => 'Keine passenden Murmurs';

  @override
  String get noThreadsYet => 'Noch keine Threads';

  @override
  String get noMatchingThreads => 'Keine passenden Threads';

  @override
  String get murmurTitle => 'MURMUR';

  @override
  String get local => 'Lokal';

  @override
  String get send => 'Senden';

  @override
  String get murmurPrompt =>
      'Was Halbgeformtes\ngeht dir gerade durch den Kopf?';

  @override
  String get murmurPrivateHint =>
      'Ein Satz, ein Impuls oder eine ungeklärte Frage passt hierher. Niemand sonst sieht es.';

  @override
  String get murmurSyncHint =>
      'Ein Satz, ein Impuls oder eine ungeklärte Frage passt hierher. Dies wird als synchronisierbar markiert.';

  @override
  String get murmurInputHint => 'Woran ich in letzter Zeit denke';

  @override
  String get murmurPrivateVisibilityHint => 'Nur für mich';

  @override
  String get murmurUnlistedVisibilityHint =>
      'Synchronisierbar, aber ungelistet';

  @override
  String get murmurPublicVisibilityHint => 'Öffentlich veröffentlichen';

  @override
  String get looseMurmurs => 'Lose';

  @override
  String get looseMurmursEmpty => 'Gesendete Murmurs bleiben zuerst hier.';

  @override
  String get sent => 'Gesendet';

  @override
  String get deletedMurmur => 'Murmur gelöscht';

  @override
  String get unused => 'Ungenutzt';

  @override
  String referenceCount(int count) {
    return '$count Verweise';
  }

  @override
  String get search => 'Suchen';

  @override
  String get settingsNav => 'Einstellungen';

  @override
  String get publicIdentity => 'Öffentliche Identität';

  @override
  String get murmurTab => 'Murmur';

  @override
  String get notesTab => 'Notizen';

  @override
  String get discussionsTab => 'Boards';

  @override
  String get discussionsTabCompact => 'Boards';

  @override
  String get networkOnline => 'Online';

  @override
  String get networkOffline => 'Offline';

  @override
  String get networkChecking => 'Prüfen';

  @override
  String get workingNotes => 'Arbeitsnotizen';

  @override
  String get newest => 'Neueste';

  @override
  String get oldest => 'Älteste';

  @override
  String get newNote => 'Neue Notiz';

  @override
  String get drawInAction => '↗ Einfügen';

  @override
  String get noLooseMurmursYet => 'Noch keine losen Murmurs.';

  @override
  String get lineage => 'Herkunft';

  @override
  String get noteCreated => 'Notiz erstellt';

  @override
  String get cancel => 'Abbrechen';

  @override
  String get draftLocal => 'Entwurf bleibt lokal';

  @override
  String get editing => 'Bearbeiten';

  @override
  String get noteTitleHint => 'Notiztitel';

  @override
  String get noteTitleRequired => 'Titel eingeben';

  @override
  String get noteBodyHint =>
      'Weiterschreiben oder unten einen Murmur hineinziehen...';

  @override
  String get noteBodyRequired => 'Notiztext eingeben';

  @override
  String get noteSubjectLabel => 'diese Notiz';

  @override
  String get drawIn => 'Einfügen';

  @override
  String get noMurmursToDraw => 'Noch keine Murmurs zum Einfügen.';

  @override
  String get noNotesDescription =>
      'Murmurs bleiben zuerst lokal lose; wenn sie sich verbinden, werden sie zu einer Notiz.';

  @override
  String get noteUpdated => 'Notiz aktualisiert';

  @override
  String get visibilityUpdated => 'Sichtbarkeit aktualisiert';

  @override
  String get lineageDescription =>
      'Aus Murmurs geformte Notizen behalten hier ihre Quellen.';

  @override
  String get notePrivateSummary => 'Noch für niemand anderen sichtbar';

  @override
  String get noteNostrSummary => 'Veröffentlichen sendet dies an Nostr relays';

  @override
  String get noteActivityPubSummary =>
      'Veröffentlichen sendet dies an den ActivityPub relay';

  @override
  String get noteBothSummary =>
      'Veröffentlichen sendet dies an Nostr relays und den ActivityPub relay';

  @override
  String get noteLocalPublicSummary =>
      'Öffentlicher Status, aber noch nicht gesendet';

  @override
  String get createDiscussion => 'Diskussion erstellen';

  @override
  String get chooseHostedBoard => 'Hosted Board wählen';

  @override
  String get hostedBoardMissing =>
      'Tritt zuerst einem Forum-Host-Board bei oder erstelle eines';

  @override
  String get hostedBoardRequired => 'Hosted Board auswählen';

  @override
  String get titleLabel => 'Titel';

  @override
  String get discussionTitleHint => 'Diskussionstitel eingeben';

  @override
  String get titleRequired => 'Titel ist erforderlich';

  @override
  String get contentLabel => 'Inhalt';

  @override
  String get discussionContentHint => 'Diskussionsinhalt eingeben';

  @override
  String get contentRequired => 'Inhalt ist erforderlich';

  @override
  String get create => 'Erstellen';

  @override
  String get uncategorized => 'Nicht kategorisiert';

  @override
  String get addForumHostFirst =>
      'Füge zuerst in den Sync-Einstellungen einen Forum Host hinzu. Diskussionsboards werden von Forum Hosts erstellt.';

  @override
  String syncedPublicCount(int count) {
    return '$count öffentliche Inhalte synchronisiert';
  }

  @override
  String get publicQueuedRelayFailed =>
      'Öffentliche Inhalte wurden eingereiht, aber die Relay-Veröffentlichung ist fehlgeschlagen';

  @override
  String get noWritableNostrRelay =>
      'Kein beschreibbarer Nostr relay konfiguriert';

  @override
  String syncFailedMessage(String error) {
    return 'Synchronisierung fehlgeschlagen: $error';
  }

  @override
  String get justNow => 'Gerade eben';

  @override
  String minutesAgo(int count) {
    return 'vor $count Minuten';
  }

  @override
  String hoursAgo(int count) {
    return 'vor $count Stunden';
  }

  @override
  String daysAgo(int count) {
    return 'vor $count Tagen';
  }

  @override
  String get circleSection => 'Circle';

  @override
  String get allActivity => 'Alle Aktivitäten';

  @override
  String boardCount(int count) {
    return '$count Boards';
  }

  @override
  String get manageSubscriptions => 'Abos verwalten';

  @override
  String get newPost => 'Neuer Beitrag';

  @override
  String get addBoardTooltip => 'Board hinzufügen';

  @override
  String get newDiscussion => 'Neuer Board-Thread';

  @override
  String get createNewDiscussion => 'Board-Thread erstellen';

  @override
  String get boardsShort => 'Boards';

  @override
  String get manageBoardsShort => 'Boards verwalten';

  @override
  String get aiAssistant => 'AI Assistent';

  @override
  String get aiSummary => 'AI Zusammenfassung';

  @override
  String get noPostsYet => 'Noch keine Feed-Beiträge';

  @override
  String get subscribe => 'Abonnieren';

  @override
  String get discussionAreaTitle => 'Feed';

  @override
  String get feedSocialIdentitySubtitle =>
      'Notes und Murmurs sind persönliche Beiträge. Menschen, die dir folgen, sehen sie im Feed; Boards bringen gemeinsame Diskussionen dazu.';

  @override
  String get publicOpen => 'Menschen + Boards';

  @override
  String get noContentYet => '(Noch kein Inhalt)';

  @override
  String commentsCount(int count) {
    return '$count Kommentare';
  }

  @override
  String get manageBoards => 'Boards verwalten';

  @override
  String get noBoardsYet => 'Noch keine Boards';

  @override
  String get deleteBoard => 'Board löschen';

  @override
  String deleteBoardConfirm(String title) {
    return '\"$title\" löschen? Dies kann nicht rückgängig gemacht werden.';
  }

  @override
  String get delete => 'Löschen';

  @override
  String get close => 'Schließen';

  @override
  String get addBoard => 'Board hinzufügen';
}
