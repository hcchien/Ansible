import 'package:ansible_node/theme/ansible_design.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'light and dark themes share the Lavender Signal component contract',
    () {
      final light = AnsibleDesign.theme();
      final dark = AnsibleDesign.darkTheme();

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
    },
  );

  testWidgets('custom Elix wordmark remains accessible in both themes', (
    tester,
  ) async {
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
