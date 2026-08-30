import 'package:flutter/material.dart';

import '../l10n/app_l10n.dart';
import '../theme/ansible_design.dart';

/// Section A (onboarding) intro flow from the Elix Screens design: Welcome (A·01)
/// and Promise (A·02). Leads into the passkey registration screen ("first key",
/// A·03). Editorial styling: serif headings/body, mono small-caps labels, the
/// constellation mark + wordmark, dark pill CTA.
class OnboardingIntroScreen extends StatefulWidget {
  const OnboardingIntroScreen({
    super.key,
    required this.onContinue,
    this.reviewPublicContent,
  });

  /// Called when the user finishes the intro — the host shows the passkey
  /// registration screen next.
  final VoidCallback onContinue;

  /// Present only in the specially built Google Play review artifact. This
  /// opens a public, read-only surface and never creates an identity.
  final VoidCallback? reviewPublicContent;

  @override
  State<OnboardingIntroScreen> createState() => _OnboardingIntroScreenState();
}

class _OnboardingIntroScreenState extends State<OnboardingIntroScreen> {
  // Onboarding follows the app theme; these used to be fixed Paper constants,
  // which left the screen light under the Ink theme.
  bool get _dark => Theme.of(context).brightness == Brightness.dark;
  Color get _bg => _dark ? AnsibleDesign.darkPaper : AnsibleDesign.paper;
  Color get _bgElev =>
      _dark ? AnsibleDesign.darkPaperElev : AnsibleDesign.paperElev;
  Color get _fg => _dark ? AnsibleDesign.darkInk : AnsibleDesign.ink;
  Color get _muted =>
      _dark ? AnsibleDesign.darkInkMuted : AnsibleDesign.inkMuted;
  Color get _faint =>
      _dark ? AnsibleDesign.darkInkFaint : AnsibleDesign.inkFaint;
  Color get _rule => _dark ? AnsibleDesign.darkRule : AnsibleDesign.rule;
  Color get _ruleSoft =>
      _dark ? AnsibleDesign.darkRuleSoft : AnsibleDesign.ruleSoft;
  Color get _accent => _dark ? AnsibleDesign.darkOchre : AnsibleDesign.accent;

  final _pager = PageController();
  int _page = 0;

  @override
  void dispose() {
    _pager.dispose();
    super.dispose();
  }

  void _next() {
    if (_page == 0) {
      _pager.animateToPage(
        1,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
    } else {
      widget.onContinue();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: PageView(
          controller: _pager,
          onPageChanged: (p) => setState(() => _page = p),
          children: [_welcome(context), _promise(context)],
        ),
      ),
    );
  }

  // ── A·01 Welcome ──────────────────────────────────────────────────────────
  Widget _welcome(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 8, 22, 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _step('1 / 3'),
              GestureDetector(
                onTap: widget.onContinue,
                child: _link(context.uiCopy(zh: '跳過', en: 'Skip')),
              ),
            ],
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 26),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const AnsibleMark(size: 50),
                const SizedBox(height: 20),
                const ElixWordmark(fontSize: 46),
                const SizedBox(height: 20),
                Text(
                  context.uiCopy(
                    zh: '你的話、你的圈、\n你的鑰匙。',
                    en: 'Your words, your circle,\nyour keys.',
                  ),
                  style: TextStyle(
                    fontFamily: AnsibleDesign.serif,
                    fontSize: 30,
                    height: 1.32,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.3,
                    color: _fg,
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  // Benefit-led, not mechanism-led (UX review P1 + 行銷策略書:
                  // 「不要賣機制，要賣機制帶來的感受」).
                  context.uiCopy(
                    zh: '一個每個人都是真人的討論社群。沒有機器人、沒有網軍，你的帳號和內容永遠是你的。',
                    en:
                        'A community where everyone is a real person. No bots, '
                        'no troll armies — and your account and words stay '
                        'yours, always.',
                  ),
                  style: TextStyle(
                    fontFamily: AnsibleDesign.serif,
                    fontStyle: FontStyle.italic,
                    fontSize: 15.5,
                    height: 1.78,
                    color: _muted,
                  ),
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 14, 22, 10),
          child: Column(
            children: [
              _cta(
                context.uiCopy(zh: '進入', en: 'Enter'),
                trailing: '→',
              ),
              if (widget.reviewPublicContent != null) ...[
                const SizedBox(height: 8),
                TextButton(
                  key: const Key('google_play_review_public_content'),
                  onPressed: widget.reviewPublicContent,
                  child: Text(
                    context.uiCopy(
                      zh: '查看公開內容（Google Play 審查）',
                      en: 'Review public content (Google Play)',
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 14),
              Text(
                context.uiCopy(
                  zh: '沒有帳號 · 沒有雲端 · 不會被收集',
                  en: 'No account · No cloud · Never collected',
                ),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: AnsibleDesign.sans,
                  fontSize: 12,
                  letterSpacing: 0.3,
                  color: _faint,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── A·02 Promise ──────────────────────────────────────────────────────────
  Widget _promise(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 8, 22, 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              GestureDetector(
                onTap: () => _pager.animateToPage(
                  0,
                  duration: const Duration(milliseconds: 240),
                  curve: Curves.easeOut,
                ),
                child: _link(context.uiCopy(zh: '← 上一步', en: '← Back')),
              ),
              _step('2 / 3'),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(22, 24, 22, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _mono(
                  context.uiCopy(
                    zh: '三條承諾 · THREE PROMISES',
                    en: 'THREE PROMISES',
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  context.uiCopy(
                    zh: '這是一個會跟你\n一起變舊的地方。',
                    en: 'A place that grows\nold alongside you.',
                  ),
                  style: TextStyle(
                    fontFamily: AnsibleDesign.serif,
                    fontSize: 25,
                    height: 1.38,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.25,
                    color: _fg,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  context.uiCopy(
                    zh: '所有寫下來的東西，預設只在你的裝置裡。不上雲，不索引，不分析。要送出去之前，會先問你。',
                    en:
                        'Everything you write stays on your device by default — '
                        'no cloud, no indexing, no analysis. Before anything leaves, it asks you.',
                  ),
                  style: TextStyle(
                    fontFamily: AnsibleDesign.serif,
                    fontSize: 15,
                    height: 1.78,
                    color: _muted,
                  ),
                ),
                const SizedBox(height: 22),
                Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: _rule, width: 0.5),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: [
                      _promiseBlock(
                        context,
                        dot: AnsibleDesign.moss,
                        zh: '留在你這裡',
                        en: 'STAYS LOCAL',
                        items: const ['碎念與筆記的內容', '寫作的時序與停頓', '草稿與沒寄出的句子'],
                      ),
                      _promiseBlock(
                        context,
                        dot: _accent,
                        zh: '送出前會先問你',
                        en: 'ASKS FIRST',
                        items: const [
                          '請 AI 整理一段內容',
                          '把筆記分享到圈子或公開',
                          '把 murmur 編入別人的討論',
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 12, 22, 10),
          child: _cta(
            context.uiCopy(zh: '明白了 · 繼續', en: 'Got it · Continue'),
            trailing: '→',
          ),
        ),
      ],
    );
  }

  Widget _promiseBlock(
    BuildContext context, {
    required Color dot,
    required String zh,
    required String en,
    required List<String> items,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          color: _bgElev,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: dot,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    zh,
                    style: TextStyle(
                      fontFamily: AnsibleDesign.serif,
                      fontSize: 15.5,
                      fontWeight: FontWeight.w600,
                      color: _fg,
                    ),
                  ),
                ],
              ),
              _mono(en),
            ],
          ),
        ),
        for (final t in items)
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: _ruleSoft, width: 0.5)),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
            child: Text(
              '· $t',
              style: TextStyle(
                fontFamily: AnsibleDesign.serif,
                fontSize: 14.5,
                color: _muted,
              ),
            ),
          ),
      ],
    );
  }

  Widget _mono(String text, {bool center = false}) {
    return Text(
      text,
      textAlign: center ? TextAlign.center : null,
      style: TextStyle(
        fontFamily: AnsibleDesign.mono,
        fontSize: 10.5,
        letterSpacing: 2,
        color: _faint,
      ),
    );
  }

  /// Mono step counter in the top bar ("1 / 3").
  Widget _step(String text) {
    return Text(
      text,
      style: TextStyle(
        fontFamily: AnsibleDesign.mono,
        fontSize: 12,
        letterSpacing: 1.2,
        color: _faint,
      ),
    );
  }

  /// Sans top-bar link ("跳過" / "← 上一步").
  Widget _link(String text) {
    return Text(
      text,
      style: TextStyle(
        fontFamily: AnsibleDesign.sans,
        fontSize: 14,
        color: _muted,
      ),
    );
  }

  Widget _cta(String label, {String? trailing}) {
    return SizedBox(
      width: double.infinity,
      child: Material(
        color: _accent,
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: _next,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontFamily: AnsibleDesign.sans,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: _dark ? AnsibleDesign.darkPaper : AnsibleDesign.ink,
                  ),
                ),
                if (trailing != null) ...[
                  const SizedBox(width: 9),
                  Text(
                    trailing,
                    style: TextStyle(
                      fontFamily: AnsibleDesign.sans,
                      fontSize: 14,
                      color:
                          (_dark ? AnsibleDesign.darkPaper : AnsibleDesign.ink)
                              .withValues(alpha: 0.82),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
