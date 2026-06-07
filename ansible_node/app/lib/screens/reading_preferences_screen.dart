import 'package:flutter/material.dart';

import '../l10n/subpage_l10n.dart';
import '../services/reading_preferences_controller.dart';
import '../theme/ansible_design.dart';
import '../widgets/ansible_screen_chrome.dart';

class ReadingPreferencesScreen extends StatefulWidget {
  const ReadingPreferencesScreen({super.key, this.controller});

  final ReadingPreferencesController? controller;

  @override
  State<ReadingPreferencesScreen> createState() =>
      _ReadingPreferencesScreenState();
}

class _ReadingPreferencesScreenState extends State<ReadingPreferencesScreen> {
  late final ReadingPreferencesController _controller;
  late final bool _ownsController;

  @override
  void initState() {
    super.initState();
    _controller = widget.controller ?? ReadingPreferencesController();
    _ownsController = widget.controller == null;
    _controller.load();
  }

  @override
  void dispose() {
    if (_ownsController) {
      _controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = SubpageL10n.of(context);
    return AnsibleScreenScaffold(
      title: text.t('readingPreferencesTitleCaps'),
      leadingLabel: text.t('backSettings'),
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return ListView(
            padding: const EdgeInsets.fromLTRB(22, 0, 22, 32),
            children: [
              AnsibleMonoLabel(text.t('readingPreferencesLabel')),
              const SizedBox(height: 8),
              _ReadingPreview(scale: _controller.textScaleFactor),
              const SizedBox(height: 22),
              AnsibleMonoLabel(text.t('readingTextSizeLabel')),
              const SizedBox(height: 8),
              AnsibleRuleGroup(
                children: [
                  for (
                    var i = 0;
                    i < ReadingTextScalePreference.values.length;
                    i += 1
                  )
                    _ReadingScaleRow(
                      preference: ReadingTextScalePreference.values[i],
                      selected:
                          _controller.textScale ==
                          ReadingTextScalePreference.values[i],
                      last: i == ReadingTextScalePreference.values.length - 1,
                      onTap: () => _controller.setTextScale(
                        ReadingTextScalePreference.values[i],
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 22),
              AnsibleMonoLabel(text.t('readingLayoutLabel')),
              const SizedBox(height: 8),
              AnsibleRuleGroup(
                children: [
                  AnsibleSettingsRow(
                    glyph: '↕',
                    label: text.t('readingLineHeight'),
                    en: 'LINE HEIGHT',
                    value: text.t('readingStandard'),
                  ),
                  AnsibleSettingsRow(
                    glyph: '◐',
                    label: text.t('readingTheme'),
                    en: 'THEME',
                    value: text.t('readingFollowsApp'),
                    last: true,
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ReadingPreview extends StatelessWidget {
  const _ReadingPreview({required this.scale});

  final double scale;

  @override
  Widget build(BuildContext context) {
    final text = SubpageL10n.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: AnsibleDesign.paperElev,
        border: Border.all(color: AnsibleDesign.ruleSoft, width: 0.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text.t('readingPreviewBody'),
        style: TextStyle(
          fontSize: 16 * scale,
          height: 1.6,
          color: AnsibleDesign.ink,
        ),
      ),
    );
  }
}

class _ReadingScaleRow extends StatelessWidget {
  const _ReadingScaleRow({
    required this.preference,
    required this.selected,
    required this.onTap,
    this.last = false,
  });

  final ReadingTextScalePreference preference;
  final bool selected;
  final VoidCallback onTap;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final text = SubpageL10n.of(context);
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 13),
        decoration: BoxDecoration(
          border: Border(
            bottom: last
                ? BorderSide.none
                : const BorderSide(color: AnsibleDesign.ruleSoft, width: 0.5),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                _scaleLabel(text, preference),
                style: const TextStyle(
                  fontSize: 14,
                  color: AnsibleDesign.ink,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            Text(
              '${(preference.scale * 100).round()}%',
              style: const TextStyle(
                fontFamily: AnsibleDesign.mono,
                fontSize: 11,
                letterSpacing: 1.2,
                color: AnsibleDesign.inkMuted,
              ),
            ),
            const SizedBox(width: 12),
            Icon(
              selected ? Icons.check_circle : Icons.circle_outlined,
              size: 18,
              color: selected ? AnsibleDesign.accent : AnsibleDesign.inkFaint,
            ),
          ],
        ),
      ),
    );
  }

  String _scaleLabel(SubpageL10n text, ReadingTextScalePreference preference) {
    return switch (preference) {
      ReadingTextScalePreference.small => text.t('readingSmall'),
      ReadingTextScalePreference.standard => text.t('readingStandard'),
      ReadingTextScalePreference.large => text.t('readingLarge'),
      ReadingTextScalePreference.extraLarge => text.t('readingExtraLarge'),
    };
  }
}
