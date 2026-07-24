// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Korean (`ko`).
class AppLocalizationsKo extends AppLocalizations {
  AppLocalizationsKo([String locale = 'ko']) : super(locale);

  @override
  String get appTitle => '엘릭스';

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
  String get light => '빛';

  @override
  String get readingPreferences => '읽기 환경설정';

  @override
  String get readingPreferencesSubtitle => '글자 크기, 줄 간격, 테마';

  @override
  String get defaultValue => '기본값';

  @override
  String get boundaries => '경계';

  @override
  String get lock => '잠그다';

  @override
  String get lockSubtitle => '앱을 빈 표지로 바꿔보세요';

  @override
  String get off => '끄다';

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
  String get feedAll => '밥을 먹이다';

  @override
  String get feedFollowing => '수행원';

  @override
  String get feedBoards => '무대';

  @override
  String get searchBack => '← 초원';

  @override
  String get clear => '분명한';

  @override
  String get searchHint => '중얼거림, 메모, 토론 검색';

  @override
  String get searchScopeAll => '모두';

  @override
  String get searchScopeMy => '나의';

  @override
  String get searchScopeCircle => '원';

  @override
  String get searchScopePublic => '공공의';

  @override
  String searchResultCount(int count) {
    return '$count이 언급된 것을 발견했습니다.';
  }

  @override
  String get searchSortRelevant => '↓ 관련';

  @override
  String notesSectionCount(int count) {
    return '참고 사항 · $count';
  }

  @override
  String murmursSectionCount(int count) {
    return '중얼거림 · $count';
  }

  @override
  String threadsSectionCount(int count) {
    return '스레드 · $count';
  }

  @override
  String get noNotesYet => '아직 메모가 없습니다.';

  @override
  String get noMatchingNotes => '일치하는 메모 없음';

  @override
  String get noMurmursYet => '아직 잡음은 없습니다';

  @override
  String get noMatchingMurmurs => '어울리는 중얼거림 없음';

  @override
  String get noThreadsYet => '아직 스레드가 없습니다.';

  @override
  String get noMatchingThreads => '일치하는 스레드 없음';

  @override
  String get murmurTitle => '어렴풋한 말소리';

  @override
  String get local => '현지의';

  @override
  String get send => '보내다';

  @override
  String get murmurPrompt => '무슨 반쯤 형성된 것\n당신의 마음에 있습니까?';

  @override
  String get murmurPrivateHint =>
      '문장, 본능, 해결되지 않은 질문 모두 여기에 적합합니다. 다른 사람은 그것을 볼 수 없습니다.';

  @override
  String get murmurSyncHint =>
      '문장, 본능, 해결되지 않은 질문 모두 여기에 적합합니다. 이것은 동기화 가능으로 표시됩니다.';

  @override
  String get murmurInputHint => '제가 최근에 생각하고 있는 것은';

  @override
  String get murmurPrivateVisibilityHint => '나에게만';

  @override
  String get murmurUnlistedVisibilityHint => '동기화 가능하지만 목록에 없음';

  @override
  String get murmurPublicVisibilityHint => '공개적으로 게시';

  @override
  String get looseMurmurs => '헐렁한';

  @override
  String get looseMurmursEmpty => '보낸 중얼거림은 먼저 여기에 머물러라.';

  @override
  String get sent => '전송된';

  @override
  String get deletedMurmur => '중얼거림이 삭제되었습니다.';

  @override
  String get unused => '미사용';

  @override
  String referenceCount(int count) {
    return '$count 참조';
  }

  @override
  String get search => '검색';

  @override
  String get settingsNav => '설정';

  @override
  String get publicIdentity => '공공의 정체성';

  @override
  String get murmurTab => '어렴풋한 말소리';

  @override
  String get notesTab => '메모';

  @override
  String get discussionsTab => '무대';

  @override
  String get discussionsTabCompact => '무대';

  @override
  String get networkOnline => '온라인';

  @override
  String get networkOffline => '오프라인';

  @override
  String get networkChecking => '확인 중';

  @override
  String get workingNotes => '작업 노트';

  @override
  String get newest => '최신';

  @override
  String get oldest => '가장 오래된';

  @override
  String get newNote => '새 메모';

  @override
  String get drawInAction => '↗ 그리기';

  @override
  String get noLooseMurmursYet => '아직은 느슨한 중얼거림이 없습니다.';

  @override
  String get lineage => '혈통';

  @override
  String get noteCreated => '메모가 생성되었습니다.';

  @override
  String get cancel => '취소';

  @override
  String get draftLocal => '초안은 로컬에 유지됩니다.';

  @override
  String get editing => '편집';

  @override
  String get noteTitleHint => '메모 제목';

  @override
  String get noteTitleRequired => '제목을 입력하세요';

  @override
  String get noteBodyHint => '계속 쓰거나 아래에서 중얼거리는 소리를 끌어오세요...';

  @override
  String get noteBodyRequired => '메모 본문 입력';

  @override
  String get noteSubjectLabel => '이 메모';

  @override
  String get drawIn => '끌어들이다';

  @override
  String get noMurmursToDraw => '아직 끌어낼 수 있는 중얼거림이 없습니다.';

  @override
  String get noNotesDescription =>
      '중얼거림은 먼저 국부적으로 느슨해집니다. 연결되기 시작하면 메모 모양으로 만듭니다.';

  @override
  String get noteUpdated => '메모가 업데이트되었습니다.';

  @override
  String get visibilityUpdated => '공개 상태가 업데이트되었습니다.';

  @override
  String get lineageDescription => '중얼거림으로 형성된 음표는 여기에 소스 계보를 유지합니다.';

  @override
  String get notePrivateSummary => '아직은 다른 사람이 볼 수 없습니다.';

  @override
  String get noteNostrSummary => '게시는 이를 Nostr 릴레이로 보냅니다.';

  @override
  String get noteActivityPubSummary => '게시하면 이를 ActivityPub 릴레이로 보냅니다.';

  @override
  String get noteBothSummary => '게시하면 이를 Nostr 릴레이 및 ActivityPub 릴레이로 보냅니다.';

  @override
  String get noteLocalPublicSummary => '공개 상태이지만 아직 전송되지 않았습니다.';

  @override
  String get createDiscussion => '토론 만들기';

  @override
  String get chooseHostedBoard => '보드 선택';

  @override
  String get hostedBoardMissing => '먼저 Elix Relay 보드에 가입하거나 생성하세요.';

  @override
  String get hostedBoardRequired => '보드를 선택하세요';

  @override
  String get titleLabel => '제목';

  @override
  String get discussionTitleHint => '토론 제목 입력';

  @override
  String get titleRequired => '제목은 필수 항목입니다.';

  @override
  String get contentLabel => '콘텐츠';

  @override
  String get discussionContentHint => '토론 내용 입력';

  @override
  String get contentRequired => '콘텐츠가 필요합니다';

  @override
  String get create => '만들다';

  @override
  String get uncategorized => '분류되지 않음';

  @override
  String get addForumHostFirst =>
      '먼저 동기화 설정에서 Elix Relay를 추가하세요. 토론 게시판은 Elix Relays에 의해 만들어졌습니다.';

  @override
  String syncedPublicCount(int count) {
    return '동기화된 $count 공개 항목';
  }

  @override
  String get publicQueuedRelayFailed => '공개 콘텐츠가 대기열에 추가되었지만 릴레이 게시에 실패했습니다.';

  @override
  String get noWritableNostrRelay => '쓰기 가능한 Nostr 릴레이가 구성되지 않았습니다.';

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
  String get circleSection => '원';

  @override
  String get allActivity => '모든 활동';

  @override
  String boardCount(int count) {
    return '$count 보드';
  }

  @override
  String get manageSubscriptions => '구독 관리';

  @override
  String get newPost => '새 게시물';

  @override
  String get addBoardTooltip => '보드 추가';

  @override
  String get newDiscussion => '새로운 보드 스레드';

  @override
  String get createNewDiscussion => '보드 스레드 생성';

  @override
  String get boardsShort => '무대';

  @override
  String get manageBoardsShort => '보드 관리';

  @override
  String get aiAssistant => 'AI 어시스턴트';

  @override
  String get aiSummary => 'AI 요약';

  @override
  String get noPostsYet => '아직 피드 게시물이 없습니다.';

  @override
  String get subscribe => '구독하다';

  @override
  String get discussionAreaTitle => '밥을 먹이다';

  @override
  String get feedSocialIdentitySubtitle =>
      '메모와 중얼거림은 개인 게시물입니다. 당신을 팔로우하는 사람들은 자신의 피드에서 해당 내용을 볼 수 있습니다. 보드에는 공유 토론이 추가됩니다.';

  @override
  String get publicOpen => '사람 + 보드';

  @override
  String get noContentYet => '(아직 내용이 없습니다)';

  @override
  String commentsCount(int count) {
    return '$count 댓글';
  }

  @override
  String get manageBoards => '보드 관리';

  @override
  String get noBoardsYet => '아직 보드가 없습니다.';

  @override
  String get deleteBoard => '보드 삭제';

  @override
  String deleteBoardConfirm(String title) {
    return '\'$title\'을 삭제하시겠습니까? 이 작업은 취소할 수 없습니다.';
  }

  @override
  String get delete => '삭제';

  @override
  String get close => '닫다';

  @override
  String get addBoard => '보드 추가';
}
