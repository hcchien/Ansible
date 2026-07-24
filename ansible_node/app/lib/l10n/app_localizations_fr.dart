// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for French (`fr`).
class AppLocalizationsFr extends AppLocalizations {
  AppLocalizationsFr([String locale = 'fr']) : super(locale);

  @override
  String get appTitle => 'Élix';

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
  String get sync => 'Synchronisation';

  @override
  String get syncSubtitle => 'Réglages Elix Relay';

  @override
  String get configured => 'Réglages';

  @override
  String get accessAudit => 'Accès et audit';

  @override
  String get accessAuditSubtitle => 'Qui peut voir quelle identité';

  @override
  String get noSuspiciousAccess => '0 accès suspect';

  @override
  String get language => 'Langue';

  @override
  String get languageSubtitle => 'Choisir la langue de l’interface';

  @override
  String get systemDefault => 'Langue du système';

  @override
  String get daily => 'Quotidien';

  @override
  String get inbox => 'Boîte de réception';

  @override
  String get inboxSubtitle => 'Réponses, nouveaux membres, synchronisation';

  @override
  String get notifications => 'Notifications';

  @override
  String get notificationsSubtitle => 'Choisir ce qui peut vous interrompre';

  @override
  String get light => 'Lumière';

  @override
  String get readingPreferences => 'Préférences de lecture';

  @override
  String get readingPreferencesSubtitle => 'Taille du texte, interligne, thème';

  @override
  String get defaultValue => 'Par défaut';

  @override
  String get boundaries => 'Limites';

  @override
  String get lock => 'Verrouillage';

  @override
  String get lockSubtitle =>
      'Transformez l\'application en une couverture vierge';

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
  String get blockedListSubtitle => 'Vous ne pouvez pas vous voir mutuellement';

  @override
  String get about => 'À propos d’Elix';

  @override
  String get aboutSubtitle => 'Un signal à travers la distance interstellaire';

  @override
  String get manual => 'Manuel';

  @override
  String get signOutDevice => 'Se déconnecter de cet appareil';

  @override
  String get signOutSubtitle =>
      'Conserver les données ; passkey requise la prochaine fois';

  @override
  String get languagePickerTitle => 'Langue';

  @override
  String get languageSystemDescription => 'Utiliser la langue de cet appareil';

  @override
  String get feedAll => 'Alimentation';

  @override
  String get feedFollowing => 'Suivant';

  @override
  String get feedBoards => 'Planches';

  @override
  String get searchBack => '← Prairie';

  @override
  String get clear => 'Clair';

  @override
  String get searchHint =>
      'Rechercher des murmures, des notes, des discussions';

  @override
  String get searchScopeAll => 'Tous';

  @override
  String get searchScopeMy => 'Mon';

  @override
  String get searchScopeCircle => 'Cercle';

  @override
  String get searchScopePublic => 'Publique';

  @override
  String searchResultCount(int count) {
    return 'Mentions $count trouvées';
  }

  @override
  String get searchSortRelevant => '↓ Pertinent';

  @override
  String notesSectionCount(int count) {
    return 'Remarques · $count';
  }

  @override
  String murmursSectionCount(int count) {
    return 'Murmures · $count';
  }

  @override
  String threadsSectionCount(int count) {
    return 'Sujets · $count';
  }

  @override
  String get noNotesYet => 'Aucune note pour l\'instant';

  @override
  String get noMatchingNotes => 'Aucune note correspondante';

  @override
  String get noMurmursYet => 'Pas encore de murmures';

  @override
  String get noMatchingMurmurs => 'Aucun murmure correspondant';

  @override
  String get noThreadsYet => 'Pas encore de sujets';

  @override
  String get noMatchingThreads => 'Aucun fil correspondant';

  @override
  String get murmurTitle => 'MURMURE';

  @override
  String get local => 'Locale';

  @override
  String get send => 'Envoyer';

  @override
  String get murmurPrompt =>
      'Quelle chose à moitié formée\nest dans votre esprit ?';

  @override
  String get murmurPrivateHint =>
      'Une phrase, un instinct, une question non résolue ont leur place ici. Personne d\'autre ne le verra.';

  @override
  String get murmurSyncHint =>
      'Une phrase, un instinct, une question non résolue ont leur place ici. Celui-ci sera marqué synchronisable.';

  @override
  String get murmurInputHint =>
      'Ce à quoi j\'ai pensé ces derniers temps, c\'est';

  @override
  String get murmurPrivateVisibilityHint => 'Seulement pour moi';

  @override
  String get murmurUnlistedVisibilityHint =>
      'Synchronisable mais non répertorié';

  @override
  String get murmurPublicVisibilityHint => 'Publier publiquement';

  @override
  String get looseMurmurs => 'Lâche';

  @override
  String get looseMurmursEmpty =>
      'Les murmures envoyés restent ici en premier.';

  @override
  String get sent => 'Envoyé';

  @override
  String get deletedMurmur => 'Murmure supprimé';

  @override
  String get unused => 'Inutilisé';

  @override
  String referenceCount(int count) {
    return 'Références $count';
  }

  @override
  String get search => 'Rechercher';

  @override
  String get settingsNav => 'Réglages';

  @override
  String get publicIdentity => 'Identité publique';

  @override
  String get murmurTab => 'Murmure';

  @override
  String get notesTab => 'Remarques';

  @override
  String get discussionsTab => 'Planches';

  @override
  String get discussionsTabCompact => 'Planches';

  @override
  String get networkOnline => 'En ligne';

  @override
  String get networkOffline => 'Hors ligne';

  @override
  String get networkChecking => 'Vérification';

  @override
  String get workingNotes => 'Notes de travail';

  @override
  String get newest => 'Le plus récent';

  @override
  String get oldest => 'Le plus ancien';

  @override
  String get newNote => 'Nouvelle remarque';

  @override
  String get drawInAction => '↗ Attirer';

  @override
  String get noLooseMurmursYet => 'Pas encore de murmures lâches.';

  @override
  String get lineage => 'Lignée';

  @override
  String get noteCreated => 'Note créée';

  @override
  String get cancel => 'Annuler';

  @override
  String get draftLocal => 'Le tirage reste local';

  @override
  String get editing => 'Édition';

  @override
  String get noteTitleHint => 'Titre de la note';

  @override
  String get noteTitleRequired => 'Entrez un titre';

  @override
  String get noteBodyHint =>
      'Continuez à écrire, ou faites glisser un murmure d\'en bas...';

  @override
  String get noteBodyRequired => 'Saisir le corps de la note';

  @override
  String get noteSubjectLabel => 'cette note';

  @override
  String get drawIn => 'Dessiner';

  @override
  String get noMurmursToDraw => 'Aucun murmure à capter pour l’instant.';

  @override
  String get noNotesDescription =>
      'Les murmures restent d\'abord lâches localement ; quand ils commencent à se connecter, façonnez-les en une note.';

  @override
  String get noteUpdated => 'Remarque mise à jour';

  @override
  String get visibilityUpdated => 'Visibilité mise à jour';

  @override
  String get lineageDescription =>
      'Les notes façonnées à partir de murmures conservent ici leur lignée source.';

  @override
  String get notePrivateSummary => 'Personne d\'autre ne peut encore voir ça';

  @override
  String get noteNostrSummary => 'La publication envoie ceci aux relais Nostr';

  @override
  String get noteActivityPubSummary =>
      'La publication envoie ceci au relais ActivityPub';

  @override
  String get noteBothSummary =>
      'La publication envoie cela aux relais Nostr et au relais ActivityPub';

  @override
  String get noteLocalPublicSummary => 'État public, mais pas encore envoyé';

  @override
  String get createDiscussion => 'Créer une discussion';

  @override
  String get chooseHostedBoard => 'Choisir le tableau';

  @override
  String get hostedBoardMissing =>
      'Rejoignez ou créez d\'abord un forum Elix Relay';

  @override
  String get hostedBoardRequired => 'Choisissez une planche';

  @override
  String get titleLabel => 'Titre';

  @override
  String get discussionTitleHint => 'Entrez le titre de la discussion';

  @override
  String get titleRequired => 'Le titre est requis';

  @override
  String get contentLabel => 'Contenu';

  @override
  String get discussionContentHint => 'Entrez le contenu de la discussion';

  @override
  String get contentRequired => 'Le contenu est requis';

  @override
  String get create => 'Créer';

  @override
  String get uncategorized => 'Non classé';

  @override
  String get addForumHostFirst =>
      'Ajoutez d’abord un relais Elix dans les paramètres de synchronisation. Les forums de discussion sont créés par Elix Relays.';

  @override
  String syncedPublicCount(int count) {
    return 'Éléments publics $count synchronisés';
  }

  @override
  String get publicQueuedRelayFailed =>
      'Le contenu public a été mis en file d\'attente, mais la publication relais a échoué';

  @override
  String get noWritableNostrRelay =>
      'Aucun relais Nostr inscriptible n\'est configuré';

  @override
  String syncFailedMessage(String error) {
    return 'Échec de la synchronisation : $error';
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
  String get allActivity => 'Toutes les activités';

  @override
  String boardCount(int count) {
    return 'Cartes $count';
  }

  @override
  String get manageSubscriptions => 'Gérer les abonnements';

  @override
  String get newPost => 'Nouveau message';

  @override
  String get addBoardTooltip => 'Ajouter un tableau';

  @override
  String get newDiscussion => 'Nouveau fil de discussion';

  @override
  String get createNewDiscussion => 'Créer un fil de discussion sur le forum';

  @override
  String get boardsShort => 'Planches';

  @override
  String get manageBoardsShort => 'Gérer les tableaux';

  @override
  String get aiAssistant => 'Assistant IA';

  @override
  String get aiSummary => 'Résumé de l\'IA';

  @override
  String get noPostsYet => 'Aucune publication dans le fil pour l\'instant';

  @override
  String get subscribe => 'S\'abonner';

  @override
  String get discussionAreaTitle => 'Alimentation';

  @override
  String get feedSocialIdentitySubtitle =>
      'Les notes et les murmures sont des messages personnels. Les personnes qui vous suivent les voient dans leur flux ; les tableaux ajoutent des discussions partagées.';

  @override
  String get publicOpen => 'Personnes + tableaux';

  @override
  String get noContentYet => '(Pas encore de contenu)';

  @override
  String commentsCount(int count) {
    return 'Commentaires sur $count';
  }

  @override
  String get manageBoards => 'Gérer les tableaux';

  @override
  String get noBoardsYet => 'Pas encore de tableaux';

  @override
  String get deleteBoard => 'Supprimer le tableau';

  @override
  String deleteBoardConfirm(String title) {
    return 'Supprimer \"$title\" ? Cela ne peut pas être annulé.';
  }

  @override
  String get delete => 'Supprimer';

  @override
  String get close => 'Fermer';

  @override
  String get addBoard => 'Ajouter un tableau';
}
