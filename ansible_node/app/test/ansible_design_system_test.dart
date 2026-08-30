import 'package:ansible_node/theme/ansible_design.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('light and dark themes share the Forest Letter component contract', () {
    final light = AnsibleDesign.theme();
    final dark = AnsibleDesign.darkTheme();

    expect(AnsibleDesign.paper, const Color(0xFFF4F3EC));
    expect(AnsibleDesign.ink, const Color(0xFF2A2A0A));
    expect(AnsibleDesign.accent, const Color(0xFFC9AEEB));
    expect(AnsibleDesign.moss, const Color(0xFF6FB2E8));
    expect(AnsibleDesign.highlight, const Color(0xFFEBE21C));
    expect(AnsibleDesign.darkPaper, const Color(0xFF17130A));
    expect(AnsibleDesign.darkOchre, const Color(0xFFD9C6F2));
    expect(light.scaffoldBackgroundColor, AnsibleDesign.paper);
    expect(dark.scaffoldBackgroundColor, AnsibleDesign.darkPaper);
    expect(light.colorScheme.secondary, AnsibleDesign.accent);
    expect(dark.colorScheme.secondary, AnsibleDesign.darkOchre);
    expect(light.colorScheme.onSecondary, AnsibleDesign.ink);
    expect(dark.colorScheme.onSecondary, AnsibleDesign.darkPaper);
    expect(light.textTheme.bodyMedium?.fontFamily, AnsibleDesign.serif);
    expect(dark.textTheme.bodyMedium?.fontFamily, AnsibleDesign.serif);
    expect(light.textTheme.labelLarge?.fontFamily, AnsibleDesign.sans);
    expect(dark.textTheme.labelLarge?.fontFamily, AnsibleDesign.sans);
    expect(light.cardTheme.elevation, 0);
    expect(dark.cardTheme.elevation, 0);
    expect(
      light.filledButtonTheme.style?.backgroundColor?.resolve({}),
      AnsibleDesign.ink,
    );
    expect(
      dark.filledButtonTheme.style?.backgroundColor?.resolve({}),
      AnsibleDesign.darkInk,
    );
    expect(light.floatingActionButtonTheme.elevation, 0);
    expect(dark.floatingActionButtonTheme.elevation, 0);
    expect(light.appBarTheme.centerTitle, isTrue);
    expect(dark.appBarTheme.centerTitle, isTrue);
    expect(
      (light.cardTheme.shape! as RoundedRectangleBorder).borderRadius,
      BorderRadius.circular(AnsibleDesign.cardRadius),
    );
  });

  testWidgets('Elix wordmark remains visible and accessible', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AnsibleDesign.theme(),
        darkTheme: AnsibleDesign.darkTheme(),
        home: const Scaffold(body: ElixWordmark()),
      ),
    );

    expect(find.byType(CustomPaint), findsWidgets);
    expect(find.bySemanticsLabel('Elix'), findsOneWidget);
  });
}
