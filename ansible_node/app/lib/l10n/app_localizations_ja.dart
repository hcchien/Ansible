// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Japanese (`ja`).
class AppLocalizationsJa extends AppLocalizations {
  AppLocalizationsJa([String locale = 'ja']) : super(locale);

  @override
  String get appTitle => 'Elix';

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
  String get walletSubtitleEmpty => '認証情報はありません';

  @override
  String walletSubtitleCount(int count) {
    return '$count 件の認証情報';
  }

  @override
  String get empty => '空';

  @override
  String get sync => '同期';

  @override
  String get syncSubtitle => 'Elix Relay の設定';

  @override
  String get configured => '設定';

  @override
  String get accessAudit => 'アクセスと監査';

  @override
  String get accessAuditSubtitle => 'どの ID が誰に表示されたか';

  @override
  String get noSuspiciousAccess => '不審なアクセス 0 件';

  @override
  String get language => '言語';

  @override
  String get languageSubtitle => 'アプリの表示言語を選択';

  @override
  String get systemDefault => 'システムのデフォルト';

  @override
  String get daily => '日常';

  @override
  String get inbox => '受信箱';

  @override
  String get inboxSubtitle => '返信、新しいメンバー、同期';

  @override
  String get notifications => '通知';

  @override
  String get notificationsSubtitle => '通知する項目を選択';

  @override
  String get light => 'ライト';

  @override
  String get readingPreferences => '表示設定';

  @override
  String get readingPreferencesSubtitle => '文字サイズ、行間、テーマ';

  @override
  String get defaultValue => '標準';

  @override
  String get boundaries => '境界';

  @override
  String get lock => 'ロック';

  @override
  String get lockSubtitle => 'アプリを空白のカバーに切り替えます';

  @override
  String get off => 'オフ';

  @override
  String get backupRestore => 'バックアップと復元';

  @override
  String get backupRestoreSubtitle => 'パスフレーズ、新しいデバイスへの移行';

  @override
  String get notSet => '未設定';

  @override
  String get blockedList => 'ブロックリスト';

  @override
  String get blockedListSubtitle => 'お互いに表示されません';

  @override
  String get about => 'Elix について';

  @override
  String get aboutSubtitle => '星間距離を越えるシグナル';

  @override
  String get manual => 'マニュアル';

  @override
  String get signOutDevice => 'このデバイスからログアウト';

  @override
  String get signOutSubtitle => 'データを保持し、次回はパスキーを使用';

  @override
  String get languagePickerTitle => '言語';

  @override
  String get languageSystemDescription => 'このデバイスの言語設定を使用';

  @override
  String get feedAll => 'フィード';

  @override
  String get feedFollowing => 'フォロー中';

  @override
  String get feedBoards => 'ボード';

  @override
  String get searchBack => '← 戻る';

  @override
  String get clear => 'クリア';

  @override
  String get searchHint => 'つぶやき、ノート、議論を検索';

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
  String get searchSortRelevant => '↓ 関連度順';

  @override
  String notesSectionCount(int count) {
    return 'ノート · $count';
  }

  @override
  String murmursSectionCount(int count) {
    return 'つぶやき · $count';
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
  String get noMurmursYet => 'つぶやきはまだありません';

  @override
  String get noMatchingMurmurs => '一致するつぶやきはありません';

  @override
  String get noThreadsYet => 'スレッドはまだありません';

  @override
  String get noMatchingThreads => '一致するスレッドはありません';

  @override
  String get murmurTitle => 'つぶやき';

  @override
  String get local => 'ローカル';

  @override
  String get send => '送信';

  @override
  String get murmurPrompt => 'まだ形になっていない考えはありますか？';

  @override
  String get murmurPrivateHint => '一文、直感、答えのない問いでも構いません。ほかの人には表示されません。';

  @override
  String get murmurSyncHint => '一文、直感、答えのない問いでも構いません。同期可能として保存されます。';

  @override
  String get murmurInputHint => '最近考えていることは';

  @override
  String get murmurPrivateVisibilityHint => '自分だけ';

  @override
  String get murmurUnlistedVisibilityHint => '同期可能・一覧には非表示';

  @override
  String get murmurPublicVisibilityHint => '公開する';

  @override
  String get looseMurmurs => '未整理';

  @override
  String get looseMurmursEmpty => '送信したつぶやきは最初にここへ保存されます。';

  @override
  String get sent => '送信済み';

  @override
  String get deletedMurmur => 'つぶやきを削除しました';

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
  String get murmurTab => 'つぶやき';

  @override
  String get notesTab => 'ノート';

  @override
  String get discussionsTab => 'ボード';

  @override
  String get discussionsTabCompact => 'ボード';

  @override
  String get networkOnline => 'オンライン';

  @override
  String get networkOffline => 'オフライン';

  @override
  String get networkChecking => '確認中';

  @override
  String get workingNotes => '作業中のノート';

  @override
  String get newest => '新しい順';

  @override
  String get oldest => '古い順';

  @override
  String get newNote => '新しいノート';

  @override
  String get drawInAction => '↗ 取り込む';

  @override
  String get noLooseMurmursYet => '取り込めるつぶやきはまだありません。';

  @override
  String get lineage => '出典';

  @override
  String get noteCreated => 'ノートを作成しました';

  @override
  String get cancel => 'キャンセル';

  @override
  String get draftLocal => '下書きはローカルに保存されます';

  @override
  String get editing => '編集中';

  @override
  String get noteTitleHint => 'ノートのタイトル';

  @override
  String get noteTitleRequired => 'タイトルを入力してください';

  @override
  String get noteBodyHint => '続きを書くか、下のつぶやきを取り込んでください…';

  @override
  String get noteBodyRequired => '本文を入力してください';

  @override
  String get noteSubjectLabel => 'このノート';

  @override
  String get drawIn => '取り込む';

  @override
  String get noMurmursToDraw => '取り込めるつぶやきはまだありません。';

  @override
  String get noNotesDescription => 'つぶやきはまずローカルに残ります。考えがつながり始めたらノートにまとめましょう。';

  @override
  String get noteUpdated => 'ノートを更新しました';

  @override
  String get visibilityUpdated => '公開範囲を更新しました';

  @override
  String get lineageDescription => 'つぶやきから作成したノートの出典をここに残します。';

  @override
  String get notePrivateSummary => 'まだほかの人には表示されません';

  @override
  String get noteNostrSummary => '公開すると Nostr Relay に送信されます';

  @override
  String get noteActivityPubSummary => '公開すると ActivityPub Relay に送信されます';

  @override
  String get noteBothSummary => '公開すると Nostr と ActivityPub の Relay に送信されます';

  @override
  String get noteLocalPublicSummary => '公開状態ですが、まだ送信されていません';

  @override
  String get createDiscussion => '議論を作成';

  @override
  String get chooseHostedBoard => 'ボードを選択';

  @override
  String get hostedBoardMissing => '先に Elix Relay のボードへ参加するか作成してください';

  @override
  String get hostedBoardRequired => 'ボードを選択してください';

  @override
  String get titleLabel => 'タイトル';

  @override
  String get discussionTitleHint => '議論のタイトルを入力';

  @override
  String get titleRequired => 'タイトルは必須です';

  @override
  String get contentLabel => '内容';

  @override
  String get discussionContentHint => '議論の内容を入力';

  @override
  String get contentRequired => '内容は必須です';

  @override
  String get create => '作成';

  @override
  String get uncategorized => '未分類';

  @override
  String get addForumHostFirst =>
      '先に同期設定で Elix Relay を追加してください。議論ボードは Elix Relay 上に作成されます。';

  @override
  String syncedPublicCount(int count) {
    return '公開項目 $count 件を同期しました';
  }

  @override
  String get publicQueuedRelayFailed => '公開内容をキューに追加しましたが、Relay への公開に失敗しました';

  @override
  String get noWritableNostrRelay => '書き込み可能な Nostr Relay が設定されていません';

  @override
  String syncFailedMessage(String error) {
    return '同期に失敗しました：$error';
  }

  @override
  String get justNow => 'たった今';

  @override
  String minutesAgo(int count) {
    return '$count分前';
  }

  @override
  String hoursAgo(int count) {
    return '$count時間前';
  }

  @override
  String daysAgo(int count) {
    return '$count日前';
  }

  @override
  String get circleSection => 'サークル';

  @override
  String get allActivity => 'すべてのアクティビティ';

  @override
  String boardCount(int count) {
    return '$count ボード';
  }

  @override
  String get manageSubscriptions => '購読を管理';

  @override
  String get newPost => '新しい投稿';

  @override
  String get addBoardTooltip => 'ボードを追加';

  @override
  String get newDiscussion => '新しいボードスレッド';

  @override
  String get createNewDiscussion => 'ボードスレッドを作成';

  @override
  String get boardsShort => 'ボード';

  @override
  String get manageBoardsShort => 'ボードを管理';

  @override
  String get aiAssistant => 'AI アシスタント';

  @override
  String get aiSummary => 'AI 要約';

  @override
  String get noPostsYet => 'フィード投稿はまだありません';

  @override
  String get subscribe => '購読';

  @override
  String get discussionAreaTitle => 'フィード';

  @override
  String get feedSocialIdentitySubtitle =>
      'ノートとつぶやきは個人投稿です。フォロワーのフィードに表示され、ボードでは共有の議論に参加できます。';

  @override
  String get publicOpen => 'ユーザー + ボード';

  @override
  String get noContentYet => '（内容はまだありません）';

  @override
  String commentsCount(int count) {
    return '$count 件のコメント';
  }

  @override
  String get manageBoards => 'ボードを管理';

  @override
  String get noBoardsYet => 'ボードはまだありません';

  @override
  String get deleteBoard => 'ボードを削除';

  @override
  String deleteBoardConfirm(String title) {
    return '「$title」を削除しますか？この操作は取り消せません。';
  }

  @override
  String get delete => '削除';

  @override
  String get close => '閉じる';

  @override
  String get addBoard => 'ボードを追加';
}
