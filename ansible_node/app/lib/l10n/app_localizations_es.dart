// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Spanish Castilian (`es`).
class AppLocalizationsEs extends AppLocalizations {
  AppLocalizationsEs([String locale = 'es']) : super(locale);

  @override
  String get appTitle => 'Elix';

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
  String get syncSubtitle => 'Ajustes de Elix Relay';

  @override
  String get configured => 'Ajustes';

  @override
  String get accessAudit => 'Acceso y auditoría';

  @override
  String get accessAuditSubtitle => 'Quién puede ver cada identidad';

  @override
  String get noSuspiciousAccess => '0 accesos sospechosos';

  @override
  String get language => 'Idioma';

  @override
  String get languageSubtitle => 'Elige el idioma de la interfaz';

  @override
  String get systemDefault => 'Idioma del sistema';

  @override
  String get daily => 'Diario';

  @override
  String get inbox => 'Bandeja de entrada';

  @override
  String get inboxSubtitle => 'Respuestas, nuevos miembros y sincronización';

  @override
  String get notifications => 'Notificaciones';

  @override
  String get notificationsSubtitle => 'Elige qué puede interrumpirte';

  @override
  String get light => 'Luz';

  @override
  String get readingPreferences => 'Preferencias de lectura';

  @override
  String get readingPreferencesSubtitle =>
      'Tamaño de texto, interlineado y tema';

  @override
  String get defaultValue => 'Predeterminado';

  @override
  String get boundaries => 'Límites';

  @override
  String get lock => 'Cerrar';

  @override
  String get lockSubtitle => 'Convierte la aplicación en una portada en blanco';

  @override
  String get off => 'Apagado';

  @override
  String get backupRestore => 'Copia de seguridad y restauración';

  @override
  String get backupRestoreSubtitle =>
      'Frase de acceso y migración a un dispositivo nuevo';

  @override
  String get notSet => 'Sin configurar';

  @override
  String get blockedList => 'Lista de bloqueados';

  @override
  String get blockedListSubtitle => 'No pueden verse mutuamente';

  @override
  String get about => 'Acerca de Elix';

  @override
  String get aboutSubtitle => 'Una señal a través de la distancia interestelar';

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
  String get feedAll => 'Alimentar';

  @override
  String get feedFollowing => 'Siguiente';

  @override
  String get feedBoards => 'tableros';

  @override
  String get searchBack => '← Prado';

  @override
  String get clear => 'Claro';

  @override
  String get searchHint => 'Buscar murmullos, notas, discusiones.';

  @override
  String get searchScopeAll => 'Todo';

  @override
  String get searchScopeMy => 'Mi';

  @override
  String get searchScopeCircle => 'Círculo';

  @override
  String get searchScopePublic => 'Público';

  @override
  String searchResultCount(int count) {
    return 'Se encontraron menciones de $count';
  }

  @override
  String get searchSortRelevant => '↓ Relevante';

  @override
  String notesSectionCount(int count) {
    return 'Notas · $count';
  }

  @override
  String murmursSectionCount(int count) {
    return 'Soplos · $count';
  }

  @override
  String threadsSectionCount(int count) {
    return 'Temas · $count';
  }

  @override
  String get noNotesYet => 'Aún no hay notas';

  @override
  String get noMatchingNotes => 'No hay notas coincidentes';

  @override
  String get noMurmursYet => 'Aún no hay murmullos';

  @override
  String get noMatchingMurmurs => 'No hay murmullos coincidentes';

  @override
  String get noThreadsYet => 'Aún no hay hilos';

  @override
  String get noMatchingThreads => 'No hay hilos coincidentes';

  @override
  String get murmurTitle => 'MURMULLO';

  @override
  String get local => 'Local';

  @override
  String get send => 'Enviar';

  @override
  String get murmurPrompt => '¿Qué cosa a medio formar?\nestá en tu mente?';

  @override
  String get murmurPrivateHint =>
      'Aquí cabe una frase, un instinto, una cuestión no resuelta. Nadie más lo verá.';

  @override
  String get murmurSyncHint =>
      'Aquí cabe una frase, un instinto, una cuestión no resuelta. Este estará marcado como sincronizable.';

  @override
  String get murmurInputHint => 'En lo que he estado pensando últimamente es';

  @override
  String get murmurPrivateVisibilityHint => 'solo para mi';

  @override
  String get murmurUnlistedVisibilityHint => 'Sincronizable pero no listado';

  @override
  String get murmurPublicVisibilityHint => 'Publicar públicamente';

  @override
  String get looseMurmurs => 'Perder';

  @override
  String get looseMurmursEmpty =>
      'Los murmullos enviados se quedan aquí primero.';

  @override
  String get sent => 'Enviado';

  @override
  String get deletedMurmur => 'Murmullo eliminado';

  @override
  String get unused => 'No usado';

  @override
  String referenceCount(int count) {
    return 'Referencias de $count';
  }

  @override
  String get search => 'Buscar';

  @override
  String get settingsNav => 'Ajustes';

  @override
  String get publicIdentity => 'Identidad pública';

  @override
  String get murmurTab => 'Murmullo';

  @override
  String get notesTab => 'Notas';

  @override
  String get discussionsTab => 'tableros';

  @override
  String get discussionsTabCompact => 'tableros';

  @override
  String get networkOnline => 'En línea';

  @override
  String get networkOffline => 'Sin conexión';

  @override
  String get networkChecking => 'Comprobando';

  @override
  String get workingNotes => 'Notas de trabajo';

  @override
  String get newest => 'El más nuevo';

  @override
  String get oldest => 'más antiguo';

  @override
  String get newNote => 'Nueva nota';

  @override
  String get drawInAction => '↗ Dibujar';

  @override
  String get noLooseMurmursYet => 'Aún no hay murmullos sueltos.';

  @override
  String get lineage => 'Linaje';

  @override
  String get noteCreated => 'Nota creada';

  @override
  String get cancel => 'Cancelar';

  @override
  String get draftLocal => 'El borrador se queda local';

  @override
  String get editing => 'Edición';

  @override
  String get noteTitleHint => 'Título de la nota';

  @override
  String get noteTitleRequired => 'Introduce un título';

  @override
  String get noteBodyHint =>
      'Sigue escribiendo o arrastra un murmullo desde abajo...';

  @override
  String get noteBodyRequired => 'Introducir el cuerpo de la nota';

  @override
  String get noteSubjectLabel => 'esta nota';

  @override
  String get drawIn => 'Atraer';

  @override
  String get noMurmursToDraw => 'Aún no hay murmullos que atraer.';

  @override
  String get noNotesDescription =>
      'Los murmullos se mantienen sueltos primero a nivel local; cuando empiecen a conectarse, dales forma de nota.';

  @override
  String get noteUpdated => 'Nota actualizada';

  @override
  String get visibilityUpdated => 'Visibilidad actualizada';

  @override
  String get lineageDescription =>
      'Las notas formadas a partir de murmullos mantienen aquí su linaje original.';

  @override
  String get notePrivateSummary => 'Nadie más puede ver esto todavía.';

  @override
  String get noteNostrSummary =>
      'La editorial envía esto a los retransmisores de Nostr.';

  @override
  String get noteActivityPubSummary =>
      'La publicación envía esto al relé ActivityPub';

  @override
  String get noteBothSummary =>
      'La publicación envía esto a los retransmisiones de Nostr y a la retransmisión de ActivityPub.';

  @override
  String get noteLocalPublicSummary => 'Estado público, pero aún no enviado.';

  @override
  String get createDiscussion => 'Crear discusión';

  @override
  String get chooseHostedBoard => 'Elige tablero';

  @override
  String get hostedBoardMissing =>
      'Únase o cree un tablero de Elix Relay primero';

  @override
  String get hostedBoardRequired => 'Elige una tabla';

  @override
  String get titleLabel => 'Título';

  @override
  String get discussionTitleHint => 'Ingrese el título de la discusión';

  @override
  String get titleRequired => 'Se requiere título';

  @override
  String get contentLabel => 'Contenido';

  @override
  String get discussionContentHint => 'Ingrese el contenido de la discusión';

  @override
  String get contentRequired => 'Se requiere contenido';

  @override
  String get create => 'Crear';

  @override
  String get uncategorized => 'Sin categoría';

  @override
  String get addForumHostFirst =>
      'Primero agregue un Elix Relay en la configuración de sincronización. Los foros de discusión son creados por Elix Relays.';

  @override
  String syncedPublicCount(int count) {
    return 'Elementos públicos $count sincronizados';
  }

  @override
  String get publicQueuedRelayFailed =>
      'El contenido público estaba en cola, pero la publicación de retransmisión falló';

  @override
  String get noWritableNostrRelay =>
      'No se ha configurado ningún relé Nostr grabable';

  @override
  String syncFailedMessage(String error) {
    return 'Error de sincronización: $error';
  }

  @override
  String get justNow => 'Ahora mismo';

  @override
  String minutesAgo(int count) {
    return 'Hace $count min';
  }

  @override
  String hoursAgo(int count) {
    return 'Hace $count h';
  }

  @override
  String daysAgo(int count) {
    return 'Hace $count d';
  }

  @override
  String get circleSection => 'Círculo';

  @override
  String get allActivity => 'Toda la actividad';

  @override
  String boardCount(int count) {
    return 'Tableros $count';
  }

  @override
  String get manageSubscriptions => 'Administrar suscripciones';

  @override
  String get newPost => 'Nueva publicación';

  @override
  String get addBoardTooltip => 'Agregar tablero';

  @override
  String get newDiscussion => 'Nuevo hilo del tablero';

  @override
  String get createNewDiscussion => 'Crear hilo de tablero';

  @override
  String get boardsShort => 'tableros';

  @override
  String get manageBoardsShort => 'Administrar tableros';

  @override
  String get aiAssistant => 'Asistente de IA';

  @override
  String get aiSummary => 'Resumen de IA';

  @override
  String get noPostsYet => 'Aún no hay publicaciones en el feed';

  @override
  String get subscribe => 'Suscribir';

  @override
  String get discussionAreaTitle => 'Alimentar';

  @override
  String get feedSocialIdentitySubtitle =>
      'Las notas y los murmullos son publicaciones personales. Las personas que te siguen los ven en su feed; Los foros agregan discusiones compartidas.';

  @override
  String get publicOpen => 'Personas + Tableros';

  @override
  String get noContentYet => '(Aún no hay contenido)';

  @override
  String commentsCount(int count) {
    return 'Comentarios de $count';
  }

  @override
  String get manageBoards => 'Administrar tableros';

  @override
  String get noBoardsYet => 'Aún no hay tableros';

  @override
  String get deleteBoard => 'Eliminar tablero';

  @override
  String deleteBoardConfirm(String title) {
    return '¿Eliminar \"$title\"? Esto no se puede deshacer.';
  }

  @override
  String get delete => 'Borrar';

  @override
  String get close => 'Cerca';

  @override
  String get addBoard => 'Agregar tablero';
}
