// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Portuguese (`pt`).
class AppLocalizationsPt extends AppLocalizations {
  AppLocalizationsPt([String locale = 'pt']) : super(locale);

  @override
  String get appTitle => 'Elix';

  @override
  String get settingsTitle => 'DEFINIÇÕES';

  @override
  String get done => 'Concluído';

  @override
  String get localIdentity => 'Identidade local';

  @override
  String get localDid => 'DID local';

  @override
  String get edit => 'Editar';

  @override
  String get identityAndDevice => 'Identidade e dispositivo';

  @override
  String get wallet => 'Carteira';

  @override
  String get walletSubtitleEmpty => 'Sem credenciais';

  @override
  String walletSubtitleCount(int count) {
    return '$count credenciais';
  }

  @override
  String get empty => 'Vazio';

  @override
  String get sync => 'Sincronizar';

  @override
  String get syncSubtitle => 'Definições de Elix Relay';

  @override
  String get configured => 'Definições';

  @override
  String get accessAudit => 'Acesso e auditoria';

  @override
  String get accessAuditSubtitle => 'Quem pode ver qual identidade';

  @override
  String get noSuspiciousAccess => '0 suspeitos';

  @override
  String get language => 'Idioma';

  @override
  String get languageSubtitle => 'Escolha o idioma da app';

  @override
  String get systemDefault => 'Padrão do sistema';

  @override
  String get daily => 'Diário';

  @override
  String get inbox => 'Caixa de entrada';

  @override
  String get inboxSubtitle =>
      'Respostas de círculos, novos membros, sincronização';

  @override
  String get notifications => 'Notificações';

  @override
  String get notificationsSubtitle => 'Decida o que pode interromper você';

  @override
  String get light => 'Leve';

  @override
  String get readingPreferences => 'Preferências de leitura';

  @override
  String get readingPreferencesSubtitle =>
      'Tamanho do texto, altura da linha, tema';

  @override
  String get defaultValue => 'Padrão';

  @override
  String get boundaries => 'Limites';

  @override
  String get lock => 'Bloquear';

  @override
  String get lockSubtitle => 'Transformar a app numa capa em branco';

  @override
  String get off => 'Desligado';

  @override
  String get backupRestore => 'Backup e restauração';

  @override
  String get backupRestoreSubtitle =>
      'Frase-passe, migração para novo dispositivo';

  @override
  String get notSet => 'Não definido';

  @override
  String get blockedList => 'Lista de bloqueados';

  @override
  String get blockedListSubtitle => 'Você não os vê, e eles não veem você';

  @override
  String get about => 'Sobre o Elix';

  @override
  String get aboutSubtitle => 'Um sinal que cruza distâncias estelares';

  @override
  String get manual => 'Manual';

  @override
  String get signOutDevice => 'Sair deste dispositivo';

  @override
  String get signOutSubtitle => 'Manter dados; passkey exigida na próxima vez';

  @override
  String get languagePickerTitle => 'Idioma';

  @override
  String get languageSystemDescription => 'Usar o idioma deste dispositivo';

  @override
  String get feedAll => 'Tudo';

  @override
  String get feedFollowing => 'Seguindo';

  @override
  String get feedBoards => 'Quadros';

  @override
  String get searchBack => '← Prado';

  @override
  String get clear => 'Limpar';

  @override
  String get searchHint => 'Buscar murmurs, notas e discussões';

  @override
  String get searchScopeAll => 'Tudo';

  @override
  String get searchScopeMy => 'Meu';

  @override
  String get searchScopeCircle => 'Círculo';

  @override
  String get searchScopePublic => 'Público';

  @override
  String searchResultCount(int count) {
    return '$count menções encontradas';
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
    return 'Tópicos · $count';
  }

  @override
  String get noNotesYet => 'Ainda não há notas';

  @override
  String get noMatchingNotes => 'Nenhuma nota correspondente';

  @override
  String get noMurmursYet => 'Ainda não há murmurs';

  @override
  String get noMatchingMurmurs => 'Nenhum murmur correspondente';

  @override
  String get noThreadsYet => 'Ainda não há tópicos';

  @override
  String get noMatchingThreads => 'Nenhum tópico correspondente';

  @override
  String get murmurTitle => 'MURMUR';

  @override
  String get local => 'Local';

  @override
  String get send => 'Enviar';

  @override
  String get murmurPrompt => 'Que coisa meio formada\nestá na sua cabeça?';

  @override
  String get murmurPrivateHint =>
      'Uma frase, uma intuição ou uma pergunta em aberto cabem aqui. Ninguém mais verá.';

  @override
  String get murmurSyncHint =>
      'Uma frase, uma intuição ou uma pergunta em aberto cabem aqui. Isto será marcado como sincronizável.';

  @override
  String get murmurInputHint => 'O que tenho pensado ultimamente é';

  @override
  String get murmurPrivateVisibilityHint => 'Só para mim';

  @override
  String get murmurUnlistedVisibilityHint => 'Sincronizável, mas não listado';

  @override
  String get murmurPublicVisibilityHint => 'Publicar publicamente';

  @override
  String get looseMurmurs => 'Soltos';

  @override
  String get looseMurmursEmpty => 'Murmurs enviados ficam aqui primeiro.';

  @override
  String get sent => 'Enviado';

  @override
  String get deletedMurmur => 'Murmur excluído';

  @override
  String get unused => 'Sem uso';

  @override
  String referenceCount(int count) {
    return '$count referências';
  }

  @override
  String get search => 'Buscar';

  @override
  String get settingsNav => 'Configurações';

  @override
  String get publicIdentity => 'Identidade pública';

  @override
  String get murmurTab => 'Murmur';

  @override
  String get notesTab => 'Notas';

  @override
  String get discussionsTab => 'Discussões';

  @override
  String get discussionsTabCompact => 'Fórum';

  @override
  String get networkOnline => 'Online';

  @override
  String get networkOffline => 'Offline';

  @override
  String get networkChecking => 'Verificando';

  @override
  String get workingNotes => 'Notas de trabalho';

  @override
  String get newest => 'Mais recentes';

  @override
  String get oldest => 'Mais antigas';

  @override
  String get newNote => 'Nova nota';

  @override
  String get drawInAction => '↗ Incorporar';

  @override
  String get noLooseMurmursYet => 'Ainda não há murmurs soltos.';

  @override
  String get lineage => 'Linhagem';

  @override
  String get noteCreated => 'Nota criada';

  @override
  String get cancel => 'Cancelar';

  @override
  String get draftLocal => 'Rascunho fica local';

  @override
  String get editing => 'Editando';

  @override
  String get noteTitleHint => 'Título da nota';

  @override
  String get noteTitleRequired => 'Insira um título';

  @override
  String get noteBodyHint =>
      'Continue escrevendo ou arraste um murmur de baixo...';

  @override
  String get noteBodyRequired => 'Insira o conteúdo da nota';

  @override
  String get noteSubjectLabel => 'esta nota';

  @override
  String get drawIn => 'Incorporar';

  @override
  String get noMurmursToDraw => 'Ainda não há murmurs para incorporar.';

  @override
  String get noNotesDescription =>
      'Murmurs ficam soltos localmente primeiro; quando começarem a se conectar, transforme-os em uma nota.';

  @override
  String get noteUpdated => 'Nota atualizada';

  @override
  String get visibilityUpdated => 'Visibilidade atualizada';

  @override
  String get lineageDescription =>
      'Notas formadas a partir de murmurs mantêm suas fontes aqui.';

  @override
  String get notePrivateSummary => 'Ninguém mais pode ver isto ainda';

  @override
  String get noteNostrSummary => 'Ao publicar, será enviado aos Nostr relays';

  @override
  String get noteActivityPubSummary =>
      'Ao publicar, será enviado ao relay ActivityPub';

  @override
  String get noteBothSummary =>
      'Ao publicar, será enviado aos Nostr relays e ao relay ActivityPub';

  @override
  String get noteLocalPublicSummary => 'Estado público, mas ainda não enviado';

  @override
  String get createDiscussion => 'Criar discussão';

  @override
  String get chooseHostedBoard => 'Escolher hosted board';

  @override
  String get hostedBoardMissing =>
      'Entre ou crie primeiro um hosted board do Elix Relay';

  @override
  String get hostedBoardRequired => 'Escolha um hosted board';

  @override
  String get titleLabel => 'Título';

  @override
  String get discussionTitleHint => 'Insira o título da discussão';

  @override
  String get titleRequired => 'Título é obrigatório';

  @override
  String get contentLabel => 'Conteúdo';

  @override
  String get discussionContentHint => 'Insira o conteúdo da discussão';

  @override
  String get contentRequired => 'Conteúdo é obrigatório';

  @override
  String get create => 'Criar';

  @override
  String get uncategorized => 'Sem categoria';

  @override
  String get addForumHostFirst =>
      'Adicione primeiro um Elix Relay nas configurações de sincronização. Quadros de discussão são criados por Elix Relays.';

  @override
  String syncedPublicCount(int count) {
    return '$count itens públicos sincronizados';
  }

  @override
  String get publicQueuedRelayFailed =>
      'O conteúdo público foi enfileirado, mas a publicação no relay falhou';

  @override
  String get noWritableNostrRelay => 'Nenhum Nostr relay gravável configurado';

  @override
  String syncFailedMessage(String error) {
    return 'Falha na sincronização: $error';
  }

  @override
  String get justNow => 'Agora mesmo';

  @override
  String minutesAgo(int count) {
    return 'Há $count minutos';
  }

  @override
  String hoursAgo(int count) {
    return 'Há $count horas';
  }

  @override
  String daysAgo(int count) {
    return 'Há $count dias';
  }

  @override
  String get circleSection => 'Círculo';

  @override
  String get allActivity => 'Toda atividade';

  @override
  String boardCount(int count) {
    return '$count quadros';
  }

  @override
  String get manageSubscriptions => 'Gerenciar assinaturas';

  @override
  String get newPost => 'Nova publicação';

  @override
  String get addBoardTooltip => 'Adicionar quadro';

  @override
  String get newDiscussion => 'Nova discussão';

  @override
  String get createNewDiscussion => 'Criar nova discussão';

  @override
  String get boardsShort => 'Quadros';

  @override
  String get manageBoardsShort => 'Gerenciar quadros';

  @override
  String get aiAssistant => 'Assistente AI';

  @override
  String get aiSummary => 'Resumo AI';

  @override
  String get noPostsYet => 'Ainda não há publicações';

  @override
  String get subscribe => 'Assinar';

  @override
  String get discussionAreaTitle => 'Área de discussão';

  @override
  String get feedSocialIdentitySubtitle =>
      'Notes e Murmurs são publicações pessoais. Quem segue você as vê no feed; boards adicionam discussões compartilhadas.';

  @override
  String get publicOpen => 'Público · Open';

  @override
  String get noContentYet => '(Ainda sem conteúdo)';

  @override
  String commentsCount(int count) {
    return '$count comentários';
  }

  @override
  String get manageBoards => 'Gerenciar quadros';

  @override
  String get noBoardsYet => 'Ainda não há quadros';

  @override
  String get deleteBoard => 'Excluir quadro';

  @override
  String deleteBoardConfirm(String title) {
    return 'Excluir \"$title\"? Esta ação não pode ser desfeita.';
  }

  @override
  String get delete => 'Excluir';

  @override
  String get close => 'Fechar';

  @override
  String get addBoard => 'Adicionar quadro';
}
