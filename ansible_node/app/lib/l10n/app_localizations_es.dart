// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Spanish Castilian (`es`).
class AppLocalizationsEs extends AppLocalizations {
  AppLocalizationsEs([String locale = 'es']) : super(locale);

  @override
  String get appTitle => 'Ansible Node';

  @override
  String get settingsTitle => 'AJUSTES';

  @override
  String get done => 'Listo';

  @override
  String get localIdentity => 'Identidad local';

  @override
  String get localDid => 'DID local';

  @override
  String get edit => 'Editar';

  @override
  String get identityAndDevice => 'Identidad y dispositivo';

  @override
  String get wallet => 'Cartera';

  @override
  String get walletSubtitleEmpty => 'Sin credenciales';

  @override
  String walletSubtitleCount(int count) {
    return '$count credenciales';
  }

  @override
  String get empty => 'Vacío';

  @override
  String get sync => 'Sincronizar';

  @override
  String get syncSubtitle => 'Ajustes de Forum Host / Nostr relay';

  @override
  String get configured => 'Ajustes';

  @override
  String get accessAudit => 'Acceso y auditoría';

  @override
  String get accessAuditSubtitle => 'Quién puede ver cada identidad';

  @override
  String get noSuspiciousAccess => '0 sospechosos';

  @override
  String get language => 'Idioma';

  @override
  String get languageSubtitle => 'Elige el idioma de la app';

  @override
  String get systemDefault => 'Predeterminado del sistema';

  @override
  String get daily => 'Diario';

  @override
  String get inbox => 'Bandeja de entrada';

  @override
  String get inboxSubtitle =>
      'Respuestas de círculos, nuevos miembros, sincronización';

  @override
  String get notifications => 'Notificaciones';

  @override
  String get notificationsSubtitle => 'Decide qué puede interrumpirte';

  @override
  String get light => 'Ligero';

  @override
  String get readingPreferences => 'Preferencias de lectura';

  @override
  String get readingPreferencesSubtitle =>
      'Tamaño de texto, interlineado, tema';

  @override
  String get defaultValue => 'Predeterminado';

  @override
  String get boundaries => 'Límites';

  @override
  String get lock => 'Bloquear';

  @override
  String get lockSubtitle => 'Convertir la app en una portada en blanco';

  @override
  String get off => 'Desactivado';

  @override
  String get backupRestore => 'Copia y restauración';

  @override
  String get backupRestoreSubtitle =>
      'Frase secreta, migración a nuevo dispositivo';

  @override
  String get notSet => 'No configurado';

  @override
  String get blockedList => 'Lista de bloqueados';

  @override
  String get blockedListSubtitle => 'No los ves y ellos no te ven';

  @override
  String get about => 'Acerca de Ansible';

  @override
  String get aboutSubtitle => 'Una señal que cruza distancias estelares';

  @override
  String get manual => 'Manual';

  @override
  String get signOutDevice => 'Cerrar sesión en este dispositivo';

  @override
  String get signOutSubtitle =>
      'Conservar datos; se requerirá passkey la próxima vez';

  @override
  String get languagePickerTitle => 'Idioma';

  @override
  String get languageSystemDescription => 'Usar el idioma de este dispositivo';

  @override
  String get feedAll => 'Todo';

  @override
  String get feedFollowing => 'Siguiendo';

  @override
  String get feedBoards => 'Tableros';

  @override
  String get searchBack => '← Prado';

  @override
  String get clear => 'Borrar';

  @override
  String get searchHint => 'Buscar murmurs, notas y discusiones';

  @override
  String get searchScopeAll => 'Todo';

  @override
  String get searchScopeMy => 'Mío';

  @override
  String get searchScopeCircle => 'Círculo';

  @override
  String get searchScopePublic => 'Público';

  @override
  String searchResultCount(int count) {
    return '$count menciones encontradas';
  }

  @override
  String get searchSortRelevant => '↓ Relevante';

  @override
  String notesSectionCount(int count) {
    return 'Notas · $count';
  }

  @override
  String murmursSectionCount(int count) {
    return 'Murmurs · $count';
  }

  @override
  String threadsSectionCount(int count) {
    return 'Hilos · $count';
  }

  @override
  String get noNotesYet => 'Aún no hay notas';

  @override
  String get noMatchingNotes => 'No hay notas coincidentes';

  @override
  String get noMurmursYet => 'Aún no hay murmurs';

  @override
  String get noMatchingMurmurs => 'No hay murmurs coincidentes';

  @override
  String get noThreadsYet => 'Aún no hay hilos';

  @override
  String get noMatchingThreads => 'No hay hilos coincidentes';

  @override
  String get murmurTitle => 'MURMUR';

  @override
  String get local => 'Local';

  @override
  String get send => 'Enviar';

  @override
  String get murmurPrompt => '¿Qué idea a medio formar\ntienes en mente?';

  @override
  String get murmurPrivateHint =>
      'Una frase, una intuición o una pregunta sin resolver caben aquí. Nadie más lo verá.';

  @override
  String get murmurSyncHint =>
      'Una frase, una intuición o una pregunta sin resolver caben aquí. Se marcará como sincronizable.';

  @override
  String get murmurInputHint => 'Lo que he estado pensando últimamente es';

  @override
  String get murmurPrivateVisibilityHint => 'Solo para mí';

  @override
  String get murmurUnlistedVisibilityHint => 'Sin listar pero sincronizable';

  @override
  String get murmurPublicVisibilityHint => 'Publicar públicamente';

  @override
  String get looseMurmurs => 'Sueltos';

  @override
  String get looseMurmursEmpty =>
      'Los murmurs enviados se quedan aquí primero.';

  @override
  String get sent => 'Enviado';

  @override
  String get deletedMurmur => 'Murmur eliminado';

  @override
  String get unused => 'Sin usar';

  @override
  String referenceCount(int count) {
    return '$count referencias';
  }

  @override
  String get search => 'Buscar';

  @override
  String get settingsNav => 'Ajustes';

  @override
  String get publicIdentity => 'Identidad pública';

  @override
  String get murmurTab => 'Murmur';

  @override
  String get notesTab => 'Notas';

  @override
  String get discussionsTab => 'Discusiones';

  @override
  String get discussionsTabCompact => 'Foro';

  @override
  String get networkOnline => 'En línea';

  @override
  String get networkOffline => 'Sin conexión';

  @override
  String get networkChecking => 'Comprobando';

  @override
  String get workingNotes => 'Notas de trabajo';

  @override
  String get newest => 'Más recientes';

  @override
  String get oldest => 'Más antiguas';

  @override
  String get newNote => 'Nueva nota';

  @override
  String get drawInAction => '↗ Incorporar';

  @override
  String get noLooseMurmursYet => 'Aún no hay murmurs sueltos.';

  @override
  String get lineage => 'Linaje';

  @override
  String get noteCreated => 'Nota creada';

  @override
  String get cancel => 'Cancelar';

  @override
  String get draftLocal => 'El borrador queda local';

  @override
  String get editing => 'Editando';

  @override
  String get noteTitleHint => 'Título de la nota';

  @override
  String get noteTitleRequired => 'Ingresa un título';

  @override
  String get noteBodyHint =>
      'Sigue escribiendo o arrastra un murmur desde abajo...';

  @override
  String get noteBodyRequired => 'Ingresa el contenido de la nota';

  @override
  String get noteSubjectLabel => 'esta nota';

  @override
  String get drawIn => 'Incorporar';

  @override
  String get noMurmursToDraw => 'Aún no hay murmurs para incorporar.';

  @override
  String get noNotesDescription =>
      'Los murmurs quedan sueltos localmente primero; cuando empiecen a conectarse, conviértelos en una nota.';

  @override
  String get noteUpdated => 'Nota actualizada';

  @override
  String get visibilityUpdated => 'Visibilidad actualizada';

  @override
  String get lineageDescription =>
      'Las notas formadas desde murmurs conservan aquí sus fuentes.';

  @override
  String get notePrivateSummary => 'Aún nadie más puede verlo';

  @override
  String get noteNostrSummary => 'Al publicar se enviará a Nostr relays';

  @override
  String get noteActivityPubSummary =>
      'Al publicar se enviará al relay ActivityPub';

  @override
  String get noteBothSummary =>
      'Al publicar se enviará a Nostr relays y al relay ActivityPub';

  @override
  String get noteLocalPublicSummary => 'Estado público, pero aún no enviado';

  @override
  String get createDiscussion => 'Crear discusión';

  @override
  String get chooseHostedBoard => 'Elegir hosted board';

  @override
  String get hostedBoardMissing =>
      'Primero únete o crea un hosted board de Forum Host';

  @override
  String get hostedBoardRequired => 'Elige un hosted board';

  @override
  String get titleLabel => 'Título';

  @override
  String get discussionTitleHint => 'Ingresa el título de la discusión';

  @override
  String get titleRequired => 'El título es obligatorio';

  @override
  String get contentLabel => 'Contenido';

  @override
  String get discussionContentHint => 'Ingresa el contenido de la discusión';

  @override
  String get contentRequired => 'El contenido es obligatorio';

  @override
  String get create => 'Crear';

  @override
  String get uncategorized => 'Sin categoría';

  @override
  String get addForumHostFirst =>
      'Primero agrega un Forum Host en ajustes de sincronización. Los tableros de discusión los crean los Forum Hosts.';

  @override
  String syncedPublicCount(int count) {
    return '$count elementos públicos sincronizados';
  }

  @override
  String get publicQueuedRelayFailed =>
      'El contenido público quedó en cola, pero falló la publicación al relay';

  @override
  String get noWritableNostrRelay =>
      'No hay Nostr relay escribible configurado';

  @override
  String syncFailedMessage(String error) {
    return 'Falló la sincronización: $error';
  }

  @override
  String get justNow => 'Ahora mismo';

  @override
  String minutesAgo(int count) {
    return 'Hace $count minutos';
  }

  @override
  String hoursAgo(int count) {
    return 'Hace $count horas';
  }

  @override
  String daysAgo(int count) {
    return 'Hace $count días';
  }

  @override
  String get circleSection => 'Círculo';

  @override
  String get allActivity => 'Toda la actividad';

  @override
  String boardCount(int count) {
    return '$count tableros';
  }

  @override
  String get manageSubscriptions => 'Gestionar suscripciones';

  @override
  String get newPost => 'Nueva publicación';

  @override
  String get addBoardTooltip => 'Agregar tablero';

  @override
  String get newDiscussion => 'Nueva discusión';

  @override
  String get createNewDiscussion => 'Crear nueva discusión';

  @override
  String get boardsShort => 'Tableros';

  @override
  String get manageBoardsShort => 'Gestionar tableros';

  @override
  String get aiAssistant => 'Asistente AI';

  @override
  String get aiSummary => 'Resumen AI';

  @override
  String get noPostsYet => 'Aún no hay publicaciones';

  @override
  String get subscribe => 'Suscribirse';

  @override
  String get discussionAreaTitle => 'Área de discusión';

  @override
  String get publicOpen => 'Público · Open';

  @override
  String get noContentYet => '(Aún sin contenido)';

  @override
  String commentsCount(int count) {
    return '$count comentarios';
  }

  @override
  String get manageBoards => 'Gestionar tableros';

  @override
  String get noBoardsYet => 'Aún no hay tableros';

  @override
  String get deleteBoard => 'Eliminar tablero';

  @override
  String deleteBoardConfirm(String title) {
    return '¿Eliminar \"$title\"? Esta acción no se puede deshacer.';
  }

  @override
  String get delete => 'Eliminar';

  @override
  String get close => 'Cerrar';

  @override
  String get addBoard => 'Agregar tablero';
}
