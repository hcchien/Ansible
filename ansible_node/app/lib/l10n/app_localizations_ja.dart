// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Japanese (`ja`).
class AppLocalizationsJa extends AppLocalizations {
  AppLocalizationsJa([String locale = 'ja']) : super(locale);

  @override
  String get appTitle => 'Ansible Node';

  @override
  String get settingsTitle => '設定';

  @override
  String get done => '完了';

  @override
  String get localIdentity => 'ローカル ID';

  @override
  String get localDid => 'ローカル DID';

  @override
  String get edit => '編集';

  @override
  String get identityAndDevice => 'ID とデバイス';

  @override
  String get wallet => 'ウォレット';

  @override
  String get walletSubtitleEmpty => '資格情報はありません';

  @override
  String walletSubtitleCount(int count) {
    return '$count 件の資格情報';
  }

  @override
  String get empty => '空';

  @override
  String get sync => '同期';

  @override
  String get syncSubtitle => 'Forum Host / Nostr relay 設定';

  @override
  String get configured => '設定';

  @override
  String get accessAudit => 'アクセスと監査';

  @override
  String get accessAuditSubtitle => 'どの ID を誰が見られるか';

  @override
  String get noSuspiciousAccess => '不審 0 件';

  @override
  String get language => '言語';

  @override
  String get languageSubtitle => 'アプリの表示言語を選択';

  @override
  String get systemDefault => 'システム設定に従う';

  @override
  String get daily => '日常';

  @override
  String get inbox => '受信箱';

  @override
  String get inboxSubtitle => 'サークル返信、新メンバー、同期';

  @override
  String get notifications => '通知';

  @override
  String get notificationsSubtitle => '通知する内容を決める';

  @override
  String get light => '軽め';

  @override
  String get readingPreferences => '読書設定';

  @override
  String get readingPreferencesSubtitle => '文字サイズ、行間、テーマ';

  @override
  String get defaultValue => '既定';

  @override
  String get boundaries => '境界';

  @override
  String get lock => 'ロック';

  @override
  String get lockSubtitle => 'アプリを空白のカバーにする';

  @override
  String get off => 'オフ';

  @override
  String get backupRestore => 'バックアップと復元';

  @override
  String get backupRestoreSubtitle => 'パスフレーズ、新しい端末への移行';

  @override
  String get notSet => '未設定';

  @override
  String get blockedList => 'ブロックリスト';

  @override
  String get blockedListSubtitle => '相手もあなたも互いに見えません';

  @override
  String get about => 'Ansible について';

  @override
  String get aboutSubtitle => '星間距離を越える信号';

  @override
  String get manual => 'マニュアル';

  @override
  String get signOutDevice => 'この端末からサインアウト';

  @override
  String get signOutSubtitle => 'データは保持し、次回は passkey が必要';

  @override
  String get languagePickerTitle => '言語';

  @override
  String get languageSystemDescription => '端末の言語設定を使用';

  @override
  String get feedAll => 'すべて';

  @override
  String get feedFollowing => 'フォロー中';

  @override
  String get feedBoards => 'ボード';

  @override
  String get searchBack => '← 草地';

  @override
  String get clear => 'クリア';

  @override
  String get searchHint => 'murmur、ノート、議論を検索';

  @override
  String get searchScopeAll => 'すべて';

  @override
  String get searchScopeMy => '自分';

  @override
  String get searchScopeCircle => 'サークル';

  @override
  String get searchScopePublic => '公開';

  @override
  String searchResultCount(int count) {
    return '$count 件見つかりました';
  }

  @override
  String get searchSortRelevant => '↓ 関連順';

  @override
  String notesSectionCount(int count) {
    return 'ノート · $count';
  }

  @override
  String murmursSectionCount(int count) {
    return 'Murmurs · $count';
  }

  @override
  String threadsSectionCount(int count) {
    return 'スレッド · $count';
  }

  @override
  String get noNotesYet => 'ノートはまだありません';

  @override
  String get noMatchingNotes => '一致するノートはありません';

  @override
  String get noMurmursYet => 'Murmur はまだありません';

  @override
  String get noMatchingMurmurs => '一致する murmur はありません';

  @override
  String get noThreadsYet => 'スレッドはまだありません';

  @override
  String get noMatchingThreads => '一致するスレッドはありません';

  @override
  String get murmurTitle => 'MURMUR';

  @override
  String get local => 'ローカル';

  @override
  String get send => '送信';

  @override
  String get murmurPrompt => '頭の中にある\nまだ形にならないものは？';

  @override
  String get murmurPrivateHint => '一文、直感、まだ整理できていない問いでも大丈夫です。誰にも見えません。';

  @override
  String get murmurSyncHint => '一文、直感、まだ整理できていない問いでも大丈夫です。これは同期可能として扱われます。';

  @override
  String get murmurInputHint => '最近ずっと考えていることは';

  @override
  String get murmurPrivateVisibilityHint => '自分だけ';

  @override
  String get murmurUnlistedVisibilityHint => '一覧外で同期可';

  @override
  String get murmurPublicVisibilityHint => '公開する';

  @override
  String get looseMurmurs => '散らばり';

  @override
  String get looseMurmursEmpty => '送信した murmur はまずここに残ります。';

  @override
  String get sent => '送信しました';

  @override
  String get deletedMurmur => 'Murmur を削除しました';

  @override
  String get unused => '未使用';

  @override
  String referenceCount(int count) {
    return '$count 件の参照';
  }

  @override
  String get search => '検索';

  @override
  String get settingsNav => '設定';

  @override
  String get publicIdentity => '公開 ID';

  @override
  String get murmurTab => 'Murmur';

  @override
  String get notesTab => 'ノート';

  @override
  String get discussionsTab => '議論';

  @override
  String get discussionsTabCompact => 'フォーラム';

  @override
  String get networkOnline => 'オンライン';

  @override
  String get networkOffline => 'オフライン';

  @override
  String get networkChecking => '確認中';

  @override
  String get workingNotes => '作業ノート';

  @override
  String get newest => '新しい順';

  @override
  String get oldest => '古い順';

  @override
  String get newNote => '新規ノート';

  @override
  String get drawInAction => '↗ 取り込む';

  @override
  String get noLooseMurmursYet => '散らばった murmur はまだありません。';

  @override
  String get lineage => '系譜';

  @override
  String get noteCreated => 'ノートを作成しました';

  @override
  String get cancel => 'キャンセル';

  @override
  String get draftLocal => '下書きはローカルに保持';

  @override
  String get editing => '編集中';

  @override
  String get noteTitleHint => 'ノートのタイトル';

  @override
  String get noteTitleRequired => 'タイトルを入力してください';

  @override
  String get noteBodyHint => '続きを書くか、下から murmur をドラッグしてください...';

  @override
  String get noteBodyRequired => '本文を入力してください';

  @override
  String get noteSubjectLabel => 'このノート';

  @override
  String get drawIn => '取り込む';

  @override
  String get noMurmursToDraw => '取り込める murmur はまだありません。';

  @override
  String get noNotesDescription => 'Murmur はまずローカルに散らばって残り、つながり始めたらノートにできます。';

  @override
  String get noteUpdated => 'ノートを更新しました';

  @override
  String get visibilityUpdated => '公開範囲を更新しました';

  @override
  String get lineageDescription => 'Murmur から作ったノートの出典はここに残ります。';

  @override
  String get notePrivateSummary => 'まだ誰にも表示されません';

  @override
  String get noteNostrSummary => '公開すると Nostr relays に送信されます';

  @override
  String get noteActivityPubSummary => '公開すると ActivityPub relay に送信されます';

  @override
  String get noteBothSummary =>
      '公開すると Nostr relays と ActivityPub relay に送信されます';

  @override
  String get noteLocalPublicSummary => '公開状態ですが、まだ送信しません';

  @override
  String get createDiscussion => '議論を作成';

  @override
  String get chooseHostedBoard => 'Hosted board を選択';

  @override
  String get hostedBoardMissing =>
      'まず Forum Host の hosted board に参加または作成してください';

  @override
  String get hostedBoardRequired => 'Hosted board を選択してください';

  @override
  String get titleLabel => 'タイトル';

  @override
  String get discussionTitleHint => '議論タイトルを入力';

  @override
  String get titleRequired => 'タイトルは必須です';

  @override
  String get contentLabel => '本文';

  @override
  String get discussionContentHint => '議論内容を入力';

  @override
  String get contentRequired => '本文は必須です';

  @override
  String get create => '作成';

  @override
  String get uncategorized => '未分類';

  @override
  String get addForumHostFirst =>
      'まず同期設定で Forum Host を追加してください。議論ボードは Forum Host が作成します。';

  @override
  String syncedPublicCount(int count) {
    return '$count 件の公開コンテンツを同期しました';
  }

  @override
  String get publicQueuedRelayFailed => '公開コンテンツはキューに入りましたが、relay への公開に失敗しました';

  @override
  String get noWritableNostrRelay => '書き込み可能な Nostr relay が設定されていません';

  @override
  String syncFailedMessage(String error) {
    return '同期失敗: $error';
  }

  @override
  String get justNow => 'たった今';

  @override
  String minutesAgo(int count) {
    return '$count 分前';
  }

  @override
  String hoursAgo(int count) {
    return '$count 時間前';
  }

  @override
  String daysAgo(int count) {
    return '$count 日前';
  }

  @override
  String get circleSection => 'サークル';

  @override
  String get allActivity => 'すべての活動';

  @override
  String boardCount(int count) {
    return '$count ボード';
  }

  @override
  String get manageSubscriptions => '購読を管理';

  @override
  String get newPost => '新規投稿';

  @override
  String get addBoardTooltip => 'ボードを追加';

  @override
  String get newDiscussion => '新規議論';

  @override
  String get createNewDiscussion => '新しい議論を作成';

  @override
  String get boardsShort => 'ボード';

  @override
  String get manageBoardsShort => 'ボード管理';

  @override
  String get aiAssistant => 'AI アシスタント';

  @override
  String get aiSummary => 'AI 要約';

  @override
  String get noPostsYet => '投稿はまだありません';

  @override
  String get subscribe => '購読';

  @override
  String get discussionAreaTitle => '議論エリア';

  @override
  String get publicOpen => '公開 · Open';

  @override
  String get noContentYet => '（内容はまだありません）';

  @override
  String commentsCount(int count) {
    return '$count 件のコメント';
  }

  @override
  String get manageBoards => 'ボード管理';

  @override
  String get noBoardsYet => 'ボードはまだありません';

  @override
  String get deleteBoard => 'ボードを削除';

  @override
  String deleteBoardConfirm(String title) {
    return '「$title」を削除しますか？この操作は元に戻せません。';
  }

  @override
  String get delete => '削除';

  @override
  String get close => '閉じる';

  @override
  String get addBoard => 'ボードを追加';
}
