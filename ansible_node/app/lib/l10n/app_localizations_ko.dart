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
  String get walletSubtitleEmpty => '자격 증명이 없습니다';

  @override
  String walletSubtitleCount(int count) {
    return '자격 증명 $count개';
  }

  @override
  String get empty => '비어 있음';

  @override
  String get sync => '동기화';

  @override
  String get syncSubtitle => 'Forum Host / Nostr relay 설정';

  @override
  String get configured => '설정';

  @override
  String get accessAudit => '접근 및 감사';

  @override
  String get accessAuditSubtitle => '누가 어떤 신원을 볼 수 있는지';

  @override
  String get noSuspiciousAccess => '의심 항목 0개';

  @override
  String get language => '언어';

  @override
  String get languageSubtitle => '앱 인터페이스 언어 선택';

  @override
  String get systemDefault => '시스템 기본값';

  @override
  String get daily => '일상';

  @override
  String get inbox => '받은함';

  @override
  String get inboxSubtitle => '서클 답글, 새 멤버, 동기화';

  @override
  String get notifications => '알림';

  @override
  String get notificationsSubtitle => '무엇이 방해할 수 있는지 결정';

  @override
  String get light => '가볍게';

  @override
  String get readingPreferences => '읽기 설정';

  @override
  String get readingPreferencesSubtitle => '글자 크기, 줄 간격, 테마';

  @override
  String get defaultValue => '기본값';

  @override
  String get boundaries => '경계';

  @override
  String get lock => '잠금';

  @override
  String get lockSubtitle => '앱을 빈 표지로 전환';

  @override
  String get off => '꺼짐';

  @override
  String get backupRestore => '백업 및 복원';

  @override
  String get backupRestoreSubtitle => '암호문, 새 기기 이전';

  @override
  String get notSet => '설정 안 됨';

  @override
  String get blockedList => '차단 목록';

  @override
  String get blockedListSubtitle => '서로 볼 수 없습니다';

  @override
  String get about => 'Elix 정보';

  @override
  String get aboutSubtitle => '별 사이의 거리를 건너는 신호';

  @override
  String get manual => '사용 설명서';

  @override
  String get signOutDevice => '이 기기에서 로그아웃';

  @override
  String get signOutSubtitle => '데이터 유지; 다음에는 passkey 필요';

  @override
  String get languagePickerTitle => '언어';

  @override
  String get languageSystemDescription => '이 기기의 언어 설정 사용';

  @override
  String get feedAll => '전체';

  @override
  String get feedFollowing => '팔로잉';

  @override
  String get feedBoards => '보드';

  @override
  String get searchBack => '← 초원';

  @override
  String get clear => '지우기';

  @override
  String get searchHint => 'murmur, 노트, 토론 검색';

  @override
  String get searchScopeAll => '전체';

  @override
  String get searchScopeMy => '내 것';

  @override
  String get searchScopeCircle => '서클';

  @override
  String get searchScopePublic => '공개';

  @override
  String searchResultCount(int count) {
    return '$count개 언급을 찾았습니다';
  }

  @override
  String get searchSortRelevant => '↓ 관련순';

  @override
  String notesSectionCount(int count) {
    return '노트 · $count';
  }

  @override
  String murmursSectionCount(int count) {
    return 'Murmurs · $count';
  }

  @override
  String threadsSectionCount(int count) {
    return '스레드 · $count';
  }

  @override
  String get noNotesYet => '아직 노트가 없습니다';

  @override
  String get noMatchingNotes => '일치하는 노트가 없습니다';

  @override
  String get noMurmursYet => '아직 murmur가 없습니다';

  @override
  String get noMatchingMurmurs => '일치하는 murmur가 없습니다';

  @override
  String get noThreadsYet => '아직 스레드가 없습니다';

  @override
  String get noMatchingThreads => '일치하는 스레드가 없습니다';

  @override
  String get murmurTitle => 'MURMUR';

  @override
  String get local => '로컬';

  @override
  String get send => '보내기';

  @override
  String get murmurPrompt => '아직 반쯤만 떠오른 생각이\n있나요?';

  @override
  String get murmurPrivateHint =>
      '문장, 직감, 아직 정리되지 않은 질문 모두 괜찮습니다. 아무도 보지 않습니다.';

  @override
  String get murmurSyncHint =>
      '문장, 직감, 아직 정리되지 않은 질문 모두 괜찮습니다. 이 항목은 동기화 가능으로 표시됩니다.';

  @override
  String get murmurInputHint => '요즘 계속 생각하는 것은';

  @override
  String get murmurPrivateVisibilityHint => '나만 보기';

  @override
  String get murmurUnlistedVisibilityHint => '목록 제외, 동기화 가능';

  @override
  String get murmurPublicVisibilityHint => '공개 게시';

  @override
  String get looseMurmurs => '흩어진 글';

  @override
  String get looseMurmursEmpty => '보낸 murmur는 먼저 여기에 남습니다.';

  @override
  String get sent => '보냈습니다';

  @override
  String get deletedMurmur => 'Murmur가 삭제되었습니다';

  @override
  String get unused => '미사용';

  @override
  String referenceCount(int count) {
    return '$count개 참조';
  }

  @override
  String get search => '검색';

  @override
  String get settingsNav => '설정';

  @override
  String get publicIdentity => '공개 신원';

  @override
  String get murmurTab => 'Murmur';

  @override
  String get notesTab => '노트';

  @override
  String get discussionsTab => '토론';

  @override
  String get discussionsTabCompact => '포럼';

  @override
  String get networkOnline => '온라인';

  @override
  String get networkOffline => '오프라인';

  @override
  String get networkChecking => '확인 중';

  @override
  String get workingNotes => '작업 노트';

  @override
  String get newest => '최신순';

  @override
  String get oldest => '오래된순';

  @override
  String get newNote => '새 노트';

  @override
  String get drawInAction => '↗ 끌어오기';

  @override
  String get noLooseMurmursYet => '아직 흩어진 murmur가 없습니다.';

  @override
  String get lineage => '계보';

  @override
  String get noteCreated => '노트를 만들었습니다';

  @override
  String get cancel => '취소';

  @override
  String get draftLocal => '초안은 로컬에 유지';

  @override
  String get editing => '편집 중';

  @override
  String get noteTitleHint => '노트 제목';

  @override
  String get noteTitleRequired => '제목을 입력하세요';

  @override
  String get noteBodyHint => '계속 쓰거나 아래에서 murmur를 끌어오세요...';

  @override
  String get noteBodyRequired => '노트 본문을 입력하세요';

  @override
  String get noteSubjectLabel => '이 노트';

  @override
  String get drawIn => '끌어오기';

  @override
  String get noMurmursToDraw => '아직 끌어올 murmur가 없습니다.';

  @override
  String get noNotesDescription => 'Murmur는 먼저 로컬에 흩어져 있다가 서로 연결되면 노트가 됩니다.';

  @override
  String get noteUpdated => '노트를 업데이트했습니다';

  @override
  String get visibilityUpdated => '공개 범위를 업데이트했습니다';

  @override
  String get lineageDescription => 'Murmur에서 만든 노트의 출처가 여기에 남습니다.';

  @override
  String get notePrivateSummary => '아직 아무도 볼 수 없습니다';

  @override
  String get noteNostrSummary => '게시하면 Nostr relays로 전송됩니다';

  @override
  String get noteActivityPubSummary => '게시하면 ActivityPub relay로 전송됩니다';

  @override
  String get noteBothSummary => '게시하면 Nostr relays와 ActivityPub relay로 전송됩니다';

  @override
  String get noteLocalPublicSummary => '공개 상태지만 아직 보내지 않음';

  @override
  String get createDiscussion => '토론 만들기';

  @override
  String get chooseHostedBoard => 'Hosted board 선택';

  @override
  String get hostedBoardMissing => '먼저 Forum Host의 hosted board에 참여하거나 만드세요';

  @override
  String get hostedBoardRequired => 'Hosted board를 선택하세요';

  @override
  String get titleLabel => '제목';

  @override
  String get discussionTitleHint => '토론 제목 입력';

  @override
  String get titleRequired => '제목은 필수입니다';

  @override
  String get contentLabel => '내용';

  @override
  String get discussionContentHint => '토론 내용 입력';

  @override
  String get contentRequired => '내용은 필수입니다';

  @override
  String get create => '만들기';

  @override
  String get uncategorized => '미분류';

  @override
  String get addForumHostFirst =>
      '먼저 동기화 설정에서 Forum Host를 추가하세요. 토론 보드는 Forum Host가 만듭니다.';

  @override
  String syncedPublicCount(int count) {
    return '공개 콘텐츠 $count개를 동기화했습니다';
  }

  @override
  String get publicQueuedRelayFailed => '공개 콘텐츠는 대기열에 추가됐지만 relay 게시에 실패했습니다';

  @override
  String get noWritableNostrRelay => '쓰기 가능한 Nostr relay가 설정되지 않았습니다';

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
  String get circleSection => '서클';

  @override
  String get allActivity => '전체 활동';

  @override
  String boardCount(int count) {
    return '보드 $count개';
  }

  @override
  String get manageSubscriptions => '구독 관리';

  @override
  String get newPost => '새 게시물';

  @override
  String get addBoardTooltip => '보드 추가';

  @override
  String get newDiscussion => '새 토론';

  @override
  String get createNewDiscussion => '새 토론 만들기';

  @override
  String get boardsShort => '보드';

  @override
  String get manageBoardsShort => '보드 관리';

  @override
  String get aiAssistant => 'AI 도우미';

  @override
  String get aiSummary => 'AI 요약';

  @override
  String get noPostsYet => '아직 게시물이 없습니다';

  @override
  String get subscribe => '구독';

  @override
  String get discussionAreaTitle => '토론 구역';

  @override
  String get publicOpen => '공개 · Open';

  @override
  String get noContentYet => '(아직 내용 없음)';

  @override
  String commentsCount(int count) {
    return '댓글 $count개';
  }

  @override
  String get manageBoards => '보드 관리';

  @override
  String get noBoardsYet => '아직 보드가 없습니다';

  @override
  String get deleteBoard => '보드 삭제';

  @override
  String deleteBoardConfirm(String title) {
    return '\"$title\"을 삭제할까요? 이 작업은 되돌릴 수 없습니다.';
  }

  @override
  String get delete => '삭제';

  @override
  String get close => '닫기';

  @override
  String get addBoard => '보드 추가';
}
