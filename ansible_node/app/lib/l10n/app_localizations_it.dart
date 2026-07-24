// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Italian (`it`).
class AppLocalizationsIt extends AppLocalizations {
  AppLocalizationsIt([String locale = 'it']) : super(locale);

  @override
  String get appTitle => 'Elise';

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
  String get light => 'Leggero';

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
  String get lock => 'Serratura';

  @override
  String get lockSubtitle => 'Trasforma l\'app in una copertina vuota';

  @override
  String get off => 'Spento';

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
  String get feedAll => 'Foraggio';

  @override
  String get feedFollowing => 'Seguente';

  @override
  String get feedBoards => 'Tavole';

  @override
  String get searchBack => '← Prato';

  @override
  String get clear => 'Chiaro';

  @override
  String get searchHint => 'Cerca mormorii, appunti, discussioni';

  @override
  String get searchScopeAll => 'Tutto';

  @override
  String get searchScopeMy => 'Mio';

  @override
  String get searchScopeCircle => 'Cerchio';

  @override
  String get searchScopePublic => 'Pubblico';

  @override
  String searchResultCount(int count) {
    return 'Trovate menzioni $count';
  }

  @override
  String get searchSortRelevant => '↓ Rilevante';

  @override
  String notesSectionCount(int count) {
    return 'Note · $count';
  }

  @override
  String murmursSectionCount(int count) {
    return 'Mormorii · $count';
  }

  @override
  String threadsSectionCount(int count) {
    return 'Discussioni · $count';
  }

  @override
  String get noNotesYet => 'Nessuna nota ancora';

  @override
  String get noMatchingNotes => 'Nessuna nota corrispondente';

  @override
  String get noMurmursYet => 'Ancora nessun mormorio';

  @override
  String get noMatchingMurmurs => 'Nessun mormorio corrispondente';

  @override
  String get noThreadsYet => 'Nessun thread ancora';

  @override
  String get noMatchingThreads => 'Nessun thread corrispondente';

  @override
  String get murmurTitle => 'MORMORIO';

  @override
  String get local => 'Locale';

  @override
  String get send => 'Inviare';

  @override
  String get murmurPrompt => 'Che cosa formata a metà\nhai in mente?';

  @override
  String get murmurPrivateHint =>
      'Qui c\'entra una frase, un istinto, una questione irrisolta. Nessun altro lo vedrà.';

  @override
  String get murmurSyncHint =>
      'Qui c\'entra una frase, un istinto, una questione irrisolta. Questo sarà contrassegnato come sincronizzabile.';

  @override
  String get murmurInputHint => 'Quello a cui ho pensato ultimamente è';

  @override
  String get murmurPrivateVisibilityHint => 'Solo per me';

  @override
  String get murmurUnlistedVisibilityHint => 'Sincronizzabile ma non in elenco';

  @override
  String get murmurPublicVisibilityHint => 'Pubblica pubblicamente';

  @override
  String get looseMurmurs => 'Sciolto';

  @override
  String get looseMurmursEmpty => 'I mormorii inviati restano qui per primi.';

  @override
  String get sent => 'Inviato';

  @override
  String get deletedMurmur => 'Mormorio cancellato';

  @override
  String get unused => 'Inutilizzato';

  @override
  String referenceCount(int count) {
    return 'Riferimenti $count';
  }

  @override
  String get search => 'Cerca';

  @override
  String get settingsNav => 'Impostazioni';

  @override
  String get publicIdentity => 'Identità pubblica';

  @override
  String get murmurTab => 'Mormorio';

  @override
  String get notesTab => 'Note';

  @override
  String get discussionsTab => 'Tavole';

  @override
  String get discussionsTabCompact => 'Tavole';

  @override
  String get networkOnline => 'Online';

  @override
  String get networkOffline => 'Offline';

  @override
  String get networkChecking => 'Verifica';

  @override
  String get workingNotes => 'Note di lavoro';

  @override
  String get newest => 'Più recente';

  @override
  String get oldest => 'Il più antico';

  @override
  String get newNote => 'Nuova nota';

  @override
  String get drawInAction => '↗ Attrai';

  @override
  String get noLooseMurmursYet => 'Nessun mormorio sciolto ancora.';

  @override
  String get lineage => 'Lignaggio';

  @override
  String get noteCreated => 'Nota creata';

  @override
  String get cancel => 'Annulla';

  @override
  String get draftLocal => 'Il tiraggio rimane locale';

  @override
  String get editing => 'Modifica';

  @override
  String get noteTitleHint => 'Titolo della nota';

  @override
  String get noteTitleRequired => 'Inserisci un titolo';

  @override
  String get noteBodyHint =>
      'Continua a scrivere, o trascina un mormorio dal basso...';

  @override
  String get noteBodyRequired => 'Inserisci il corpo della nota';

  @override
  String get noteSubjectLabel => 'questa nota';

  @override
  String get drawIn => 'Attira';

  @override
  String get noMurmursToDraw => 'Nessun mormorio da attirare ancora.';

  @override
  String get noNotesDescription =>
      'I soffi rimangono inizialmente liberi a livello locale; quando iniziano a connettersi, modellali in una nota.';

  @override
  String get noteUpdated => 'Nota aggiornata';

  @override
  String get visibilityUpdated => 'Visibilità aggiornata';

  @override
  String get lineageDescription =>
      'Le note formate dai soffi mantengono qui la loro origine.';

  @override
  String get notePrivateSummary => 'Nessun altro può ancora vederlo';

  @override
  String get noteNostrSummary => 'La pubblicazione lo invia ai relè Nostr';

  @override
  String get noteActivityPubSummary =>
      'La pubblicazione lo invia al relè ActivityPub';

  @override
  String get noteBothSummary =>
      'La pubblicazione lo invia ai relè Nostr e al relè ActivityPub';

  @override
  String get noteLocalPublicSummary => 'Stato pubblico, ma non ancora inviato';

  @override
  String get createDiscussion => 'Crea discussione';

  @override
  String get chooseHostedBoard => 'Scegli la tavola';

  @override
  String get hostedBoardMissing =>
      'Unisciti o crea prima una scheda Elix Relay';

  @override
  String get hostedBoardRequired => 'Scegli una tavola';

  @override
  String get titleLabel => 'Titolo';

  @override
  String get discussionTitleHint => 'Inserisci il titolo della discussione';

  @override
  String get titleRequired => 'Il titolo è obbligatorio';

  @override
  String get contentLabel => 'Contenuto';

  @override
  String get discussionContentHint =>
      'Inserisci il contenuto della discussione';

  @override
  String get contentRequired => 'Il contenuto è obbligatorio';

  @override
  String get create => 'Creare';

  @override
  String get uncategorized => 'Senza categoria';

  @override
  String get addForumHostFirst =>
      'Aggiungi prima un relè Elix nelle impostazioni di sincronizzazione. I forum di discussione sono creati da Elix Relays.';

  @override
  String syncedPublicCount(int count) {
    return 'Elementi pubblici $count sincronizzati';
  }

  @override
  String get publicQueuedRelayFailed =>
      'Il contenuto pubblico è stato messo in coda, ma la pubblicazione tramite inoltro non è riuscita';

  @override
  String get noWritableNostrRelay =>
      'Nessun relè Nostr scrivibile è configurato';

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
  String get circleSection => 'Cerchio';

  @override
  String get allActivity => 'Tutte le attività';

  @override
  String boardCount(int count) {
    return 'Tavole $count';
  }

  @override
  String get manageSubscriptions => 'Gestisci abbonamenti';

  @override
  String get newPost => 'Nuovo messaggio';

  @override
  String get addBoardTooltip => 'Aggiungi tavola';

  @override
  String get newDiscussion => 'Nuovo thread della scheda';

  @override
  String get createNewDiscussion => 'Crea discussione sulla scheda';

  @override
  String get boardsShort => 'Tavole';

  @override
  String get manageBoardsShort => 'Gestisci bacheche';

  @override
  String get aiAssistant => 'Assistente AI';

  @override
  String get aiSummary => 'Riepilogo dell\'IA';

  @override
  String get noPostsYet => 'Nessun post nel feed ancora';

  @override
  String get subscribe => 'Iscriviti';

  @override
  String get discussionAreaTitle => 'Foraggio';

  @override
  String get feedSocialIdentitySubtitle =>
      'Note e Mormorii sono post personali. Le persone che ti seguono le vedono nel loro feed; le bacheche aggiungono discussioni condivise.';

  @override
  String get publicOpen => 'Persone + Tabelloni';

  @override
  String get noContentYet => '(Nessun contenuto ancora)';

  @override
  String commentsCount(int count) {
    return 'Commenti di $count';
  }

  @override
  String get manageBoards => 'Gestisci bacheche';

  @override
  String get noBoardsYet => 'Nessuna bacheca ancora';

  @override
  String get deleteBoard => 'Elimina bacheca';

  @override
  String deleteBoardConfirm(String title) {
    return 'Eliminare \"$title\"? Questa operazione non può essere annullata.';
  }

  @override
  String get delete => 'Eliminare';

  @override
  String get close => 'Vicino';

  @override
  String get addBoard => 'Aggiungi tavola';
}
