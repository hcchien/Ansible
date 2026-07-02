part of 'settings_home_screen.dart';

class _InterfaceSettingsPanel extends StatefulWidget {
  const _InterfaceSettingsPanel({
    required this.text,
    required this.personalStyle,
    required this.forumStyle,
    required this.motion,
    this.onPersonalStyleChanged,
    this.onForumStyleChanged,
    this.onMotionChanged,
  });

  final _SettingsText text;
  final ElixScreenStyle personalStyle;
  final ElixScreenStyle forumStyle;
  final ElixBoardMotion motion;
  final ValueChanged<ElixScreenStyle>? onPersonalStyleChanged;
  final ValueChanged<ElixScreenStyle>? onForumStyleChanged;
  final ValueChanged<ElixBoardMotion>? onMotionChanged;

  @override
  State<_InterfaceSettingsPanel> createState() =>
      _InterfaceSettingsPanelState();
}

class _InterfaceSettingsPanelState extends State<_InterfaceSettingsPanel> {
  late ElixScreenStyle _personalStyle;
  late ElixScreenStyle _forumStyle;
  late ElixBoardMotion _motion;

  @override
  void initState() {
    super.initState();
    _personalStyle = widget.personalStyle;
    _forumStyle = widget.forumStyle;
    _motion = widget.motion;
  }

  @override
  void didUpdateWidget(covariant _InterfaceSettingsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.personalStyle != widget.personalStyle) {
      _personalStyle = widget.personalStyle;
    }
    if (oldWidget.forumStyle != widget.forumStyle) {
      _forumStyle = widget.forumStyle;
    }
    if (oldWidget.motion != widget.motion) {
      _motion = widget.motion;
    }
  }

  @override
  Widget build(BuildContext context) {
    final canEditStyles =
        widget.onPersonalStyleChanged != null ||
        widget.onForumStyleChanged != null;
    final canEditMotion = widget.onMotionChanged != null;

    return Container(
      padding: const EdgeInsets.fromLTRB(22, 15, 22, 16),
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: AnsibleDesign.ruleSoft, width: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _InterfacePanelHeading(
            title: widget.text.sceneLight,
            en: 'LIGHT',
            value: '${_personalStyle.label} / ${_forumStyle.label}',
          ),
          const SizedBox(height: 6),
          Text(
            widget.text.sceneLightSubtitle,
            style: const TextStyle(
              fontFamily: AnsibleDesign.serif,
              fontSize: 13,
              height: 1.5,
              color: AnsibleDesign.inkMuted,
            ),
          ),
          const SizedBox(height: 12),
          _SceneStylePicker(
            keyPrefix: 'personal',
            label: widget.text.personalBoard,
            selected: _personalStyle,
            enabled: canEditStyles,
            onSelected: (style) {
              setState(() => _personalStyle = style);
              widget.onPersonalStyleChanged?.call(style);
            },
          ),
          const SizedBox(height: 10),
          _SceneStylePicker(
            keyPrefix: 'forum',
            label: widget.text.forumBoard,
            selected: _forumStyle,
            enabled: canEditStyles,
            onSelected: (style) {
              setState(() => _forumStyle = style);
              widget.onForumStyleChanged?.call(style);
            },
          ),
          const SizedBox(height: 18),
          _InterfacePanelHeading(
            title: widget.text.boardMotion,
            en: 'MOTION',
            value: _motion.label,
          ),
          const SizedBox(height: 9),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final motion in ElixBoardMotion.values)
                _MotionChoice(
                  key: Key('settings_motion_${motion.name}'),
                  motion: motion,
                  selected: _motion == motion,
                  enabled: canEditMotion,
                  onTap: () {
                    setState(() => _motion = motion);
                    widget.onMotionChanged?.call(motion);
                  },
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _InterfacePanelHeading extends StatelessWidget {
  const _InterfacePanelHeading({
    required this.title,
    required this.en,
    required this.value,
  });

  final String title;
  final String en;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Wrap(
            spacing: 8,
            runSpacing: 2,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontFamily: AnsibleDesign.serif,
                  fontSize: 16,
                  color: AnsibleDesign.ink,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                en,
                style: const TextStyle(
                  fontFamily: AnsibleDesign.mono,
                  fontSize: 10,
                  letterSpacing: 1.4,
                  color: AnsibleDesign.inkFaint,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        Flexible(
          child: Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.right,
            style: const TextStyle(
              fontFamily: AnsibleDesign.sans,
              fontSize: 14,
              color: AnsibleDesign.inkMuted,
            ),
          ),
        ),
      ],
    );
  }
}

class _SceneStylePicker extends StatelessWidget {
  const _SceneStylePicker({
    required this.keyPrefix,
    required this.label,
    required this.selected,
    required this.enabled,
    required this.onSelected,
  });

  final String keyPrefix;
  final String label;
  final ElixScreenStyle selected;
  final bool enabled;
  final ValueChanged<ElixScreenStyle> onSelected;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 56,
          child: Text(
            label,
            style: const TextStyle(
              fontFamily: AnsibleDesign.sans,
              fontSize: 13,
              color: AnsibleDesign.inkMuted,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Row(
            children: [
              for (final style in ElixScreenStyle.values) ...[
                Expanded(
                  child: _StyleChoice(
                    key: Key(
                      'settings_style_choice_${keyPrefix}_${style.name}',
                    ),
                    style: style,
                    selected: selected == style,
                    enabled: enabled,
                    onTap: () => onSelected(style),
                  ),
                ),
                if (style != ElixScreenStyle.values.last)
                  const SizedBox(width: 7),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _StyleChoice extends StatelessWidget {
  const _StyleChoice({
    super.key,
    required this.style,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final ElixScreenStyle style;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final data = style.dataFor(Theme.of(context).brightness);
    // Auto previews as a half-Paper / half-Ink split, per the design's swatch.
    final auto = style == ElixScreenStyle.system;
    final previewColor = auto ? null : data.background;
    const autoGradient = LinearGradient(
      begin: Alignment.centerLeft,
      end: Alignment.centerRight,
      stops: [0.5, 0.5],
      colors: [AnsibleDesign.paper, AnsibleDesign.ink],
    );
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          // Opaque fill so the selection glow reads as an outer ring, not a
          // wash through the card.
          color: AnsibleDesign.paper,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? AnsibleDesign.ochre : AnsibleDesign.rule,
            width: 0.5,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: AnsibleDesign.ochre.withValues(alpha: 0.28),
                    spreadRadius: 1.5,
                  ),
                ]
              : null,
        ),
        child: Column(
          children: [
            Container(
              height: 30,
              decoration: BoxDecoration(
                color: previewColor,
                gradient: auto ? autoGradient : null,
                borderRadius: BorderRadius.circular(7),
                border: Border.all(color: AnsibleDesign.rule, width: 0.5),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              style.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: AnsibleDesign.sans,
                fontSize: 12.5,
                color: selected ? AnsibleDesign.ink : AnsibleDesign.inkMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MotionChoice extends StatelessWidget {
  const _MotionChoice({
    super.key,
    required this.motion,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final ElixBoardMotion motion;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(999),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
        decoration: BoxDecoration(
          color: selected
              ? AnsibleDesign.ochre.withValues(alpha: 0.14)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? AnsibleDesign.ochre : AnsibleDesign.rule,
            width: 0.5,
          ),
        ),
        child: Text(
          motion.label,
          style: TextStyle(
            fontFamily: AnsibleDesign.sans,
            fontSize: 14,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            color: selected ? AnsibleDesign.ochre : AnsibleDesign.inkMuted,
          ),
        ),
      ),
    );
  }
}

