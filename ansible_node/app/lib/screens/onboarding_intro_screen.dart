import 'package:flutter/material.dart';

import '../l10n/app_l10n.dart';
import '../theme/ansible_design.dart';

/// Section A (onboarding) intro flow from the Elix Screens design: Welcome (A·01)
/// and Promise (A·02). Leads into the passkey registration screen ("first key",
/// A·03). Editorial styling: serif headings/body, mono small-caps labels, the
/// constellation mark + wordmark, dark pill CTA.
class OnboardingIntroScreen extends StatefulWidget {
  const OnboardingIntroScreen({super.key, required this.onContinue});

  /// Called when the user finishes the intro — the host shows the passkey
  /// registration screen next.
  final VoidCallback onContinue;

  @override
  State<OnboardingIntroScreen> createState() => _OnboardingIntroScreenState();
}

class _OnboardingIntroScreenState extends State<OnboardingIntroScreen> {
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
      backgroundColor: AnsibleDesign.paper,
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
              _mono(context.uiCopy(zh: '1 / 3', en: '1 / 3')),
              GestureDetector(
                onTap: widget.onContinue,
                child: _mono(context.uiCopy(zh: '跳過', en: 'Skip')),
              ),
            ],
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const AnsibleMark(size: 96),
                const SizedBox(height: 26),
                const ElixWordmark(fontSize: 40),
                const SizedBox(height: 26),
                Text(
                  context.uiCopy(
                    zh: '你的話、你的圈、\n你的鑰匙。',
                    en: 'Your words, your circle,\nyour keys.',
                  ),
                  style: const TextStyle(
                    fontFamily: AnsibleDesign.serif,
                    fontSize: 22,
                    height: 1.55,
                    color: AnsibleDesign.ink,
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  context.uiCopy(
                    zh: '一個重新建立信任的社群。資料留在本地，身分握在你自己手上。要被看見之前，先問過你。',
                    en: 'A community rebuilding trust. Your data stays local, '
                        'your identity is yours. Nothing is seen without asking you first.',
                  ),
                  style: const TextStyle(
                    fontFamily: AnsibleDesign.serif,
                    fontStyle: FontStyle.italic,
                    fontSize: 14,
                    height: 1.7,
                    color: AnsibleDesign.inkMuted,
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
              _cta(context.uiCopy(zh: '進入', en: 'Enter'), trailing: '→'),
              const SizedBox(height: 14),
              _mono(
                context.uiCopy(
                  zh: '沒有帳號 · 沒有雲端 · 不會被收集',
                  en: 'No account · No cloud · Never collected',
                ),
                center: true,
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
                child: _mono(context.uiCopy(zh: '← 上一步', en: '← Back')),
              ),
              _mono('2 / 3'),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(22, 24, 22, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _mono(context.uiCopy(zh: '三條承諾 · THREE PROMISES', en: 'THREE PROMISES')),
                const SizedBox(height: 16),
                Text(
                  context.uiCopy(
                    zh: '這是一個會跟你\n一起變舊的地方。',
                    en: 'A place that grows\nold alongside you.',
                  ),
                  style: const TextStyle(
                    fontFamily: AnsibleDesign.serif,
                    fontSize: 24,
                    height: 1.45,
                    fontWeight: FontWeight.w500,
                    color: AnsibleDesign.ink,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  context.uiCopy(
                    zh: '所有寫下來的東西，預設只在你的裝置裡。不上雲，不索引，不分析。要送出去之前，會先問你。',
                    en: 'Everything you write stays on your device by default — '
                        'no cloud, no indexing, no analysis. Before anything leaves, it asks you.',
                  ),
                  style: const TextStyle(
                    fontFamily: AnsibleDesign.serif,
                    fontSize: 13.5,
                    height: 1.75,
                    color: AnsibleDesign.inkMuted,
                  ),
                ),
                const SizedBox(height: 22),
                Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: AnsibleDesign.rule, width: 0.5),
                    borderRadius: BorderRadius.circular(14),
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
                        dot: AnsibleDesign.accent,
                        zh: '送出前會先問你',
                        en: 'ASKS FIRST',
                        items: const ['請 AI 整理一段內容', '把筆記分享到圈子或公開', '把 murmur 編入別人的討論'],
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
          color: AnsibleDesign.paperElev,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    zh,
                    style: const TextStyle(
                      fontFamily: AnsibleDesign.serif,
                      fontSize: 13,
                      color: AnsibleDesign.ink,
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
            decoration: const BoxDecoration(
              border: Border(
                top: BorderSide(color: AnsibleDesign.ruleSoft, width: 0.5),
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Text(
              '· $t',
              style: const TextStyle(
                fontFamily: AnsibleDesign.serif,
                fontSize: 13,
                color: AnsibleDesign.ink,
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
      style: const TextStyle(
        fontFamily: AnsibleDesign.mono,
        fontSize: 9.5,
        letterSpacing: 1.6,
        color: AnsibleDesign.inkFaint,
      ),
    );
  }

  Widget _cta(String label, {String? trailing}) {
    return SizedBox(
      width: double.infinity,
      child: Material(
        color: AnsibleDesign.ink,
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
                  style: const TextStyle(
                    fontFamily: AnsibleDesign.serif,
                    fontSize: 14,
                    color: AnsibleDesign.paper,
                  ),
                ),
                if (trailing != null) ...[
                  const SizedBox(width: 8),
                  Text(
                    trailing,
                    style: TextStyle(
                      fontFamily: AnsibleDesign.mono,
                      fontSize: 12,
                      color: AnsibleDesign.paper.withValues(alpha: 0.55),
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
