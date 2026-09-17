import 'dart:io';
import 'dart:ui' as ui;

import 'package:ansible_node/screens/home/circle_full_screen.dart';
import 'package:ansible_node/screens/home/home_types.dart';
import 'package:ansible_node/screens/follow_connections_screen.dart';
import 'package:ansible_node/services/handle_resolver.dart';
import 'package:ansible_node/theme/ansible_design.dart';
import 'package:ansible_node/widgets/note_markdown_text.dart';
import 'package:ansible_store/ansible_store.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

const _previewDir = String.fromEnvironment('APPEARANCE_PREVIEW_DIR');

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  for (final width in [390.0, 1000.0]) {
    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      testWidgets('personal pages use ${mode.name} palette at $width px', (
        tester,
      ) async {
        tester.view.physicalSize = Size(width, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        // An explicit app choice must override the opposite OS appearance.
        tester.platformDispatcher.platformBrightnessTestValue =
            mode == ThemeMode.light ? Brightness.dark : Brightness.light;
        addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
        if (_previewDir.isNotEmpty) {
          for (final entry in {
            'Noto Sans TC': 'assets/fonts/NotoSansTC-400.ttf',
            'Noto Serif TC': 'assets/fonts/NotoSerifTC-400.ttf',
            'MaterialIcons': 'fonts/MaterialIcons-Regular.otf',
            'JetBrains Mono': 'assets/fonts/JetBrainsMono-Regular.ttf',
          }.entries) {
            await (FontLoader(
              entry.key,
            )..addFont(rootBundle.load(entry.value))).load();
          }
        }
        final dark = mode == ThemeMode.dark;
        final foreground = dark ? AnsibleDesign.darkInk : AnsibleDesign.ink;
        final muted = dark
            ? AnsibleDesign.darkInkMuted
            : AnsibleDesign.inkMuted;
        final surface = dark
            ? AnsibleDesign.darkPaperElev
            : AnsibleDesign.paperElev;
        final db = AppDatabase(NativeDatabase.memory());
        addTearDown(db.close);
        final repository = InMemoryContentItemRepository();
        final now = DateTime.utc(2026, 9, 17);
        final note = ContentItem(
          id: 'note',
          authorDid: 'did:elix:owner',
          mode: ContentMode.note,
          title: '讓想法慢慢成形',
          body: '這是一篇筆記，記下今天的觀察。\n> 從片段整理出新的方向。',
          status: ContentStatus.active,
          visibility: ContentVisibility.private,
          createdAt: now,
          updatedAt: now,
        );
        final murmur = ContentItem(
          id: 'murmur',
          authorDid: 'did:elix:owner',
          mode: ContentMode.murmur,
          body: '這幾個月一直在想的事情是……',
          status: ContentStatus.active,
          visibility: ContentVisibility.private,
          createdAt: now,
          updatedAt: now,
        );
        final boundary = GlobalKey();
        Future<void> show(Widget child) async {
          await tester.pumpWidget(
            RepaintBoundary(
              key: boundary,
              child: MaterialApp(
                theme: AnsibleDesign.theme(),
                darkTheme: AnsibleDesign.darkTheme(),
                themeMode: mode,
                debugShowCheckedModeBanner: false,
                home: child,
              ),
            ),
          );
          await tester.pumpAndSettle();
        }

        Future<void> capture(String name) async {
          if (_previewDir.isEmpty || width != 390) return;
          final render =
              boundary.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary;
          await tester.runAsync(() async {
            final image = await render.toImage(pixelRatio: 2);
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            image.dispose();
            await Directory(_previewDir).create(recursive: true);
            await File(
              '$_previewDir/$name-${mode.name}.png',
            ).writeAsBytes(bytes!.buffer.asUint8List());
          });
        }

        for (final tab in [CircleTab.notes, CircleTab.murmur]) {
          await show(
            CircleFullScreen(
              key: ValueKey(tab),
              did: 'did:elix:owner',
              db: db,
              initialTab: tab,
              contentItems: [note, murmur],
              contentItemRepository: repository,
              murmurReferenceCounts: const {},
              onContentItemsChanged: () async {},
              onPublishContentItem: (_, _) async {},
              onSummonAiForNote: ({noteId, noteTitle, noteBody}) async {},
              openNoteEditorOnStart: false,
            ),
          );
          if (tab == CircleTab.notes) {
            expect(
              tester.widget<Text>(find.text(note.title!)).style?.color,
              foreground,
            );
            final markdown = tester.widget<NoteMarkdownBody>(
              find.byType(NoteMarkdownBody),
            );
            expect(markdown.style.color, muted);
            final lineage = find.text('由 murmur 編成的筆記會在這裡保留來源。');
            expect(tester.widget<Text>(lineage).style?.color, muted);
          } else {
            final field = find.byKey(const Key('murmur_body_field'));
            expect(tester.widget<TextField>(field).style?.color, foreground);
            final editable = tester.widget<EditableText>(
              find.byType(EditableText),
            );
            expect(
              editable.keyboardAppearance,
              dark ? Brightness.dark : Brightness.light,
            );
            final container = tester.widget<Container>(
              find.ancestor(of: field, matching: find.byType(Container)).first,
            );
            expect((container.decoration! as BoxDecoration).color, surface);
            await tester.enterText(field, '這幾個月一直在想的事情是');
            await tester.pumpAndSettle();
          }
          await capture(tab == CircleTab.notes ? 'note' : 'murmur');
          expect(tester.takeException(), isNull);
        }
        final follows = DriftFollowRepository(db);
        for (var i = 0; i < 3; i++) {
          final did = 'did:elix:peer000000000000000000$i';
          await follows.upsertTarget(
            FollowTarget(
              targetId: did,
              targetType: FollowTargetType.user,
              canonicalUri: did,
              did: did,
              displayName: did,
              createdAt: now,
              updatedAt: now,
            ),
          );
          await follows.upsertEdge(
            FollowEdge(
              followId: '$i',
              followerDid: 'did:elix:owner',
              targetId: did,
              targetType: FollowTargetType.user,
              direction: FollowDirection.outbound,
              status: FollowStatus.accepted,
              visibility: FollowVisibility.localOnly,
              createdAt: now,
              updatedAt: now,
            ),
          );
        }
        await show(
          FollowConnectionsScreen(
            db: db,
            did: 'did:elix:owner',
            profileResolver: _PreviewProfiles(),
          ),
        );
        expect(find.text('小草'), findsOneWidget);
        expect(find.text('@field.elix.cool'), findsOneWidget);
        expect(
          find.text(shortenDid('did:elix:peer0000000000000000002')),
          findsOneWidget,
        );
        expect(
          Theme.of(
            tester.element(find.byType(FollowConnectionsScreen)),
          ).brightness,
          dark ? Brightness.dark : Brightness.light,
        );
        await capture('following');
        expect(tester.takeException(), isNull);
      });
    }
  }
}

class _PreviewProfiles extends PublicProfileResolver {
  @override
  Future<PublicAuthorProfile?> profileFor(
    String did, {
    bool refresh = false,
  }) async {
    if (did.endsWith('0')) {
      return const PublicAuthorProfile(
        displayName: '小草',
        handle: 'grass.elix.cool',
      );
    }
    if (did.endsWith('1')) {
      return const PublicAuthorProfile(handle: 'field.elix.cool');
    }
    return null;
  }
}
