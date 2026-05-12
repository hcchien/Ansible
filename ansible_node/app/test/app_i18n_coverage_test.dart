import 'package:ansible_node/l10n/app_localizations.dart';
import 'package:ansible_node/screens/credential_admin_screen.dart';
import 'package:ansible_node/screens/inbox_screen.dart';
import 'package:ansible_node/screens/murmur_screen.dart';
import 'package:ansible_node/screens/note_workspace_screen.dart';
import 'package:ansible_node/screens/search_screen.dart';
import 'package:ansible_node/screens/wallet_screen.dart';
import 'package:ansible_node/widgets/feed_filter_tabs.dart';
import 'package:ansible_node/widgets/thread_form_dialog.dart';
import 'package:ansible_store/ansible_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('primary non-settings screens use selected English locale', (
    tester,
  ) async {
    await _pumpLocalized(
      tester,
      const Column(
        children: [
          Expanded(child: SearchScreen()),
          SizedBox(height: 240, child: MurmurScreen(authorDid: 'did:test:me')),
          FeedFilterTabs(selected: FeedFilter.all, onChanged: _ignoreFilter),
        ],
      ),
      locale: const Locale('en'),
    );

    expect(find.text('Feed'), findsWidgets);
    expect(find.text('My'), findsOneWidget);
    expect(find.text('Public'), findsOneWidget);
    expect(find.text('Send'), findsOneWidget);
    expect(find.text('Local'), findsOneWidget);
    expect(find.text('Following'), findsOneWidget);
    expect(find.text('Boards'), findsOneWidget);
    expect(find.textContaining('Search murmurs'), findsOneWidget);

    expect(find.text('全部'), findsNothing);
    expect(find.text('送出'), findsNothing);
    expect(find.text('本地'), findsNothing);
  });

  testWidgets('notes workspace uses selected English locale', (tester) async {
    await _pumpLocalized(
      tester,
      const NoteWorkspaceScreen(authorDid: 'did:test:me'),
      locale: const Locale('en'),
    );

    expect(find.text('Working Notes'), findsOneWidget);
    expect(find.text('Newest'), findsOneWidget);
    expect(find.text('New Note'), findsOneWidget);
    expect(find.text('No notes yet'), findsOneWidget);
    expect(find.text('No loose murmurs yet.'), findsOneWidget);
    expect(find.text('Lineage'), findsOneWidget);

    expect(find.text('草地'), findsNothing);
    expect(find.text('新增筆記'), findsNothing);
    expect(find.text('還沒有筆記'), findsNothing);
  });

  testWidgets('discussion creation dialog uses selected English locale', (
    tester,
  ) async {
    final board = Board(
      id: 'board-1',
      slug: 'general',
      title: 'General',
      description: null,
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
    );

    await _pumpLocalized(
      tester,
      Builder(
        builder: (context) => TextButton(
          onPressed: () => showDialog<void>(
            context: context,
            builder: (_) => ThreadFormDialog(boards: [board]),
          ),
          child: const Text('Open'),
        ),
      ),
      locale: const Locale('en'),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('Create Discussion'), findsOneWidget);
    expect(find.text('Choose hosted board'), findsOneWidget);
    expect(find.text('Title'), findsOneWidget);
    expect(find.text('Content'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
    expect(find.text('Create'), findsOneWidget);

    expect(find.text('建立討論'), findsNothing);
    expect(find.text('選擇 hosted board'), findsNothing);
  });

  testWidgets('settings subpages use selected English locale', (tester) async {
    await _pumpLocalizedScreen(
      tester,
      const InboxScreen(),
      locale: const Locale('en'),
    );
    expect(find.text('No inbox items'), findsOneWidget);
    expect(find.text('目前沒有收信'), findsNothing);

    await _pumpLocalizedScreen(
      tester,
      WalletScreen(
        holderDid: 'did:plc:abcdefghijklmnop',
        repository: InMemoryWalletRepository(),
      ),
      locale: const Locale('en'),
    );
    await tester.pumpAndSettle();
    expect(find.text('Wallet'), findsOneWidget);
    expect(find.text('No credentials yet'), findsOneWidget);
    expect(find.text('錢包'), findsNothing);

    await _pumpLocalizedScreen(
      tester,
      const CredentialAdminScreen(),
      locale: const Locale('en'),
    );
    expect(find.text('No grant records yet'), findsOneWidget);
    expect(find.text('目前沒有授權紀錄'), findsNothing);
  });
}

void _ignoreFilter(FeedFilter value) {}

Future<void> _pumpLocalized(
  WidgetTester tester,
  Widget child, {
  required Locale locale,
}) {
  return tester.pumpWidget(
    MaterialApp(
      locale: locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: Scaffold(body: child),
    ),
  );
}

Future<void> _pumpLocalizedScreen(
  WidgetTester tester,
  Widget child, {
  required Locale locale,
}) {
  return tester.pumpWidget(
    MaterialApp(
      locale: locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: child,
    ),
  );
}
