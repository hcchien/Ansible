// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Korean (`ko`).
class AppLocalizationsKo extends AppLocalizations {
  AppLocalizationsKo([String locale = 'ko']) : super(locale);

  @override
  String get appTitle => 'Elix';

  @override
  String get settingsTitle => '설정';

  @override
  String get done => '완료';

  @override
  String get localIdentity => '로컬 신원';

  @override
  String get localDid => '로컬 DID';

  @override
  String get edit => '편집';

  @override
  String get identityAndDevice => '신원 및 기기';

  @override
  String get wallet => '지갑';

  @override
  String get walletSubtitleEmpty => '자격 증명 없음';

  @override
  String walletSubtitleCount(int count) {
    return '자격 증명 $count개';
  }

  @override
  String get empty => '비어 있음';

  @override
  String get sync => '동기화';

  @override
  String get syncSubtitle => 'Elix Relay 설정';

  @override
  String get configured => '설정';

  @override
  String get accessAudit => '접근 및 감사';

  @override
  String get accessAuditSubtitle => '누가 어떤 신원을 확인했는지';

  @override
  String get noSuspiciousAccess => '의심스러운 접근 0건';

  @override
  String get language => '언어';

  @override
  String get languageSubtitle => '앱 인터페이스 언어 선택';

  @override
  String get systemDefault => '시스템 기본값';

  @override
  String get daily => '일상';

  @override
  String get inbox => '받은 편지함';

  @override
  String get inboxSubtitle => '답글, 새 멤버, 동기화';

  @override
  String get notifications => '알림';

  @override
  String get notificationsSubtitle => '알림을 받을 항목 선택';

  @override
  String get light => 'Light';

  @override
  String get readingPreferences => '읽기 환경설정';

  @override
  String get readingPreferencesSubtitle => '글자 크기, 줄 간격, 테마';

  @override
  String get defaultValue => '기본값';

  @override
  String get boundaries => '경계';

  @override
  String get lock => 'Lock';

  @override
  String get lockSubtitle => 'Turn the app into a blank cover';

  @override
  String get off => 'Off';

  @override
  String get backupRestore => '백업 및 복원';

  @override
  String get backupRestoreSubtitle => '암호 문구, 새 기기로 이전';

  @override
  String get notSet => '설정 안 됨';

  @override
  String get blockedList => '차단 목록';

  @override
  String get blockedListSubtitle => '서로를 볼 수 없습니다';

  @override
  String get about => 'Elix 정보';

  @override
  String get aboutSubtitle => '별 사이의 거리를 건너는 신호';

  @override
  String get manual => '사용 설명서';

  @override
  String get signOutDevice => '이 기기에서 로그아웃';

  @override
  String get signOutSubtitle => '데이터 유지; 다음에 패스키 필요';

  @override
  String get languagePickerTitle => '언어';

  @override
  String get languageSystemDescription => '이 기기의 언어 설정 사용';

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
  String get search => '검색';

  @override
  String get settingsNav => '설정';

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
  String get networkOnline => '온라인';

  @override
  String get networkOffline => '오프라인';

  @override
  String get networkChecking => '확인 중';

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
  String get cancel => '취소';

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
    return '동기화 실패: $error';
  }

  @override
  String get justNow => '방금';

  @override
  String minutesAgo(int count) {
    return '$count분 전';
  }

  @override
  String hoursAgo(int count) {
    return '$count시간 전';
  }

  @override
  String daysAgo(int count) {
    return '$count일 전';
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
