import 'package:flutter/material.dart';

import '../../l10n/app_l10n.dart';
import '../../theme/ansible_design.dart';

/// First-launch swipe coachmark overlay (F·10).
class SwipeCoachmark extends StatefulWidget {
  const SwipeCoachmark({super.key, required this.onDismiss});
  final VoidCallback onDismiss;
  @override
  State<SwipeCoachmark> createState() => _SwipeCoachmarkState();
}

class _SwipeCoachmarkState extends State<SwipeCoachmark>
    with SingleTickerProviderStateMixin {
  late final AnimationController _handCtrl;
  late final Animation<double> _handX;

  @override
  void initState() {
    super.initState();
    _handCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _handX = Tween<double>(
      begin: 0,
      end: 24,
    ).animate(CurvedAnimation(parent: _handCtrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _handCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final ochreColor = dark ? AnsibleDesign.darkOchre : AnsibleDesign.ochre;
    final bgColor = dark
        ? AnsibleDesign.darkPaperElev
        : AnsibleDesign.paperElev;
    final inkColor = dark ? AnsibleDesign.darkInk : AnsibleDesign.ink;
    final faintColor = dark
        ? AnsibleDesign.darkInkFaint
        : AnsibleDesign.inkFaint;

    return Positioned.fill(
      child: Material(
        color: Colors.black.withValues(alpha: 0.45),
        child: Center(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 32),
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: ochreColor.withValues(alpha: 0.55),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedBuilder(
                  animation: _handX,
                  builder: (context, _) => Transform.translate(
                    offset: Offset(_handX.value, 0),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.touch_app_outlined,
                          color: ochreColor,
                          size: 28,
                        ),
                        const SizedBox(width: 6),
                        Icon(
                          Icons.arrow_forward_rounded,
                          color: ochreColor,
                          size: 20,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  context.uiCopy(
                    zh: '這裡是你的個人版。',
                    en: 'This is your personal board.',
                  ),
                  style: TextStyle(
                    fontFamily: AnsibleDesign.serif,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: inkColor,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  context.uiCopy(
                    zh: '想看別人？往左滑，或是點上面的「討論區」。',
                    en: 'Want to see others? Swipe left or tap Forum above.',
                  ),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: AnsibleDesign.serif,
                    fontSize: 13,
                    fontStyle: FontStyle.italic,
                    color: faintColor,
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: widget.onDismiss,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: faintColor,
                          side: BorderSide(
                            color: ochreColor.withValues(alpha: 0.4),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: Text(context.uiCopy(zh: '知道了', en: 'Got it')),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton(
                        onPressed: widget.onDismiss,
                        style: FilledButton.styleFrom(
                          backgroundColor: ochreColor,
                          foregroundColor: AnsibleDesign.paper,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          elevation: 0,
                        ),
                        child: Text(
                          context.uiCopy(zh: '試試看·滑一下', en: 'Try swiping'),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
