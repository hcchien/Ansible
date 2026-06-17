import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('zh'),
    Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In zh_Hant, this message translates to:
  /// **'Elix'**
  String get appTitle;

  /// No description provided for @settingsTitle.
  ///
  /// In zh_Hant, this message translates to:
  /// **'SETTINGS'**
  String get settingsTitle;

  /// No description provided for @done.
  ///
  /// In zh_Hant, this message translates to:
  /// **'完成'**
  String get done;

  /// No description provided for @localIdentity.
  ///
  /// In zh_Hant, this message translates to:
  /// **'本機身分'**
  String get localIdentity;

  /// No description provided for @localDid.
  ///
  /// In zh_Hant, this message translates to:
  /// **'本機 DID'**
  String get localDid;

  /// No description provided for @edit.
  ///
  /// In zh_Hant, this message translates to:
  /// **'編輯'**
  String get edit;

  /// No description provided for @identityAndDevice.
  ///
  /// In zh_Hant, this message translates to:
  /// **'身分與裝置 · IDENTITY'**
  String get identityAndDevice;

  /// No description provided for @wallet.
  ///
  /// In zh_Hant, this message translates to:
  /// **'皮夾'**
  String get wallet;

  /// No description provided for @walletSubtitleEmpty.
  ///
  /// In zh_Hant, this message translates to:
  /// **'尚無憑證'**
  String get walletSubtitleEmpty;

  /// No description provided for @walletSubtitleCount.
  ///
  /// In zh_Hant, this message translates to:
  /// **'{count} 個憑證'**
  String walletSubtitleCount(int count);

  /// No description provided for @empty.
  ///
  /// In zh_Hant, this message translates to:
  /// **'空'**
  String get empty;

  /// No description provided for @sync.
  ///
  /// In zh_Hant, this message translates to:
  /// **'同步'**
  String get sync;

  /// No description provided for @syncSubtitle.
  ///
  /// In zh_Hant, this message translates to:
  /// **'Elix Relay 設定'**
  String get syncSubtitle;

  /// No description provided for @configured.
  ///
  /// In zh_Hant, this message translates to:
  /// **'設定'**
  String get configured;

  /// No description provided for @accessAudit.
  ///
  /// In zh_Hant, this message translates to:
  /// **'存取與審計'**
  String get accessAudit;

  /// No description provided for @accessAuditSubtitle.
  ///
  /// In zh_Hant, this message translates to:
  /// **'誰看見了哪一個我'**
  String get accessAuditSubtitle;

  /// No description provided for @noSuspiciousAccess.
  ///
  /// In zh_Hant, this message translates to:
  /// **'0 可疑'**
  String get noSuspiciousAccess;

  /// No description provided for @language.
  ///
  /// In zh_Hant, this message translates to:
  /// **'語言'**
  String get language;

  /// No description provided for @languageSubtitle.
  ///
  /// In zh_Hant, this message translates to:
  /// **'選擇 app 介面語言'**
  String get languageSubtitle;

  /// No description provided for @systemDefault.
  ///
  /// In zh_Hant, this message translates to:
  /// **'跟隨系統'**
  String get systemDefault;

  /// No description provided for @daily.
  ///
  /// In zh_Hant, this message translates to:
  /// **'日常 · DAILY'**
  String get daily;

  /// No description provided for @inbox.
  ///
  /// In zh_Hant, this message translates to:
  /// **'收信'**
  String get inbox;

  /// No description provided for @inboxSubtitle.
  ///
  /// In zh_Hant, this message translates to:
  /// **'圈內回覆、新成員、同步'**
  String get inboxSubtitle;

  /// No description provided for @notifications.
  ///
  /// In zh_Hant, this message translates to:
  /// **'通知'**
  String get notifications;

  /// No description provided for @notificationsSubtitle.
  ///
  /// In zh_Hant, this message translates to:
  /// **'決定哪些事會打擾你'**
  String get notificationsSubtitle;

  /// No description provided for @light.
  ///
  /// In zh_Hant, this message translates to:
  /// **'輕'**
  String get light;

  /// No description provided for @readingPreferences.
  ///
  /// In zh_Hant, this message translates to:
  /// **'閱讀偏好'**
  String get readingPreferences;

  /// No description provided for @readingPreferencesSubtitle.
  ///
  /// In zh_Hant, this message translates to:
  /// **'字級、行距、主題'**
  String get readingPreferencesSubtitle;

  /// No description provided for @defaultValue.
  ///
  /// In zh_Hant, this message translates to:
  /// **'預設'**
  String get defaultValue;

  /// No description provided for @boundaries.
  ///
  /// In zh_Hant, this message translates to:
  /// **'邊界 · BOUNDARIES'**
  String get boundaries;

  /// No description provided for @lock.
  ///
  /// In zh_Hant, this message translates to:
  /// **'鎖定'**
  String get lock;

  /// No description provided for @lockSubtitle.
  ///
  /// In zh_Hant, this message translates to:
  /// **'把 app 變成空白封面'**
  String get lockSubtitle;

  /// No description provided for @off.
  ///
  /// In zh_Hant, this message translates to:
  /// **'關閉'**
  String get off;

  /// No description provided for @backupRestore.
  ///
  /// In zh_Hant, this message translates to:
  /// **'備份與還原'**
  String get backupRestore;

  /// No description provided for @backupRestoreSubtitle.
  ///
  /// In zh_Hant, this message translates to:
  /// **'passphrase、新裝置遷移'**
  String get backupRestoreSubtitle;

  /// No description provided for @notSet.
  ///
  /// In zh_Hant, this message translates to:
  /// **'未設'**
  String get notSet;

  /// No description provided for @blockedList.
  ///
  /// In zh_Hant, this message translates to:
  /// **'封鎖名單'**
  String get blockedList;

  /// No description provided for @blockedListSubtitle.
  ///
  /// In zh_Hant, this message translates to:
  /// **'你看不到，他們也看不到你'**
  String get blockedListSubtitle;

  /// No description provided for @about.
  ///
  /// In zh_Hant, this message translates to:
  /// **'關於 Elix'**
  String get about;

  /// No description provided for @aboutSubtitle.
  ///
  /// In zh_Hant, this message translates to:
  /// **'信號越過星際的距離'**
  String get aboutSubtitle;

  /// No description provided for @manual.
  ///
  /// In zh_Hant, this message translates to:
  /// **'使用手冊'**
  String get manual;

  /// No description provided for @signOutDevice.
  ///
  /// In zh_Hant, this message translates to:
  /// **'登出此裝置'**
  String get signOutDevice;

  /// No description provided for @signOutSubtitle.
  ///
  /// In zh_Hant, this message translates to:
  /// **'保留資料；下次需要 passkey'**
  String get signOutSubtitle;

  /// No description provided for @languagePickerTitle.
  ///
  /// In zh_Hant, this message translates to:
  /// **'語言'**
  String get languagePickerTitle;

  /// No description provided for @languageSystemDescription.
  ///
  /// In zh_Hant, this message translates to:
  /// **'使用裝置的語言設定'**
  String get languageSystemDescription;

  /// No description provided for @feedAll.
  ///
  /// In zh_Hant, this message translates to:
  /// **'動態'**
  String get feedAll;

  /// No description provided for @feedFollowing.
  ///
  /// In zh_Hant, this message translates to:
  /// **'追蹤'**
  String get feedFollowing;

  /// No description provided for @feedBoards.
  ///
  /// In zh_Hant, this message translates to:
  /// **'看板'**
  String get feedBoards;

  /// No description provided for @searchBack.
  ///
  /// In zh_Hant, this message translates to:
  /// **'← 草地'**
  String get searchBack;

  /// No description provided for @clear.
  ///
  /// In zh_Hant, this message translates to:
  /// **'清除'**
  String get clear;

  /// No description provided for @searchHint.
  ///
  /// In zh_Hant, this message translates to:
  /// **'搜尋 murmur、筆記、討論'**
  String get searchHint;

  /// No description provided for @searchScopeAll.
  ///
  /// In zh_Hant, this message translates to:
  /// **'全部'**
  String get searchScopeAll;

  /// No description provided for @searchScopeMy.
  ///
  /// In zh_Hant, this message translates to:
  /// **'我的'**
  String get searchScopeMy;

  /// No description provided for @searchScopeCircle.
  ///
  /// In zh_Hant, this message translates to:
  /// **'圈內'**
  String get searchScopeCircle;

  /// No description provided for @searchScopePublic.
  ///
  /// In zh_Hant, this message translates to:
  /// **'公開'**
  String get searchScopePublic;

  /// No description provided for @searchResultCount.
  ///
  /// In zh_Hant, this message translates to:
  /// **'找到 {count} 處提及'**
  String searchResultCount(int count);

  /// No description provided for @searchSortRelevant.
  ///
  /// In zh_Hant, this message translates to:
  /// **'↓ 相關'**
  String get searchSortRelevant;

  /// No description provided for @notesSectionCount.
  ///
  /// In zh_Hant, this message translates to:
  /// **'筆記 · NOTES · {count}'**
  String notesSectionCount(int count);

  /// No description provided for @murmursSectionCount.
  ///
  /// In zh_Hant, this message translates to:
  /// **'碎念 · MURMURS · {count}'**
  String murmursSectionCount(int count);

  /// No description provided for @threadsSectionCount.
  ///
  /// In zh_Hant, this message translates to:
  /// **'討論串 · FORUM · {count}'**
  String threadsSectionCount(int count);

  /// No description provided for @noNotesYet.
  ///
  /// In zh_Hant, this message translates to:
  /// **'目前沒有筆記'**
  String get noNotesYet;

  /// No description provided for @noMatchingNotes.
  ///
  /// In zh_Hant, this message translates to:
  /// **'沒有符合的筆記'**
  String get noMatchingNotes;

  /// No description provided for @noMurmursYet.
  ///
  /// In zh_Hant, this message translates to:
  /// **'目前沒有碎念'**
  String get noMurmursYet;

  /// No description provided for @noMatchingMurmurs.
  ///
  /// In zh_Hant, this message translates to:
  /// **'沒有符合的碎念'**
  String get noMatchingMurmurs;

  /// No description provided for @noThreadsYet.
  ///
  /// In zh_Hant, this message translates to:
  /// **'目前沒有討論串'**
  String get noThreadsYet;

  /// No description provided for @noMatchingThreads.
  ///
  /// In zh_Hant, this message translates to:
  /// **'沒有符合的討論串'**
  String get noMatchingThreads;

  /// No description provided for @murmurTitle.
  ///
  /// In zh_Hant, this message translates to:
  /// **'MURMUR · 碎念'**
  String get murmurTitle;

  /// No description provided for @local.
  ///
  /// In zh_Hant, this message translates to:
  /// **'本地'**
  String get local;

  /// No description provided for @send.
  ///
  /// In zh_Hant, this message translates to:
  /// **'送出'**
  String get send;

  /// No description provided for @murmurPrompt.
  ///
  /// In zh_Hant, this message translates to:
  /// **'現在腦子裡\n有什麼半成形的東西嗎？'**
  String get murmurPrompt;

  /// No description provided for @murmurPrivateHint.
  ///
  /// In zh_Hant, this message translates to:
  /// **'一句話、一個直覺、一個還沒理順的問題都可以。沒人會看到。'**
  String get murmurPrivateHint;

  /// No description provided for @murmurSyncHint.
  ///
  /// In zh_Hant, this message translates to:
  /// **'一句話、一個直覺、一個還沒理順的問題都可以。這則會標記為可同步。'**
  String get murmurSyncHint;

  /// No description provided for @murmurInputHint.
  ///
  /// In zh_Hant, this message translates to:
  /// **'這幾個月一直在想的事情是'**
  String get murmurInputHint;

  /// No description provided for @murmurPrivateVisibilityHint.
  ///
  /// In zh_Hant, this message translates to:
  /// **'只給自己'**
  String get murmurPrivateVisibilityHint;

  /// No description provided for @murmurUnlistedVisibilityHint.
  ///
  /// In zh_Hant, this message translates to:
  /// **'不列出但可同步'**
  String get murmurUnlistedVisibilityHint;

  /// No description provided for @murmurPublicVisibilityHint.
  ///
  /// In zh_Hant, this message translates to:
  /// **'公開發布'**
  String get murmurPublicVisibilityHint;

  /// No description provided for @looseMurmurs.
  ///
  /// In zh_Hant, this message translates to:
  /// **'散落'**
  String get looseMurmurs;

  /// No description provided for @looseMurmursEmpty.
  ///
  /// In zh_Hant, this message translates to:
  /// **'送出的碎念會先留在這裡。'**
  String get looseMurmursEmpty;

  /// No description provided for @sent.
  ///
  /// In zh_Hant, this message translates to:
  /// **'已送出'**
  String get sent;

  /// No description provided for @deletedMurmur.
  ///
  /// In zh_Hant, this message translates to:
  /// **'已刪除碎念'**
  String get deletedMurmur;

  /// No description provided for @unused.
  ///
  /// In zh_Hant, this message translates to:
  /// **'未使用'**
  String get unused;

  /// No description provided for @referenceCount.
  ///
  /// In zh_Hant, this message translates to:
  /// **'{count} 篇引用'**
  String referenceCount(int count);

  /// No description provided for @search.
  ///
  /// In zh_Hant, this message translates to:
  /// **'搜尋'**
  String get search;

  /// No description provided for @settingsNav.
  ///
  /// In zh_Hant, this message translates to:
  /// **'設定'**
  String get settingsNav;

  /// No description provided for @publicIdentity.
  ///
  /// In zh_Hant, this message translates to:
  /// **'公開身分'**
  String get publicIdentity;

  /// No description provided for @murmurTab.
  ///
  /// In zh_Hant, this message translates to:
  /// **'碎念'**
  String get murmurTab;

  /// No description provided for @notesTab.
  ///
  /// In zh_Hant, this message translates to:
  /// **'筆記'**
  String get notesTab;

  /// No description provided for @discussionsTab.
  ///
  /// In zh_Hant, this message translates to:
  /// **'看板'**
  String get discussionsTab;

  /// No description provided for @discussionsTabCompact.
  ///
  /// In zh_Hant, this message translates to:
  /// **'看板'**
  String get discussionsTabCompact;

  /// No description provided for @networkOnline.
  ///
  /// In zh_Hant, this message translates to:
  /// **'已連線'**
  String get networkOnline;

  /// No description provided for @networkOffline.
  ///
  /// In zh_Hant, this message translates to:
  /// **'離線'**
  String get networkOffline;

  /// No description provided for @networkChecking.
  ///
  /// In zh_Hant, this message translates to:
  /// **'檢查中'**
  String get networkChecking;

  /// No description provided for @workingNotes.
  ///
  /// In zh_Hant, this message translates to:
  /// **'草地'**
  String get workingNotes;

  /// No description provided for @newest.
  ///
  /// In zh_Hant, this message translates to:
  /// **'最近'**
  String get newest;

  /// No description provided for @oldest.
  ///
  /// In zh_Hant, this message translates to:
  /// **'最舊'**
  String get oldest;

  /// No description provided for @newNote.
  ///
  /// In zh_Hant, this message translates to:
  /// **'新增筆記'**
  String get newNote;

  /// No description provided for @drawInAction.
  ///
  /// In zh_Hant, this message translates to:
  /// **'↗ 編入'**
  String get drawInAction;

  /// No description provided for @noLooseMurmursYet.
  ///
  /// In zh_Hant, this message translates to:
  /// **'還沒有散落的碎念。'**
  String get noLooseMurmursYet;

  /// No description provided for @lineage.
  ///
  /// In zh_Hant, this message translates to:
  /// **'來源 · LINEAGE'**
  String get lineage;

  /// No description provided for @noteCreated.
  ///
  /// In zh_Hant, this message translates to:
  /// **'已建立筆記'**
  String get noteCreated;

  /// No description provided for @cancel.
  ///
  /// In zh_Hant, this message translates to:
  /// **'取消'**
  String get cancel;

  /// No description provided for @draftLocal.
  ///
  /// In zh_Hant, this message translates to:
  /// **'草稿保留 · 本機'**
  String get draftLocal;

  /// No description provided for @editing.
  ///
  /// In zh_Hant, this message translates to:
  /// **'編輯中 · EDITING'**
  String get editing;

  /// No description provided for @noteTitleHint.
  ///
  /// In zh_Hant, this message translates to:
  /// **'筆記標題'**
  String get noteTitleHint;

  /// No description provided for @noteTitleRequired.
  ///
  /// In zh_Hant, this message translates to:
  /// **'請輸入標題'**
  String get noteTitleRequired;

  /// No description provided for @noteBodyHint.
  ///
  /// In zh_Hant, this message translates to:
  /// **'繼續寫下去，或從下方拖一個 murmur 進來……'**
  String get noteBodyHint;

  /// No description provided for @noteBodyRequired.
  ///
  /// In zh_Hant, this message translates to:
  /// **'請輸入內文'**
  String get noteBodyRequired;

  /// No description provided for @noteSubjectLabel.
  ///
  /// In zh_Hant, this message translates to:
  /// **'這篇 note'**
  String get noteSubjectLabel;

  /// No description provided for @drawIn.
  ///
  /// In zh_Hant, this message translates to:
  /// **'編入 · DRAW IN'**
  String get drawIn;

  /// No description provided for @noMurmursToDraw.
  ///
  /// In zh_Hant, this message translates to:
  /// **'還沒有可以編入的 murmur。'**
  String get noMurmursToDraw;

  /// No description provided for @noNotesDescription.
  ///
  /// In zh_Hant, this message translates to:
  /// **'碎念會先散落在本地；等它們慢慢靠近，再編成一篇筆記。'**
  String get noNotesDescription;

  /// No description provided for @noteUpdated.
  ///
  /// In zh_Hant, this message translates to:
  /// **'已更新筆記'**
  String get noteUpdated;

  /// No description provided for @visibilityUpdated.
  ///
  /// In zh_Hant, this message translates to:
  /// **'可見性已更新'**
  String get visibilityUpdated;

  /// No description provided for @lineageDescription.
  ///
  /// In zh_Hant, this message translates to:
  /// **'由 murmur 編成的筆記會在這裡保留來源。'**
  String get lineageDescription;

  /// No description provided for @notePrivateSummary.
  ///
  /// In zh_Hant, this message translates to:
  /// **'還沒讓任何人看見'**
  String get notePrivateSummary;

  /// No description provided for @noteNostrSummary.
  ///
  /// In zh_Hant, this message translates to:
  /// **'公開後會送到 Nostr Relay'**
  String get noteNostrSummary;

  /// No description provided for @noteActivityPubSummary.
  ///
  /// In zh_Hant, this message translates to:
  /// **'公開後會送到 ActivityPub relay'**
  String get noteActivityPubSummary;

  /// No description provided for @noteBothSummary.
  ///
  /// In zh_Hant, this message translates to:
  /// **'公開後會送到 Nostr Relay 與 ActivityPub Relay'**
  String get noteBothSummary;

  /// No description provided for @noteLocalPublicSummary.
  ///
  /// In zh_Hant, this message translates to:
  /// **'公開狀態，但暫不送出'**
  String get noteLocalPublicSummary;

  /// No description provided for @createDiscussion.
  ///
  /// In zh_Hant, this message translates to:
  /// **'建立討論'**
  String get createDiscussion;

  /// No description provided for @chooseHostedBoard.
  ///
  /// In zh_Hant, this message translates to:
  /// **'選擇看板'**
  String get chooseHostedBoard;

  /// No description provided for @hostedBoardMissing.
  ///
  /// In zh_Hant, this message translates to:
  /// **'請先加入或建立 Elix Relay 的看板'**
  String get hostedBoardMissing;

  /// No description provided for @hostedBoardRequired.
  ///
  /// In zh_Hant, this message translates to:
  /// **'請選擇看板'**
  String get hostedBoardRequired;

  /// No description provided for @titleLabel.
  ///
  /// In zh_Hant, this message translates to:
  /// **'標題'**
  String get titleLabel;

  /// No description provided for @discussionTitleHint.
  ///
  /// In zh_Hant, this message translates to:
  /// **'輸入討論標題'**
  String get discussionTitleHint;

  /// No description provided for @titleRequired.
  ///
  /// In zh_Hant, this message translates to:
  /// **'標題為必填'**
  String get titleRequired;

  /// No description provided for @contentLabel.
  ///
  /// In zh_Hant, this message translates to:
  /// **'內容'**
  String get contentLabel;

  /// No description provided for @discussionContentHint.
  ///
  /// In zh_Hant, this message translates to:
  /// **'輸入討論內容'**
  String get discussionContentHint;

  /// No description provided for @contentRequired.
  ///
  /// In zh_Hant, this message translates to:
  /// **'內容為必填'**
  String get contentRequired;

  /// No description provided for @create.
  ///
  /// In zh_Hant, this message translates to:
  /// **'建立'**
  String get create;

  /// No description provided for @uncategorized.
  ///
  /// In zh_Hant, this message translates to:
  /// **'未分類'**
  String get uncategorized;

  /// No description provided for @addForumHostFirst.
  ///
  /// In zh_Hant, this message translates to:
  /// **'請先在同步設定新增 Elix Relay。討論看板由 Elix Relay 建立。'**
  String get addForumHostFirst;

  /// No description provided for @syncedPublicCount.
  ///
  /// In zh_Hant, this message translates to:
  /// **'已同步 {count} 篇公開內容'**
  String syncedPublicCount(int count);

  /// No description provided for @publicQueuedRelayFailed.
  ///
  /// In zh_Hant, this message translates to:
  /// **'公開內容已排入同步，但 Relay 發佈失敗'**
  String get publicQueuedRelayFailed;

  /// No description provided for @noWritableNostrRelay.
  ///
  /// In zh_Hant, this message translates to:
  /// **'尚未設定可寫入的 Nostr Relay'**
  String get noWritableNostrRelay;

  /// No description provided for @syncFailedMessage.
  ///
  /// In zh_Hant, this message translates to:
  /// **'同步失敗：{error}'**
  String syncFailedMessage(String error);

  /// No description provided for @justNow.
  ///
  /// In zh_Hant, this message translates to:
  /// **'剛剛'**
  String get justNow;

  /// No description provided for @minutesAgo.
  ///
  /// In zh_Hant, this message translates to:
  /// **'{count} 分鐘前'**
  String minutesAgo(int count);

  /// No description provided for @hoursAgo.
  ///
  /// In zh_Hant, this message translates to:
  /// **'{count} 小時前'**
  String hoursAgo(int count);

  /// No description provided for @daysAgo.
  ///
  /// In zh_Hant, this message translates to:
  /// **'{count} 天前'**
  String daysAgo(int count);

  /// No description provided for @circleSection.
  ///
  /// In zh_Hant, this message translates to:
  /// **'圈 · CIRCLE'**
  String get circleSection;

  /// No description provided for @allActivity.
  ///
  /// In zh_Hant, this message translates to:
  /// **'全部動態'**
  String get allActivity;

  /// No description provided for @boardCount.
  ///
  /// In zh_Hant, this message translates to:
  /// **'{count} 看板'**
  String boardCount(int count);

  /// No description provided for @manageSubscriptions.
  ///
  /// In zh_Hant, this message translates to:
  /// **'管理訂閱'**
  String get manageSubscriptions;

  /// No description provided for @newPost.
  ///
  /// In zh_Hant, this message translates to:
  /// **'新貼文'**
  String get newPost;

  /// No description provided for @addBoardTooltip.
  ///
  /// In zh_Hant, this message translates to:
  /// **'新增看板'**
  String get addBoardTooltip;

  /// No description provided for @newDiscussion.
  ///
  /// In zh_Hant, this message translates to:
  /// **'新板上討論'**
  String get newDiscussion;

  /// No description provided for @createNewDiscussion.
  ///
  /// In zh_Hant, this message translates to:
  /// **'建立板上討論'**
  String get createNewDiscussion;

  /// No description provided for @boardsShort.
  ///
  /// In zh_Hant, this message translates to:
  /// **'看板'**
  String get boardsShort;

  /// No description provided for @manageBoardsShort.
  ///
  /// In zh_Hant, this message translates to:
  /// **'管理看板'**
  String get manageBoardsShort;

  /// No description provided for @aiAssistant.
  ///
  /// In zh_Hant, this message translates to:
  /// **'AI 助手'**
  String get aiAssistant;

  /// No description provided for @aiSummary.
  ///
  /// In zh_Hant, this message translates to:
  /// **'AI 摘要'**
  String get aiSummary;

  /// No description provided for @noPostsYet.
  ///
  /// In zh_Hant, this message translates to:
  /// **'目前沒有動態'**
  String get noPostsYet;

  /// No description provided for @subscribe.
  ///
  /// In zh_Hant, this message translates to:
  /// **'訂閱'**
  String get subscribe;

  /// No description provided for @discussionAreaTitle.
  ///
  /// In zh_Hant, this message translates to:
  /// **'動態'**
  String get discussionAreaTitle;

  /// No description provided for @feedSocialIdentitySubtitle.
  ///
  /// In zh_Hant, this message translates to:
  /// **'Note 與 Murmur 是個人版發文類型；追蹤你的人會在他們的 feed 上看到，訂閱的看板則帶入公共討論。'**
  String get feedSocialIdentitySubtitle;

  /// No description provided for @publicOpen.
  ///
  /// In zh_Hant, this message translates to:
  /// **'追蹤 + 看板'**
  String get publicOpen;

  /// No description provided for @noContentYet.
  ///
  /// In zh_Hant, this message translates to:
  /// **'（尚無內容）'**
  String get noContentYet;

  /// No description provided for @commentsCount.
  ///
  /// In zh_Hant, this message translates to:
  /// **'{count} 則留言'**
  String commentsCount(int count);

  /// No description provided for @manageBoards.
  ///
  /// In zh_Hant, this message translates to:
  /// **'管理看板'**
  String get manageBoards;

  /// No description provided for @noBoardsYet.
  ///
  /// In zh_Hant, this message translates to:
  /// **'目前沒有看板'**
  String get noBoardsYet;

  /// No description provided for @deleteBoard.
  ///
  /// In zh_Hant, this message translates to:
  /// **'刪除看板'**
  String get deleteBoard;

  /// No description provided for @deleteBoardConfirm.
  ///
  /// In zh_Hant, this message translates to:
  /// **'確定刪除「{title}」？此動作不可恢復。'**
  String deleteBoardConfirm(String title);

  /// No description provided for @delete.
  ///
  /// In zh_Hant, this message translates to:
  /// **'刪除'**
  String get delete;

  /// No description provided for @close.
  ///
  /// In zh_Hant, this message translates to:
  /// **'關閉'**
  String get close;

  /// No description provided for @addBoard.
  ///
  /// In zh_Hant, this message translates to:
  /// **'新增看板'**
  String get addBoard;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when language+script codes are specified.
  switch (locale.languageCode) {
    case 'zh':
      {
        switch (locale.scriptCode) {
          case 'Hant':
            return AppLocalizationsZhHant();
        }
        break;
      }
  }

  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
