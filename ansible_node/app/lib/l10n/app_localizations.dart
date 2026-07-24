import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_de.dart';
import 'app_localizations_en.dart';
import 'app_localizations_es.dart';
import 'app_localizations_fr.dart';
import 'app_localizations_it.dart';
import 'app_localizations_ja.dart';
import 'app_localizations_ko.dart';
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
    Locale('de'),
    Locale('en'),
    Locale('es'),
    Locale('fr'),
    Locale('it'),
    Locale('ja'),
    Locale('ko'),
    Locale('zh'),
    Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'Elix'**
  String get appTitle;

  /// No description provided for @settingsTitle.
  ///
  /// In en, this message translates to:
  /// **'SETTINGS'**
  String get settingsTitle;

  /// No description provided for @done.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get done;

  /// No description provided for @localIdentity.
  ///
  /// In en, this message translates to:
  /// **'Local Identity'**
  String get localIdentity;

  /// No description provided for @localDid.
  ///
  /// In en, this message translates to:
  /// **'Local DID'**
  String get localDid;

  /// No description provided for @edit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get edit;

  /// No description provided for @identityAndDevice.
  ///
  /// In en, this message translates to:
  /// **'Identity & Device'**
  String get identityAndDevice;

  /// No description provided for @wallet.
  ///
  /// In en, this message translates to:
  /// **'Wallet'**
  String get wallet;

  /// No description provided for @walletSubtitleEmpty.
  ///
  /// In en, this message translates to:
  /// **'No credentials'**
  String get walletSubtitleEmpty;

  /// No description provided for @walletSubtitleCount.
  ///
  /// In en, this message translates to:
  /// **'{count} credentials'**
  String walletSubtitleCount(int count);

  /// No description provided for @empty.
  ///
  /// In en, this message translates to:
  /// **'Empty'**
  String get empty;

  /// No description provided for @sync.
  ///
  /// In en, this message translates to:
  /// **'Sync'**
  String get sync;

  /// No description provided for @syncSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Elix Relay settings'**
  String get syncSubtitle;

  /// No description provided for @configured.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get configured;

  /// No description provided for @accessAudit.
  ///
  /// In en, this message translates to:
  /// **'Access & Audit'**
  String get accessAudit;

  /// No description provided for @accessAuditSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Who can see which identity'**
  String get accessAuditSubtitle;

  /// No description provided for @noSuspiciousAccess.
  ///
  /// In en, this message translates to:
  /// **'0 suspicious'**
  String get noSuspiciousAccess;

  /// No description provided for @language.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// No description provided for @languageSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Choose the app interface language'**
  String get languageSubtitle;

  /// No description provided for @systemDefault.
  ///
  /// In en, this message translates to:
  /// **'System default'**
  String get systemDefault;

  /// No description provided for @daily.
  ///
  /// In en, this message translates to:
  /// **'Daily'**
  String get daily;

  /// No description provided for @inbox.
  ///
  /// In en, this message translates to:
  /// **'Inbox'**
  String get inbox;

  /// No description provided for @inboxSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Circle replies, new members, sync'**
  String get inboxSubtitle;

  /// No description provided for @notifications.
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get notifications;

  /// No description provided for @notificationsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Decide what can interrupt you'**
  String get notificationsSubtitle;

  /// No description provided for @light.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get light;

  /// No description provided for @readingPreferences.
  ///
  /// In en, this message translates to:
  /// **'Reading Preferences'**
  String get readingPreferences;

  /// No description provided for @readingPreferencesSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Text size, line height, theme'**
  String get readingPreferencesSubtitle;

  /// No description provided for @defaultValue.
  ///
  /// In en, this message translates to:
  /// **'Default'**
  String get defaultValue;

  /// No description provided for @boundaries.
  ///
  /// In en, this message translates to:
  /// **'Boundaries'**
  String get boundaries;

  /// No description provided for @lock.
  ///
  /// In en, this message translates to:
  /// **'Lock'**
  String get lock;

  /// No description provided for @lockSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Turn the app into a blank cover'**
  String get lockSubtitle;

  /// No description provided for @off.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get off;

  /// No description provided for @backupRestore.
  ///
  /// In en, this message translates to:
  /// **'Backup & Restore'**
  String get backupRestore;

  /// No description provided for @backupRestoreSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Passphrase, new device migration'**
  String get backupRestoreSubtitle;

  /// No description provided for @notSet.
  ///
  /// In en, this message translates to:
  /// **'Not set'**
  String get notSet;

  /// No description provided for @blockedList.
  ///
  /// In en, this message translates to:
  /// **'Blocked List'**
  String get blockedList;

  /// No description provided for @blockedListSubtitle.
  ///
  /// In en, this message translates to:
  /// **'You cannot see them, and they cannot see you'**
  String get blockedListSubtitle;

  /// No description provided for @about.
  ///
  /// In en, this message translates to:
  /// **'About Elix'**
  String get about;

  /// No description provided for @aboutSubtitle.
  ///
  /// In en, this message translates to:
  /// **'A signal across stellar distance'**
  String get aboutSubtitle;

  /// No description provided for @manual.
  ///
  /// In en, this message translates to:
  /// **'Manual'**
  String get manual;

  /// No description provided for @signOutDevice.
  ///
  /// In en, this message translates to:
  /// **'Sign out of this device'**
  String get signOutDevice;

  /// No description provided for @signOutSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Keep data; passkey required next time'**
  String get signOutSubtitle;

  /// No description provided for @languagePickerTitle.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get languagePickerTitle;

  /// No description provided for @languageSystemDescription.
  ///
  /// In en, this message translates to:
  /// **'Use this device\'s language setting'**
  String get languageSystemDescription;

  /// No description provided for @feedAll.
  ///
  /// In en, this message translates to:
  /// **'Feed'**
  String get feedAll;

  /// No description provided for @feedFollowing.
  ///
  /// In en, this message translates to:
  /// **'Following'**
  String get feedFollowing;

  /// No description provided for @feedBoards.
  ///
  /// In en, this message translates to:
  /// **'Boards'**
  String get feedBoards;

  /// No description provided for @searchBack.
  ///
  /// In en, this message translates to:
  /// **'← Meadow'**
  String get searchBack;

  /// No description provided for @clear.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get clear;

  /// No description provided for @searchHint.
  ///
  /// In en, this message translates to:
  /// **'Search murmurs, notes, discussions'**
  String get searchHint;

  /// No description provided for @searchScopeAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get searchScopeAll;

  /// No description provided for @searchScopeMy.
  ///
  /// In en, this message translates to:
  /// **'My'**
  String get searchScopeMy;

  /// No description provided for @searchScopeCircle.
  ///
  /// In en, this message translates to:
  /// **'Circle'**
  String get searchScopeCircle;

  /// No description provided for @searchScopePublic.
  ///
  /// In en, this message translates to:
  /// **'Public'**
  String get searchScopePublic;

  /// No description provided for @searchResultCount.
  ///
  /// In en, this message translates to:
  /// **'Found {count} mentions'**
  String searchResultCount(int count);

  /// No description provided for @searchSortRelevant.
  ///
  /// In en, this message translates to:
  /// **'↓ Relevant'**
  String get searchSortRelevant;

  /// No description provided for @notesSectionCount.
  ///
  /// In en, this message translates to:
  /// **'Notes · {count}'**
  String notesSectionCount(int count);

  /// No description provided for @murmursSectionCount.
  ///
  /// In en, this message translates to:
  /// **'Murmurs · {count}'**
  String murmursSectionCount(int count);

  /// No description provided for @threadsSectionCount.
  ///
  /// In en, this message translates to:
  /// **'Threads · {count}'**
  String threadsSectionCount(int count);

  /// No description provided for @noNotesYet.
  ///
  /// In en, this message translates to:
  /// **'No notes yet'**
  String get noNotesYet;

  /// No description provided for @noMatchingNotes.
  ///
  /// In en, this message translates to:
  /// **'No matching notes'**
  String get noMatchingNotes;

  /// No description provided for @noMurmursYet.
  ///
  /// In en, this message translates to:
  /// **'No murmurs yet'**
  String get noMurmursYet;

  /// No description provided for @noMatchingMurmurs.
  ///
  /// In en, this message translates to:
  /// **'No matching murmurs'**
  String get noMatchingMurmurs;

  /// No description provided for @noThreadsYet.
  ///
  /// In en, this message translates to:
  /// **'No threads yet'**
  String get noThreadsYet;

  /// No description provided for @noMatchingThreads.
  ///
  /// In en, this message translates to:
  /// **'No matching threads'**
  String get noMatchingThreads;

  /// No description provided for @murmurTitle.
  ///
  /// In en, this message translates to:
  /// **'MURMUR'**
  String get murmurTitle;

  /// No description provided for @local.
  ///
  /// In en, this message translates to:
  /// **'Local'**
  String get local;

  /// No description provided for @send.
  ///
  /// In en, this message translates to:
  /// **'Send'**
  String get send;

  /// No description provided for @murmurPrompt.
  ///
  /// In en, this message translates to:
  /// **'What half-formed thing\nis on your mind?'**
  String get murmurPrompt;

  /// No description provided for @murmurPrivateHint.
  ///
  /// In en, this message translates to:
  /// **'A sentence, an instinct, an unresolved question all fit here. No one else will see it.'**
  String get murmurPrivateHint;

  /// No description provided for @murmurSyncHint.
  ///
  /// In en, this message translates to:
  /// **'A sentence, an instinct, an unresolved question all fit here. This one will be marked syncable.'**
  String get murmurSyncHint;

  /// No description provided for @murmurInputHint.
  ///
  /// In en, this message translates to:
  /// **'What I have been thinking about lately is'**
  String get murmurInputHint;

  /// No description provided for @murmurPrivateVisibilityHint.
  ///
  /// In en, this message translates to:
  /// **'Only for me'**
  String get murmurPrivateVisibilityHint;

  /// No description provided for @murmurUnlistedVisibilityHint.
  ///
  /// In en, this message translates to:
  /// **'Syncable but unlisted'**
  String get murmurUnlistedVisibilityHint;

  /// No description provided for @murmurPublicVisibilityHint.
  ///
  /// In en, this message translates to:
  /// **'Publish publicly'**
  String get murmurPublicVisibilityHint;

  /// No description provided for @looseMurmurs.
  ///
  /// In en, this message translates to:
  /// **'Loose'**
  String get looseMurmurs;

  /// No description provided for @looseMurmursEmpty.
  ///
  /// In en, this message translates to:
  /// **'Sent murmurs stay here first.'**
  String get looseMurmursEmpty;

  /// No description provided for @sent.
  ///
  /// In en, this message translates to:
  /// **'Sent'**
  String get sent;

  /// No description provided for @deletedMurmur.
  ///
  /// In en, this message translates to:
  /// **'Murmur deleted'**
  String get deletedMurmur;

  /// No description provided for @unused.
  ///
  /// In en, this message translates to:
  /// **'Unused'**
  String get unused;

  /// No description provided for @referenceCount.
  ///
  /// In en, this message translates to:
  /// **'{count} references'**
  String referenceCount(int count);

  /// No description provided for @search.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get search;

  /// No description provided for @settingsNav.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsNav;

  /// No description provided for @publicIdentity.
  ///
  /// In en, this message translates to:
  /// **'Public identity'**
  String get publicIdentity;

  /// No description provided for @murmurTab.
  ///
  /// In en, this message translates to:
  /// **'Murmur'**
  String get murmurTab;

  /// No description provided for @notesTab.
  ///
  /// In en, this message translates to:
  /// **'Notes'**
  String get notesTab;

  /// No description provided for @discussionsTab.
  ///
  /// In en, this message translates to:
  /// **'Boards'**
  String get discussionsTab;

  /// No description provided for @discussionsTabCompact.
  ///
  /// In en, this message translates to:
  /// **'Boards'**
  String get discussionsTabCompact;

  /// No description provided for @networkOnline.
  ///
  /// In en, this message translates to:
  /// **'Online'**
  String get networkOnline;

  /// No description provided for @networkOffline.
  ///
  /// In en, this message translates to:
  /// **'Offline'**
  String get networkOffline;

  /// No description provided for @networkChecking.
  ///
  /// In en, this message translates to:
  /// **'Checking'**
  String get networkChecking;

  /// No description provided for @workingNotes.
  ///
  /// In en, this message translates to:
  /// **'Working Notes'**
  String get workingNotes;

  /// No description provided for @newest.
  ///
  /// In en, this message translates to:
  /// **'Newest'**
  String get newest;

  /// No description provided for @oldest.
  ///
  /// In en, this message translates to:
  /// **'Oldest'**
  String get oldest;

  /// No description provided for @newNote.
  ///
  /// In en, this message translates to:
  /// **'New Note'**
  String get newNote;

  /// No description provided for @drawInAction.
  ///
  /// In en, this message translates to:
  /// **'↗ Draw in'**
  String get drawInAction;

  /// No description provided for @noLooseMurmursYet.
  ///
  /// In en, this message translates to:
  /// **'No loose murmurs yet.'**
  String get noLooseMurmursYet;

  /// No description provided for @lineage.
  ///
  /// In en, this message translates to:
  /// **'Lineage'**
  String get lineage;

  /// No description provided for @noteCreated.
  ///
  /// In en, this message translates to:
  /// **'Note created'**
  String get noteCreated;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @draftLocal.
  ///
  /// In en, this message translates to:
  /// **'Draft stays local'**
  String get draftLocal;

  /// No description provided for @editing.
  ///
  /// In en, this message translates to:
  /// **'Editing'**
  String get editing;

  /// No description provided for @noteTitleHint.
  ///
  /// In en, this message translates to:
  /// **'Note title'**
  String get noteTitleHint;

  /// No description provided for @noteTitleRequired.
  ///
  /// In en, this message translates to:
  /// **'Enter a title'**
  String get noteTitleRequired;

  /// No description provided for @noteBodyHint.
  ///
  /// In en, this message translates to:
  /// **'Keep writing, or drag a murmur in from below...'**
  String get noteBodyHint;

  /// No description provided for @noteBodyRequired.
  ///
  /// In en, this message translates to:
  /// **'Enter note body'**
  String get noteBodyRequired;

  /// No description provided for @noteSubjectLabel.
  ///
  /// In en, this message translates to:
  /// **'this note'**
  String get noteSubjectLabel;

  /// No description provided for @drawIn.
  ///
  /// In en, this message translates to:
  /// **'Draw in'**
  String get drawIn;

  /// No description provided for @noMurmursToDraw.
  ///
  /// In en, this message translates to:
  /// **'No murmurs to draw in yet.'**
  String get noMurmursToDraw;

  /// No description provided for @noNotesDescription.
  ///
  /// In en, this message translates to:
  /// **'Murmurs stay loose locally first; when they start to connect, shape them into a note.'**
  String get noNotesDescription;

  /// No description provided for @noteUpdated.
  ///
  /// In en, this message translates to:
  /// **'Note updated'**
  String get noteUpdated;

  /// No description provided for @visibilityUpdated.
  ///
  /// In en, this message translates to:
  /// **'Visibility updated'**
  String get visibilityUpdated;

  /// No description provided for @lineageDescription.
  ///
  /// In en, this message translates to:
  /// **'Notes shaped from murmurs keep their source lineage here.'**
  String get lineageDescription;

  /// No description provided for @notePrivateSummary.
  ///
  /// In en, this message translates to:
  /// **'No one else can see this yet'**
  String get notePrivateSummary;

  /// No description provided for @noteNostrSummary.
  ///
  /// In en, this message translates to:
  /// **'Publishing sends this to Nostr relays'**
  String get noteNostrSummary;

  /// No description provided for @noteActivityPubSummary.
  ///
  /// In en, this message translates to:
  /// **'Publishing sends this to the ActivityPub relay'**
  String get noteActivityPubSummary;

  /// No description provided for @noteBothSummary.
  ///
  /// In en, this message translates to:
  /// **'Publishing sends this to Nostr relays and the ActivityPub relay'**
  String get noteBothSummary;

  /// No description provided for @noteLocalPublicSummary.
  ///
  /// In en, this message translates to:
  /// **'Public state, but not sent yet'**
  String get noteLocalPublicSummary;

  /// No description provided for @createDiscussion.
  ///
  /// In en, this message translates to:
  /// **'Create Discussion'**
  String get createDiscussion;

  /// No description provided for @chooseHostedBoard.
  ///
  /// In en, this message translates to:
  /// **'Choose board'**
  String get chooseHostedBoard;

  /// No description provided for @hostedBoardMissing.
  ///
  /// In en, this message translates to:
  /// **'Join or create an Elix Relay board first'**
  String get hostedBoardMissing;

  /// No description provided for @hostedBoardRequired.
  ///
  /// In en, this message translates to:
  /// **'Choose a board'**
  String get hostedBoardRequired;

  /// No description provided for @titleLabel.
  ///
  /// In en, this message translates to:
  /// **'Title'**
  String get titleLabel;

  /// No description provided for @discussionTitleHint.
  ///
  /// In en, this message translates to:
  /// **'Enter discussion title'**
  String get discussionTitleHint;

  /// No description provided for @titleRequired.
  ///
  /// In en, this message translates to:
  /// **'Title is required'**
  String get titleRequired;

  /// No description provided for @contentLabel.
  ///
  /// In en, this message translates to:
  /// **'Content'**
  String get contentLabel;

  /// No description provided for @discussionContentHint.
  ///
  /// In en, this message translates to:
  /// **'Enter discussion content'**
  String get discussionContentHint;

  /// No description provided for @contentRequired.
  ///
  /// In en, this message translates to:
  /// **'Content is required'**
  String get contentRequired;

  /// No description provided for @create.
  ///
  /// In en, this message translates to:
  /// **'Create'**
  String get create;

  /// No description provided for @uncategorized.
  ///
  /// In en, this message translates to:
  /// **'Uncategorized'**
  String get uncategorized;

  /// No description provided for @addForumHostFirst.
  ///
  /// In en, this message translates to:
  /// **'Add an Elix Relay in Sync settings first. Discussion boards are created by Elix Relays.'**
  String get addForumHostFirst;

  /// No description provided for @syncedPublicCount.
  ///
  /// In en, this message translates to:
  /// **'Synced {count} public items'**
  String syncedPublicCount(int count);

  /// No description provided for @publicQueuedRelayFailed.
  ///
  /// In en, this message translates to:
  /// **'Public content was queued, but relay publishing failed'**
  String get publicQueuedRelayFailed;

  /// No description provided for @noWritableNostrRelay.
  ///
  /// In en, this message translates to:
  /// **'No writable Nostr relay is configured'**
  String get noWritableNostrRelay;

  /// No description provided for @syncFailedMessage.
  ///
  /// In en, this message translates to:
  /// **'Sync failed: {error}'**
  String syncFailedMessage(String error);

  /// No description provided for @justNow.
  ///
  /// In en, this message translates to:
  /// **'Just now'**
  String get justNow;

  /// No description provided for @minutesAgo.
  ///
  /// In en, this message translates to:
  /// **'{count} minutes ago'**
  String minutesAgo(int count);

  /// No description provided for @hoursAgo.
  ///
  /// In en, this message translates to:
  /// **'{count} hours ago'**
  String hoursAgo(int count);

  /// No description provided for @daysAgo.
  ///
  /// In en, this message translates to:
  /// **'{count} days ago'**
  String daysAgo(int count);

  /// No description provided for @circleSection.
  ///
  /// In en, this message translates to:
  /// **'Circle'**
  String get circleSection;

  /// No description provided for @allActivity.
  ///
  /// In en, this message translates to:
  /// **'All Activity'**
  String get allActivity;

  /// No description provided for @boardCount.
  ///
  /// In en, this message translates to:
  /// **'{count} boards'**
  String boardCount(int count);

  /// No description provided for @manageSubscriptions.
  ///
  /// In en, this message translates to:
  /// **'Manage Subscriptions'**
  String get manageSubscriptions;

  /// No description provided for @newPost.
  ///
  /// In en, this message translates to:
  /// **'New Post'**
  String get newPost;

  /// No description provided for @addBoardTooltip.
  ///
  /// In en, this message translates to:
  /// **'Add Board'**
  String get addBoardTooltip;

  /// No description provided for @newDiscussion.
  ///
  /// In en, this message translates to:
  /// **'New Board Thread'**
  String get newDiscussion;

  /// No description provided for @createNewDiscussion.
  ///
  /// In en, this message translates to:
  /// **'Create Board Thread'**
  String get createNewDiscussion;

  /// No description provided for @boardsShort.
  ///
  /// In en, this message translates to:
  /// **'Boards'**
  String get boardsShort;

  /// No description provided for @manageBoardsShort.
  ///
  /// In en, this message translates to:
  /// **'Manage Boards'**
  String get manageBoardsShort;

  /// No description provided for @aiAssistant.
  ///
  /// In en, this message translates to:
  /// **'AI Assistant'**
  String get aiAssistant;

  /// No description provided for @aiSummary.
  ///
  /// In en, this message translates to:
  /// **'AI Summary'**
  String get aiSummary;

  /// No description provided for @noPostsYet.
  ///
  /// In en, this message translates to:
  /// **'No feed posts yet'**
  String get noPostsYet;

  /// No description provided for @subscribe.
  ///
  /// In en, this message translates to:
  /// **'Subscribe'**
  String get subscribe;

  /// No description provided for @discussionAreaTitle.
  ///
  /// In en, this message translates to:
  /// **'Feed'**
  String get discussionAreaTitle;

  /// No description provided for @feedSocialIdentitySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Notes and Murmurs are personal posts. People who follow you see them in their feed; boards add shared discussions.'**
  String get feedSocialIdentitySubtitle;

  /// No description provided for @publicOpen.
  ///
  /// In en, this message translates to:
  /// **'People + Boards'**
  String get publicOpen;

  /// No description provided for @noContentYet.
  ///
  /// In en, this message translates to:
  /// **'(No content yet)'**
  String get noContentYet;

  /// No description provided for @commentsCount.
  ///
  /// In en, this message translates to:
  /// **'{count} comments'**
  String commentsCount(int count);

  /// No description provided for @manageBoards.
  ///
  /// In en, this message translates to:
  /// **'Manage Boards'**
  String get manageBoards;

  /// No description provided for @noBoardsYet.
  ///
  /// In en, this message translates to:
  /// **'No boards yet'**
  String get noBoardsYet;

  /// No description provided for @deleteBoard.
  ///
  /// In en, this message translates to:
  /// **'Delete Board'**
  String get deleteBoard;

  /// No description provided for @deleteBoardConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete \"{title}\"? This cannot be undone.'**
  String deleteBoardConfirm(String title);

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @close.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// No description provided for @addBoard.
  ///
  /// In en, this message translates to:
  /// **'Add Board'**
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
  bool isSupported(Locale locale) => <String>[
    'de',
    'en',
    'es',
    'fr',
    'it',
    'ja',
    'ko',
    'zh',
  ].contains(locale.languageCode);

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
    case 'de':
      return AppLocalizationsDe();
    case 'en':
      return AppLocalizationsEn();
    case 'es':
      return AppLocalizationsEs();
    case 'fr':
      return AppLocalizationsFr();
    case 'it':
      return AppLocalizationsIt();
    case 'ja':
      return AppLocalizationsJa();
    case 'ko':
      return AppLocalizationsKo();
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
