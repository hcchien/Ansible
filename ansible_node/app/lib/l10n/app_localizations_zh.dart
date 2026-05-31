// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get appTitle => 'Elix';

  @override
  String get settingsTitle => 'SETTINGS';

  @override
  String get done => '完成';

  @override
  String get localIdentity => '本機身分';

  @override
  String get localDid => '本機 DID';

  @override
  String get edit => '編輯';

  @override
  String get identityAndDevice => '身分與裝置 · IDENTITY';

  @override
  String get wallet => '皮夾';

  @override
  String get walletSubtitleEmpty => '尚無憑證';

  @override
  String walletSubtitleCount(int count) {
    return '$count 個憑證';
  }

  @override
  String get empty => '空';

  @override
  String get sync => '同步';

  @override
  String get syncSubtitle => 'Forum Host / Nostr relay 設定';

  @override
  String get configured => '設定';

  @override
  String get accessAudit => '存取與審計';

  @override
  String get accessAuditSubtitle => '誰看見了哪一個我';

  @override
  String get noSuspiciousAccess => '0 可疑';

  @override
  String get language => '語言';

  @override
  String get languageSubtitle => '選擇 app 介面語言';

  @override
  String get systemDefault => '跟隨系統';

  @override
  String get daily => '日常 · DAILY';

  @override
  String get inbox => '收信';

  @override
  String get inboxSubtitle => '圈內回覆、新成員、同步';

  @override
  String get notifications => '通知';

  @override
  String get notificationsSubtitle => '決定哪些事會打擾你';

  @override
  String get light => '輕';

  @override
  String get readingPreferences => '閱讀偏好';

  @override
  String get readingPreferencesSubtitle => '字級、行距、主題';

  @override
  String get defaultValue => '預設';

  @override
  String get boundaries => '邊界 · BOUNDARIES';

  @override
  String get lock => '鎖定';

  @override
  String get lockSubtitle => '把 app 變成空白封面';

  @override
  String get off => '關閉';

  @override
  String get backupRestore => '備份與還原';

  @override
  String get backupRestoreSubtitle => 'passphrase、新裝置遷移';

  @override
  String get notSet => '未設';

  @override
  String get blockedList => '封鎖名單';

  @override
  String get blockedListSubtitle => '你看不到，他們也看不到你';

  @override
  String get about => '關於 Elix';

  @override
  String get aboutSubtitle => '信號越過星際的距離';

  @override
  String get manual => '使用手冊';

  @override
  String get signOutDevice => '登出此裝置';

  @override
  String get signOutSubtitle => '保留資料；下次需要 passkey';

  @override
  String get languagePickerTitle => '語言';

  @override
  String get languageSystemDescription => '使用裝置的語言設定';

  @override
  String get feedAll => '動態';

  @override
  String get feedFollowing => '追蹤';

  @override
  String get feedBoards => '看板';

  @override
  String get searchBack => '← 草地';

  @override
  String get clear => '清除';

  @override
  String get searchHint => '搜尋 murmur、筆記、討論';

  @override
  String get searchScopeAll => '全部';

  @override
  String get searchScopeMy => '我的';

  @override
  String get searchScopeCircle => '圈內';

  @override
  String get searchScopePublic => '公開';

  @override
  String searchResultCount(int count) {
    return '找到 $count 處提及';
  }

  @override
  String get searchSortRelevant => '↓ 相關';

  @override
  String notesSectionCount(int count) {
    return '筆記 · NOTES · $count';
  }

  @override
  String murmursSectionCount(int count) {
    return '碎念 · MURMURS · $count';
  }

  @override
  String threadsSectionCount(int count) {
    return '討論串 · FORUM · $count';
  }

  @override
  String get noNotesYet => '目前沒有筆記';

  @override
  String get noMatchingNotes => '沒有符合的筆記';

  @override
  String get noMurmursYet => '目前沒有碎念';

  @override
  String get noMatchingMurmurs => '沒有符合的碎念';

  @override
  String get noThreadsYet => '目前沒有討論串';

  @override
  String get noMatchingThreads => '沒有符合的討論串';

  @override
  String get murmurTitle => 'MURMUR · 碎念';

  @override
  String get local => '本地';

  @override
  String get send => '送出';

  @override
  String get murmurPrompt => '現在腦子裡\n有什麼半成形的東西嗎？';

  @override
  String get murmurPrivateHint => '一句話、一個直覺、一個還沒理順的問題都可以。沒人會看到。';

  @override
  String get murmurSyncHint => '一句話、一個直覺、一個還沒理順的問題都可以。這則會標記為可同步。';

  @override
  String get murmurInputHint => '這幾個月一直在想的事情是';

  @override
  String get murmurPrivateVisibilityHint => '只給自己';

  @override
  String get murmurUnlistedVisibilityHint => '不列出但可同步';

  @override
  String get murmurPublicVisibilityHint => '公開發布';

  @override
  String get looseMurmurs => '散落';

  @override
  String get looseMurmursEmpty => '送出的碎念會先留在這裡。';

  @override
  String get sent => '已送出';

  @override
  String get deletedMurmur => '已刪除碎念';

  @override
  String get unused => '未使用';

  @override
  String referenceCount(int count) {
    return '$count 篇引用';
  }

  @override
  String get search => '搜尋';

  @override
  String get settingsNav => '設定';

  @override
  String get publicIdentity => '公開身分';

  @override
  String get murmurTab => '碎念';

  @override
  String get notesTab => '筆記';

  @override
  String get discussionsTab => '看板';

  @override
  String get discussionsTabCompact => '看板';

  @override
  String get networkOnline => '已連線';

  @override
  String get networkOffline => '離線';

  @override
  String get networkChecking => '檢查中';

  @override
  String get workingNotes => '草地';

  @override
  String get newest => '最近';

  @override
  String get oldest => '最舊';

  @override
  String get newNote => '新增筆記';

  @override
  String get drawInAction => '↗ 編入';

  @override
  String get noLooseMurmursYet => '還沒有散落的碎念。';

  @override
  String get lineage => '來源 · LINEAGE';

  @override
  String get noteCreated => '已建立筆記';

  @override
  String get cancel => '取消';

  @override
  String get draftLocal => '草稿保留 · 本機';

  @override
  String get editing => '編輯中 · EDITING';

  @override
  String get noteTitleHint => '筆記標題';

  @override
  String get noteTitleRequired => '請輸入標題';

  @override
  String get noteBodyHint => '繼續寫下去，或從下方拖一個 murmur 進來……';

  @override
  String get noteBodyRequired => '請輸入內文';

  @override
  String get noteSubjectLabel => '這篇 note';

  @override
  String get drawIn => '編入 · DRAW IN';

  @override
  String get noMurmursToDraw => '還沒有可以編入的 murmur。';

  @override
  String get noNotesDescription => '碎念會先散落在本地；等它們慢慢靠近，再編成一篇筆記。';

  @override
  String get noteUpdated => '已更新筆記';

  @override
  String get visibilityUpdated => '可見性已更新';

  @override
  String get lineageDescription => '由 murmur 編成的筆記會在這裡保留來源。';

  @override
  String get notePrivateSummary => '還沒讓任何人看見';

  @override
  String get noteNostrSummary => '公開後會送到 Nostr relays';

  @override
  String get noteActivityPubSummary => '公開後會送到 ActivityPub relay';

  @override
  String get noteBothSummary => '公開後會送到 Nostr relays 與 ActivityPub relay';

  @override
  String get noteLocalPublicSummary => '公開狀態，但暫不送出';

  @override
  String get createDiscussion => '建立討論';

  @override
  String get chooseHostedBoard => '選擇 hosted board';

  @override
  String get hostedBoardMissing => '請先加入或建立 Forum Host 的 hosted board';

  @override
  String get hostedBoardRequired => '請選擇 hosted board';

  @override
  String get titleLabel => '標題';

  @override
  String get discussionTitleHint => '輸入討論標題';

  @override
  String get titleRequired => '標題為必填';

  @override
  String get contentLabel => '內容';

  @override
  String get discussionContentHint => '輸入討論內容';

  @override
  String get contentRequired => '內容為必填';

  @override
  String get create => '建立';

  @override
  String get uncategorized => '未分類';

  @override
  String get addForumHostFirst => '請先在同步設定新增 Forum Host。討論看板由 Forum Host 建立。';

  @override
  String syncedPublicCount(int count) {
    return '已同步 $count 篇公開內容';
  }

  @override
  String get publicQueuedRelayFailed => '公開內容已排入同步，但 relay 發佈失敗';

  @override
  String get noWritableNostrRelay => '尚未設定可寫入的 Nostr relay';

  @override
  String syncFailedMessage(String error) {
    return '同步失敗：$error';
  }

  @override
  String get justNow => '剛剛';

  @override
  String minutesAgo(int count) {
    return '$count 分鐘前';
  }

  @override
  String hoursAgo(int count) {
    return '$count 小時前';
  }

  @override
  String daysAgo(int count) {
    return '$count 天前';
  }

  @override
  String get circleSection => '圈 · CIRCLE';

  @override
  String get allActivity => '全部動態';

  @override
  String boardCount(int count) {
    return '$count 看板';
  }

  @override
  String get manageSubscriptions => '管理訂閱';

  @override
  String get newPost => '新貼文';

  @override
  String get addBoardTooltip => '新增看板';

  @override
  String get newDiscussion => '新板上討論';

  @override
  String get createNewDiscussion => '建立板上討論';

  @override
  String get boardsShort => '看板';

  @override
  String get manageBoardsShort => '管理看板';

  @override
  String get aiAssistant => 'AI 助手';

  @override
  String get aiSummary => 'AI 摘要';

  @override
  String get noPostsYet => '目前沒有動態';

  @override
  String get subscribe => '訂閱';

  @override
  String get discussionAreaTitle => '動態';

  @override
  String get feedSocialIdentitySubtitle =>
      'Note 與 Murmur 是個人版發文類型；追蹤你的人會在他們的 feed 上看到，訂閱的看板則帶入公共討論。';

  @override
  String get publicOpen => '追蹤 + 看板';

  @override
  String get noContentYet => '（尚無內容）';

  @override
  String commentsCount(int count) {
    return '$count 則留言';
  }

  @override
  String get manageBoards => '管理看板';

  @override
  String get noBoardsYet => '目前沒有看板';

  @override
  String get deleteBoard => '刪除看板';

  @override
  String deleteBoardConfirm(String title) {
    return '確定刪除「$title」？此動作不可恢復。';
  }

  @override
  String get delete => '刪除';

  @override
  String get close => '關閉';

  @override
  String get addBoard => '新增看板';
}

/// The translations for Chinese, using the Han script (`zh_Hant`).
class AppLocalizationsZhHant extends AppLocalizationsZh {
  AppLocalizationsZhHant() : super('zh_Hant');

  @override
  String get appTitle => 'Elix';

  @override
  String get settingsTitle => 'SETTINGS';

  @override
  String get done => '完成';

  @override
  String get localIdentity => '本機身分';

  @override
  String get localDid => '本機 DID';

  @override
  String get edit => '編輯';

  @override
  String get identityAndDevice => '身分與裝置 · IDENTITY';

  @override
  String get wallet => '皮夾';

  @override
  String get walletSubtitleEmpty => '尚無憑證';

  @override
  String walletSubtitleCount(int count) {
    return '$count 個憑證';
  }

  @override
  String get empty => '空';

  @override
  String get sync => '同步';

  @override
  String get syncSubtitle => 'Forum Host / Nostr relay 設定';

  @override
  String get configured => '設定';

  @override
  String get accessAudit => '存取與審計';

  @override
  String get accessAuditSubtitle => '誰看見了哪一個我';

  @override
  String get noSuspiciousAccess => '0 可疑';

  @override
  String get language => '語言';

  @override
  String get languageSubtitle => '選擇 app 介面語言';

  @override
  String get systemDefault => '跟隨系統';

  @override
  String get daily => '日常 · DAILY';

  @override
  String get inbox => '收信';

  @override
  String get inboxSubtitle => '圈內回覆、新成員、同步';

  @override
  String get notifications => '通知';

  @override
  String get notificationsSubtitle => '決定哪些事會打擾你';

  @override
  String get light => '輕';

  @override
  String get readingPreferences => '閱讀偏好';

  @override
  String get readingPreferencesSubtitle => '字級、行距、主題';

  @override
  String get defaultValue => '預設';

  @override
  String get boundaries => '邊界 · BOUNDARIES';

  @override
  String get lock => '鎖定';

  @override
  String get lockSubtitle => '把 app 變成空白封面';

  @override
  String get off => '關閉';

  @override
  String get backupRestore => '備份與還原';

  @override
  String get backupRestoreSubtitle => 'passphrase、新裝置遷移';

  @override
  String get notSet => '未設';

  @override
  String get blockedList => '封鎖名單';

  @override
  String get blockedListSubtitle => '你看不到，他們也看不到你';

  @override
  String get about => '關於 Elix';

  @override
  String get aboutSubtitle => '信號越過星際的距離';

  @override
  String get manual => '使用手冊';

  @override
  String get signOutDevice => '登出此裝置';

  @override
  String get signOutSubtitle => '保留資料；下次需要 passkey';

  @override
  String get languagePickerTitle => '語言';

  @override
  String get languageSystemDescription => '使用裝置的語言設定';

  @override
  String get feedAll => '動態';

  @override
  String get feedFollowing => '追蹤';

  @override
  String get feedBoards => '看板';

  @override
  String get searchBack => '← 草地';

  @override
  String get clear => '清除';

  @override
  String get searchHint => '搜尋 murmur、筆記、討論';

  @override
  String get searchScopeAll => '全部';

  @override
  String get searchScopeMy => '我的';

  @override
  String get searchScopeCircle => '圈內';

  @override
  String get searchScopePublic => '公開';

  @override
  String searchResultCount(int count) {
    return '找到 $count 處提及';
  }

  @override
  String get searchSortRelevant => '↓ 相關';

  @override
  String notesSectionCount(int count) {
    return '筆記 · NOTES · $count';
  }

  @override
  String murmursSectionCount(int count) {
    return '碎念 · MURMURS · $count';
  }

  @override
  String threadsSectionCount(int count) {
    return '討論串 · FORUM · $count';
  }

  @override
  String get noNotesYet => '目前沒有筆記';

  @override
  String get noMatchingNotes => '沒有符合的筆記';

  @override
  String get noMurmursYet => '目前沒有碎念';

  @override
  String get noMatchingMurmurs => '沒有符合的碎念';

  @override
  String get noThreadsYet => '目前沒有討論串';

  @override
  String get noMatchingThreads => '沒有符合的討論串';

  @override
  String get murmurTitle => 'MURMUR · 碎念';

  @override
  String get local => '本地';

  @override
  String get send => '送出';

  @override
  String get murmurPrompt => '現在腦子裡\n有什麼半成形的東西嗎？';

  @override
  String get murmurPrivateHint => '一句話、一個直覺、一個還沒理順的問題都可以。沒人會看到。';

  @override
  String get murmurSyncHint => '一句話、一個直覺、一個還沒理順的問題都可以。這則會標記為可同步。';

  @override
  String get murmurInputHint => '這幾個月一直在想的事情是';

  @override
  String get murmurPrivateVisibilityHint => '只給自己';

  @override
  String get murmurUnlistedVisibilityHint => '不列出但可同步';

  @override
  String get murmurPublicVisibilityHint => '公開發布';

  @override
  String get looseMurmurs => '散落';

  @override
  String get looseMurmursEmpty => '送出的碎念會先留在這裡。';

  @override
  String get sent => '已送出';

  @override
  String get deletedMurmur => '已刪除碎念';

  @override
  String get unused => '未使用';

  @override
  String referenceCount(int count) {
    return '$count 篇引用';
  }

  @override
  String get search => '搜尋';

  @override
  String get settingsNav => '設定';

  @override
  String get publicIdentity => '公開身分';

  @override
  String get murmurTab => '碎念';

  @override
  String get notesTab => '筆記';

  @override
  String get discussionsTab => '看板';

  @override
  String get discussionsTabCompact => '看板';

  @override
  String get networkOnline => '已連線';

  @override
  String get networkOffline => '離線';

  @override
  String get networkChecking => '檢查中';

  @override
  String get workingNotes => '草地';

  @override
  String get newest => '最近';

  @override
  String get oldest => '最舊';

  @override
  String get newNote => '新增筆記';

  @override
  String get drawInAction => '↗ 編入';

  @override
  String get noLooseMurmursYet => '還沒有散落的碎念。';

  @override
  String get lineage => '來源 · LINEAGE';

  @override
  String get noteCreated => '已建立筆記';

  @override
  String get cancel => '取消';

  @override
  String get draftLocal => '草稿保留 · 本機';

  @override
  String get editing => '編輯中 · EDITING';

  @override
  String get noteTitleHint => '筆記標題';

  @override
  String get noteTitleRequired => '請輸入標題';

  @override
  String get noteBodyHint => '繼續寫下去，或從下方拖一個 murmur 進來……';

  @override
  String get noteBodyRequired => '請輸入內文';

  @override
  String get noteSubjectLabel => '這篇 note';

  @override
  String get drawIn => '編入 · DRAW IN';

  @override
  String get noMurmursToDraw => '還沒有可以編入的 murmur。';

  @override
  String get noNotesDescription => '碎念會先散落在本地；等它們慢慢靠近，再編成一篇筆記。';

  @override
  String get noteUpdated => '已更新筆記';

  @override
  String get visibilityUpdated => '可見性已更新';

  @override
  String get lineageDescription => '由 murmur 編成的筆記會在這裡保留來源。';

  @override
  String get notePrivateSummary => '還沒讓任何人看見';

  @override
  String get noteNostrSummary => '公開後會送到 Nostr relays';

  @override
  String get noteActivityPubSummary => '公開後會送到 ActivityPub relay';

  @override
  String get noteBothSummary => '公開後會送到 Nostr relays 與 ActivityPub relay';

  @override
  String get noteLocalPublicSummary => '公開狀態，但暫不送出';

  @override
  String get createDiscussion => '建立討論';

  @override
  String get chooseHostedBoard => '選擇 hosted board';

  @override
  String get hostedBoardMissing => '請先加入或建立 Forum Host 的 hosted board';

  @override
  String get hostedBoardRequired => '請選擇 hosted board';

  @override
  String get titleLabel => '標題';

  @override
  String get discussionTitleHint => '輸入討論標題';

  @override
  String get titleRequired => '標題為必填';

  @override
  String get contentLabel => '內容';

  @override
  String get discussionContentHint => '輸入討論內容';

  @override
  String get contentRequired => '內容為必填';

  @override
  String get create => '建立';

  @override
  String get uncategorized => '未分類';

  @override
  String get addForumHostFirst => '請先在同步設定新增 Forum Host。討論看板由 Forum Host 建立。';

  @override
  String syncedPublicCount(int count) {
    return '已同步 $count 篇公開內容';
  }

  @override
  String get publicQueuedRelayFailed => '公開內容已排入同步，但 relay 發佈失敗';

  @override
  String get noWritableNostrRelay => '尚未設定可寫入的 Nostr relay';

  @override
  String syncFailedMessage(String error) {
    return '同步失敗：$error';
  }

  @override
  String get justNow => '剛剛';

  @override
  String minutesAgo(int count) {
    return '$count 分鐘前';
  }

  @override
  String hoursAgo(int count) {
    return '$count 小時前';
  }

  @override
  String daysAgo(int count) {
    return '$count 天前';
  }

  @override
  String get circleSection => '圈 · CIRCLE';

  @override
  String get allActivity => '全部動態';

  @override
  String boardCount(int count) {
    return '$count 看板';
  }

  @override
  String get manageSubscriptions => '管理訂閱';

  @override
  String get newPost => '新貼文';

  @override
  String get addBoardTooltip => '新增看板';

  @override
  String get newDiscussion => '新板上討論';

  @override
  String get createNewDiscussion => '建立板上討論';

  @override
  String get boardsShort => '看板';

  @override
  String get manageBoardsShort => '管理看板';

  @override
  String get aiAssistant => 'AI 助手';

  @override
  String get aiSummary => 'AI 摘要';

  @override
  String get noPostsYet => '目前沒有動態';

  @override
  String get subscribe => '訂閱';

  @override
  String get discussionAreaTitle => '動態';

  @override
  String get feedSocialIdentitySubtitle =>
      'Note 與 Murmur 是個人版發文類型；追蹤你的人會在他們的 feed 上看到，訂閱的看板則帶入公共討論。';

  @override
  String get publicOpen => '追蹤 + 看板';

  @override
  String get noContentYet => '（尚無內容）';

  @override
  String commentsCount(int count) {
    return '$count 則留言';
  }

  @override
  String get manageBoards => '管理看板';

  @override
  String get noBoardsYet => '目前沒有看板';

  @override
  String get deleteBoard => '刪除看板';

  @override
  String deleteBoardConfirm(String title) {
    return '確定刪除「$title」？此動作不可恢復。';
  }

  @override
  String get delete => '刪除';

  @override
  String get close => '關閉';

  @override
  String get addBoard => '新增看板';
}
