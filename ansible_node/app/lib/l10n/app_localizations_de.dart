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
  String get light => 'Licht';

  @override
  String get readingPreferences => 'Leseeinstellungen';

  @override
  String get readingPreferencesSubtitle => 'Textgröße, Zeilenhöhe, Thema';

  @override
  String get defaultValue => 'Standard';

  @override
  String get boundaries => 'Grenzen';

  @override
  String get lock => 'Sperren';

  @override
  String get lockSubtitle => 'Verwandeln Sie die App in ein leeres Cover';

  @override
  String get off => 'Aus';

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
  String get feedAll => 'Füttern';

  @override
  String get feedFollowing => 'Nachfolgend';

  @override
  String get feedBoards => 'Bretter';

  @override
  String get searchBack => '← Wiese';

  @override
  String get clear => 'Klar';

  @override
  String get searchHint => 'Suchen Sie nach Gemurmel, Notizen und Diskussionen';

  @override
  String get searchScopeAll => 'Alle';

  @override
  String get searchScopeMy => 'Mein';

  @override
  String get searchScopeCircle => 'Kreis';

  @override
  String get searchScopePublic => 'Öffentlich';

  @override
  String searchResultCount(int count) {
    return '$count-Erwähnungen gefunden';
  }

  @override
  String get searchSortRelevant => '↓ Relevant';

  @override
  String notesSectionCount(int count) {
    return 'Notizen · $count';
  }

  @override
  String murmursSectionCount(int count) {
    return 'Murmelt · $count';
  }

  @override
  String threadsSectionCount(int count) {
    return 'Themen · $count';
  }

  @override
  String get noNotesYet => 'Noch keine Notizen';

  @override
  String get noMatchingNotes => 'Keine passenden Notizen';

  @override
  String get noMurmursYet => 'Noch kein Murren';

  @override
  String get noMatchingMurmurs => 'Kein passendes Gemurmel';

  @override
  String get noThreadsYet => 'Noch keine Threads';

  @override
  String get noMatchingThreads => 'Keine passenden Threads';

  @override
  String get murmurTitle => 'MURMELN';

  @override
  String get local => 'Lokal';

  @override
  String get send => 'Schicken';

  @override
  String get murmurPrompt =>
      'Was für ein halbfertiges Ding\ngeht dir durch den Kopf?';

  @override
  String get murmurPrivateHint =>
      'Hier passt ein Satz, ein Instinkt, eine ungelöste Frage. Niemand sonst wird es sehen.';

  @override
  String get murmurSyncHint =>
      'Hier passt ein Satz, ein Instinkt, eine ungelöste Frage. Dieser wird als synchronisierbar markiert.';

  @override
  String get murmurInputHint =>
      'Worüber ich in letzter Zeit nachgedacht habe, ist';

  @override
  String get murmurPrivateVisibilityHint => 'Nur für mich';

  @override
  String get murmurUnlistedVisibilityHint =>
      'Synchronisierbar, aber nicht gelistet';

  @override
  String get murmurPublicVisibilityHint => 'Öffentlich veröffentlichen';

  @override
  String get looseMurmurs => 'Lose';

  @override
  String get looseMurmursEmpty => 'Gesendetes Murmeln bleibt zuerst hier.';

  @override
  String get sent => 'Gesendet';

  @override
  String get deletedMurmur => 'Murmeln gelöscht';

  @override
  String get unused => 'Unbenutzt';

  @override
  String referenceCount(int count) {
    return '$count-Referenzen';
  }

  @override
  String get search => 'Suchen';

  @override
  String get settingsNav => 'Einstellungen';

  @override
  String get publicIdentity => 'Öffentliche Identität';

  @override
  String get murmurTab => 'Murmeln';

  @override
  String get notesTab => 'Notizen';

  @override
  String get discussionsTab => 'Bretter';

  @override
  String get discussionsTabCompact => 'Bretter';

  @override
  String get networkOnline => 'Online';

  @override
  String get networkOffline => 'Offline';

  @override
  String get networkChecking => 'Wird geprüft';

  @override
  String get workingNotes => 'Arbeitsnotizen';

  @override
  String get newest => 'Neueste';

  @override
  String get oldest => 'Älteste';

  @override
  String get newNote => 'Neue Notiz';

  @override
  String get drawInAction => '↗ Einzeichnen';

  @override
  String get noLooseMurmursYet => 'Noch kein lockeres Gemurmel.';

  @override
  String get lineage => 'Abstammung';

  @override
  String get noteCreated => 'Notiz erstellt';

  @override
  String get cancel => 'Abbrechen';

  @override
  String get draftLocal => 'Draft bleibt lokal';

  @override
  String get editing => 'Bearbeitung';

  @override
  String get noteTitleHint => 'Titel der Notiz';

  @override
  String get noteTitleRequired => 'Geben Sie einen Titel ein';

  @override
  String get noteBodyHint =>
      'Schreiben Sie weiter oder ziehen Sie ein Murmeln von unten herein ...';

  @override
  String get noteBodyRequired => 'Geben Sie den Notiztext ein';

  @override
  String get noteSubjectLabel => 'dieser Hinweis';

  @override
  String get drawIn => 'Einziehen';

  @override
  String get noMurmursToDraw => 'Noch ist kein Murmeln zu hören.';

  @override
  String get noNotesDescription =>
      'Murmeltiere bleiben zunächst lokal locker; Wenn sie beginnen, sich zu verbinden, formen Sie sie zu einer Notiz.';

  @override
  String get noteUpdated => 'Hinweis aktualisiert';

  @override
  String get visibilityUpdated => 'Sichtbarkeit aktualisiert';

  @override
  String get lineageDescription =>
      'Aus Murmeln geformte Notizen behalten hier ihre ursprüngliche Abstammungslinie.';

  @override
  String get notePrivateSummary => 'Das kann noch niemand sonst sehen';

  @override
  String get noteNostrSummary => 'Publishing sendet dies an Nostr-Relays';

  @override
  String get noteActivityPubSummary =>
      'Publishing sendet dies an das ActivityPub-Relay';

  @override
  String get noteBothSummary =>
      'Die Veröffentlichung sendet dies an Nostr-Relays und das ActivityPub-Relay';

  @override
  String get noteLocalPublicSummary =>
      'Öffentlicher Status, aber noch nicht gesendet';

  @override
  String get createDiscussion => 'Diskussion erstellen';

  @override
  String get chooseHostedBoard => 'Wählen Sie ein Board';

  @override
  String get hostedBoardMissing =>
      'Treten Sie zunächst einem Elix-Relay-Board bei oder erstellen Sie ein solches';

  @override
  String get hostedBoardRequired => 'Wähle ein Board';

  @override
  String get titleLabel => 'Titel';

  @override
  String get discussionTitleHint => 'Geben Sie den Diskussionstitel ein';

  @override
  String get titleRequired => 'Titel ist erforderlich';

  @override
  String get contentLabel => 'Inhalt';

  @override
  String get discussionContentHint => 'Geben Sie Diskussionsinhalte ein';

  @override
  String get contentRequired => 'Inhalte sind erforderlich';

  @override
  String get create => 'Erstellen';

  @override
  String get uncategorized => 'Nicht kategorisiert';

  @override
  String get addForumHostFirst =>
      'Fügen Sie zunächst in den Synchronisierungseinstellungen ein Elix-Relay hinzu. Diskussionsforen werden von Elix Relays erstellt.';

  @override
  String syncedPublicCount(int count) {
    return 'Öffentliche $count-Elemente synchronisiert';
  }

  @override
  String get publicQueuedRelayFailed =>
      'Öffentliche Inhalte wurden in die Warteschlange gestellt, die Weiterleitungsveröffentlichung ist jedoch fehlgeschlagen';

  @override
  String get noWritableNostrRelay =>
      'Es ist kein beschreibbares Nostr-Relay konfiguriert';

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
  String get circleSection => 'Kreis';

  @override
  String get allActivity => 'Alle Aktivitäten';

  @override
  String boardCount(int count) {
    return '$count-Boards';
  }

  @override
  String get manageSubscriptions => 'Abonnements verwalten';

  @override
  String get newPost => 'Neuer Beitrag';

  @override
  String get addBoardTooltip => 'Board hinzufügen';

  @override
  String get newDiscussion => 'Neuer Board-Thread';

  @override
  String get createNewDiscussion => 'Erstellen Sie einen Board-Thread';

  @override
  String get boardsShort => 'Bretter';

  @override
  String get manageBoardsShort => 'Boards verwalten';

  @override
  String get aiAssistant => 'KI-Assistent';

  @override
  String get aiSummary => 'KI-Zusammenfassung';

  @override
  String get noPostsYet => 'Noch keine Feed-Beiträge';

  @override
  String get subscribe => 'Abonnieren';

  @override
  String get discussionAreaTitle => 'Füttern';

  @override
  String get feedSocialIdentitySubtitle =>
      'Notizen und Gemurmel sind persönliche Beiträge. Personen, die Ihnen folgen, sehen sie in ihrem Feed. Foren fügen gemeinsame Diskussionen hinzu.';

  @override
  String get publicOpen => 'Menschen + Boards';

  @override
  String get noContentYet => '(Noch kein Inhalt)';

  @override
  String commentsCount(int count) {
    return '$count-Kommentare';
  }

  @override
  String get manageBoards => 'Boards verwalten';

  @override
  String get noBoardsYet => 'Noch keine Boards';

  @override
  String get deleteBoard => 'Board löschen';

  @override
  String deleteBoardConfirm(String title) {
    return '„$title“ löschen? Dies kann nicht rückgängig gemacht werden.';
  }

  @override
  String get delete => 'Löschen';

  @override
  String get close => 'Schließen';

  @override
  String get addBoard => 'Board hinzufügen';
}
