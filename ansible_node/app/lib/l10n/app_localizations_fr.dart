// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for French (`fr`).
class AppLocalizationsFr extends AppLocalizations {
  AppLocalizationsFr([String locale = 'fr']) : super(locale);

  @override
  String get appTitle => 'Ansible Node';

  @override
  String get settingsTitle => 'RÉGLAGES';

  @override
  String get done => 'Terminé';

  @override
  String get localIdentity => 'Identité locale';

  @override
  String get localDid => 'DID local';

  @override
  String get edit => 'Modifier';

  @override
  String get identityAndDevice => 'Identité et appareil';

  @override
  String get wallet => 'Portefeuille';

  @override
  String get walletSubtitleEmpty => 'Aucun justificatif';

  @override
  String walletSubtitleCount(int count) {
    return '$count justificatifs';
  }

  @override
  String get empty => 'Vide';

  @override
  String get sync => 'Synchroniser';

  @override
  String get syncSubtitle => 'Réglages Forum Host / Nostr relay';

  @override
  String get configured => 'Réglages';

  @override
  String get accessAudit => 'Accès et audit';

  @override
  String get accessAuditSubtitle => 'Qui peut voir quelle identité';

  @override
  String get noSuspiciousAccess => '0 suspect';

  @override
  String get language => 'Langue';

  @override
  String get languageSubtitle => 'Choisir la langue de l’app';

  @override
  String get systemDefault => 'Langue du système';

  @override
  String get daily => 'Quotidien';

  @override
  String get inbox => 'Boîte de réception';

  @override
  String get inboxSubtitle => 'Réponses de cercles, nouveaux membres, synchro';

  @override
  String get notifications => 'Notifications';

  @override
  String get notificationsSubtitle => 'Décider ce qui peut vous interrompre';

  @override
  String get light => 'Léger';

  @override
  String get readingPreferences => 'Préférences de lecture';

  @override
  String get readingPreferencesSubtitle => 'Taille du texte, interligne, thème';

  @override
  String get defaultValue => 'Par défaut';

  @override
  String get boundaries => 'Limites';

  @override
  String get lock => 'Verrouiller';

  @override
  String get lockSubtitle => 'Transformer l’app en couverture vide';

  @override
  String get off => 'Désactivé';

  @override
  String get backupRestore => 'Sauvegarde et restauration';

  @override
  String get backupRestoreSubtitle =>
      'Phrase secrète, migration vers un nouvel appareil';

  @override
  String get notSet => 'Non défini';

  @override
  String get blockedList => 'Liste de blocage';

  @override
  String get blockedListSubtitle =>
      'Vous ne les voyez pas, et ils ne vous voient pas';

  @override
  String get about => 'À propos d’Ansible';

  @override
  String get aboutSubtitle => 'Un signal au-delà des distances stellaires';

  @override
  String get manual => 'Manuel';

  @override
  String get signOutDevice => 'Se déconnecter de cet appareil';

  @override
  String get signOutSubtitle =>
      'Conserver les données; passkey requis la prochaine fois';

  @override
  String get languagePickerTitle => 'Langue';

  @override
  String get languageSystemDescription => 'Utiliser la langue de cet appareil';

  @override
  String get feedAll => 'Tout';

  @override
  String get feedFollowing => 'Abonnements';

  @override
  String get feedBoards => 'Forums';

  @override
  String get searchBack => '← Prairie';

  @override
  String get clear => 'Effacer';

  @override
  String get searchHint => 'Rechercher murmurs, notes, discussions';

  @override
  String get searchScopeAll => 'Tout';

  @override
  String get searchScopeMy => 'Moi';

  @override
  String get searchScopeCircle => 'Cercle';

  @override
  String get searchScopePublic => 'Public';

  @override
  String searchResultCount(int count) {
    return '$count mentions trouvées';
  }

  @override
  String get searchSortRelevant => '↓ Pertinent';

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
    return 'Fils · $count';
  }

  @override
  String get noNotesYet => 'Aucune note pour le moment';

  @override
  String get noMatchingNotes => 'Aucune note correspondante';

  @override
  String get noMurmursYet => 'Aucun murmur pour le moment';

  @override
  String get noMatchingMurmurs => 'Aucun murmur correspondant';

  @override
  String get noThreadsYet => 'Aucun fil pour le moment';

  @override
  String get noMatchingThreads => 'Aucun fil correspondant';

  @override
  String get murmurTitle => 'MURMUR';

  @override
  String get local => 'Local';

  @override
  String get send => 'Envoyer';

  @override
  String get murmurPrompt => 'Quelle pensée à moitié formée\nvous occupe ?';

  @override
  String get murmurPrivateHint =>
      'Une phrase, une intuition ou une question non résolue ont leur place ici. Personne d’autre ne les verra.';

  @override
  String get murmurSyncHint =>
      'Une phrase, une intuition ou une question non résolue ont leur place ici. Ce contenu sera marqué comme synchronisable.';

  @override
  String get murmurInputHint => 'Ce à quoi je pense ces derniers temps';

  @override
  String get murmurPrivateVisibilityHint => 'Seulement pour moi';

  @override
  String get murmurUnlistedVisibilityHint => 'Synchronisable mais non listé';

  @override
  String get murmurPublicVisibilityHint => 'Publier publiquement';

  @override
  String get looseMurmurs => 'Épars';

  @override
  String get looseMurmursEmpty => 'Les murmurs envoyés restent d’abord ici.';

  @override
  String get sent => 'Envoyé';

  @override
  String get deletedMurmur => 'Murmur supprimé';

  @override
  String get unused => 'Non utilisé';

  @override
  String referenceCount(int count) {
    return '$count références';
  }

  @override
  String get search => 'Rechercher';

  @override
  String get settingsNav => 'Réglages';

  @override
  String get publicIdentity => 'Identité publique';

  @override
  String get murmurTab => 'Murmur';

  @override
  String get notesTab => 'Notes';

  @override
  String get discussionsTab => 'Discussions';

  @override
  String get discussionsTabCompact => 'Forum';

  @override
  String get networkOnline => 'En ligne';

  @override
  String get networkOffline => 'Hors ligne';

  @override
  String get networkChecking => 'Vérification';

  @override
  String get workingNotes => 'Notes de travail';

  @override
  String get newest => 'Plus récentes';

  @override
  String get oldest => 'Plus anciennes';

  @override
  String get newNote => 'Nouvelle note';

  @override
  String get drawInAction => '↗ Intégrer';

  @override
  String get noLooseMurmursYet => 'Aucun murmur épars pour le moment.';

  @override
  String get lineage => 'Origine';

  @override
  String get noteCreated => 'Note créée';

  @override
  String get cancel => 'Annuler';

  @override
  String get draftLocal => 'Le brouillon reste local';

  @override
  String get editing => 'Modification';

  @override
  String get noteTitleHint => 'Titre de la note';

  @override
  String get noteTitleRequired => 'Saisir un titre';

  @override
  String get noteBodyHint =>
      'Continuez à écrire ou glissez un murmur depuis le bas...';

  @override
  String get noteBodyRequired => 'Saisir le contenu de la note';

  @override
  String get noteSubjectLabel => 'cette note';

  @override
  String get drawIn => 'Intégrer';

  @override
  String get noMurmursToDraw => 'Aucun murmur à intégrer pour le moment.';

  @override
  String get noNotesDescription =>
      'Les murmurs restent d’abord épars en local; lorsqu’ils se relient, transformez-les en note.';

  @override
  String get noteUpdated => 'Note mise à jour';

  @override
  String get visibilityUpdated => 'Visibilité mise à jour';

  @override
  String get lineageDescription =>
      'Les notes formées depuis des murmurs conservent ici leurs sources.';

  @override
  String get notePrivateSummary => 'Personne d’autre ne peut encore le voir';

  @override
  String get noteNostrSummary => 'La publication l’envoie aux Nostr relays';

  @override
  String get noteActivityPubSummary =>
      'La publication l’envoie au relay ActivityPub';

  @override
  String get noteBothSummary =>
      'La publication l’envoie aux Nostr relays et au relay ActivityPub';

  @override
  String get noteLocalPublicSummary => 'État public, mais pas encore envoyé';

  @override
  String get createDiscussion => 'Créer une discussion';

  @override
  String get chooseHostedBoard => 'Choisir un hosted board';

  @override
  String get hostedBoardMissing =>
      'Rejoignez ou créez d’abord un hosted board Forum Host';

  @override
  String get hostedBoardRequired => 'Choisir un hosted board';

  @override
  String get titleLabel => 'Titre';

  @override
  String get discussionTitleHint => 'Saisir le titre de la discussion';

  @override
  String get titleRequired => 'Le titre est obligatoire';

  @override
  String get contentLabel => 'Contenu';

  @override
  String get discussionContentHint => 'Saisir le contenu de la discussion';

  @override
  String get contentRequired => 'Le contenu est obligatoire';

  @override
  String get create => 'Créer';

  @override
  String get uncategorized => 'Non catégorisé';

  @override
  String get addForumHostFirst =>
      'Ajoutez d’abord un Forum Host dans les réglages de synchronisation. Les forums de discussion sont créés par les Forum Hosts.';

  @override
  String syncedPublicCount(int count) {
    return '$count contenus publics synchronisés';
  }

  @override
  String get publicQueuedRelayFailed =>
      'Le contenu public a été mis en file, mais la publication relay a échoué';

  @override
  String get noWritableNostrRelay =>
      'Aucun Nostr relay inscriptible n’est configuré';

  @override
  String syncFailedMessage(String error) {
    return 'Échec de synchronisation : $error';
  }

  @override
  String get justNow => 'À l’instant';

  @override
  String minutesAgo(int count) {
    return 'Il y a $count min';
  }

  @override
  String hoursAgo(int count) {
    return 'Il y a $count h';
  }

  @override
  String daysAgo(int count) {
    return 'Il y a $count j';
  }

  @override
  String get circleSection => 'Cercle';

  @override
  String get allActivity => 'Toute l’activité';

  @override
  String boardCount(int count) {
    return '$count forums';
  }

  @override
  String get manageSubscriptions => 'Gérer les abonnements';

  @override
  String get newPost => 'Nouvelle publication';

  @override
  String get addBoardTooltip => 'Ajouter un forum';

  @override
  String get newDiscussion => 'Nouvelle discussion';

  @override
  String get createNewDiscussion => 'Créer une discussion';

  @override
  String get boardsShort => 'Forums';

  @override
  String get manageBoardsShort => 'Gérer les forums';

  @override
  String get aiAssistant => 'Assistant AI';

  @override
  String get aiSummary => 'Résumé AI';

  @override
  String get noPostsYet => 'Aucune publication pour le moment';

  @override
  String get subscribe => 'S’abonner';

  @override
  String get discussionAreaTitle => 'Espace de discussion';

  @override
  String get publicOpen => 'Public · Open';

  @override
  String get noContentYet => '(Aucun contenu pour le moment)';

  @override
  String commentsCount(int count) {
    return '$count commentaires';
  }

  @override
  String get manageBoards => 'Gérer les forums';

  @override
  String get noBoardsYet => 'Aucun forum pour le moment';

  @override
  String get deleteBoard => 'Supprimer le forum';

  @override
  String deleteBoardConfirm(String title) {
    return 'Supprimer \"$title\" ? Cette action est irréversible.';
  }

  @override
  String get delete => 'Supprimer';

  @override
  String get close => 'Fermer';

  @override
  String get addBoard => 'Ajouter un forum';
}
