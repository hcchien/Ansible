import 'package:flutter/material.dart';

import '../config/app_environment.dart';
import '../l10n/app_l10n.dart';
import '../services/external_url_launcher.dart';
import '../services/terms_acceptance_store.dart';
import '../theme/ansible_design.dart';

/// Mandatory Terms/EULA checkpoint shown before account registration,
/// recovery/login, or resuming an identity after the safety terms change.
class TermsAcceptanceScreen extends StatefulWidget {
  const TermsAcceptanceScreen({
    super.key,
    required this.onAccepted,
    this.store = const TermsAcceptanceStore(),
    this.urlLauncher = const UrlLauncherExternalUrlLauncher(),
    this.legalBaseUrl = AppEnvironment.forumWebBaseUrl,
  });

  final VoidCallback onAccepted;
  final TermsAcceptanceStore store;
  final ExternalUrlLauncher urlLauncher;
  final String legalBaseUrl;

  @override
  State<TermsAcceptanceScreen> createState() => _TermsAcceptanceScreenState();
}

class _TermsAcceptanceScreenState extends State<TermsAcceptanceScreen> {
  bool _agreed = false;
  bool _saving = false;

  Future<void> _open(String path) async {
    final origin = widget.legalBaseUrl.replaceFirst(RegExp(r'/+$'), '');
    await widget.urlLauncher.open(Uri.parse('$origin$path'));
  }

  Future<void> _accept() async {
    if (!_agreed || _saving) return;
    setState(() => _saving = true);
    await widget.store.acceptCurrent();
    if (!mounted) return;
    widget.onAccepted();
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final background = dark ? AnsibleDesign.darkPaper : AnsibleDesign.paper;
    final foreground = dark ? AnsibleDesign.darkInk : AnsibleDesign.ink;
    final muted = dark ? AnsibleDesign.darkInkMuted : AnsibleDesign.inkMuted;
    final rule = dark ? AnsibleDesign.darkRule : AnsibleDesign.rule;
    final accent = dark ? AnsibleDesign.darkOchre : AnsibleDesign.accent;

    return Scaffold(
      backgroundColor: background,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(24, 36, 24, 24),
              children: [
                const AnsibleMark(size: 58),
                const SizedBox(height: 22),
                Text(
                  context.uiCopy(
                    zh: '加入社群前，先確認共同底線',
                    en: 'Agree to our community safety rules',
                  ),
                  style: TextStyle(
                    fontFamily: AnsibleDesign.serif,
                    fontSize: 26,
                    height: 1.35,
                    fontWeight: FontWeight.w700,
                    color: foreground,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  context.uiCopy(
                    zh: 'Elix 對不當內容與濫用使用者採取零容忍政策。你可以檢舉內容，也可以封鎖使用者；封鎖後，對方內容會立即從你的動態與討論中移除，並將事件通知管理者處理。',
                    en: 'Elix has zero tolerance for objectionable content or abusive users. You can report content and block users. Blocking immediately removes that user’s content from your feed and conversations and notifies the operator for review.',
                  ),
                  style: TextStyle(
                    fontFamily: AnsibleDesign.serif,
                    fontSize: 15,
                    height: 1.7,
                    color: muted,
                  ),
                ),
                const SizedBox(height: 18),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    border: Border.all(color: rule),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextButton.icon(
                        key: const Key('open_terms_link'),
                        onPressed: () => _open('/terms'),
                        icon: const Icon(Icons.description_outlined),
                        label: Text(
                          context.uiCopy(
                            zh: '閱讀服務條款與社群安全規範',
                            en: 'Read the Terms and Community Safety Rules',
                          ),
                        ),
                      ),
                      TextButton.icon(
                        key: const Key('open_privacy_link'),
                        onPressed: () => _open('/privacy'),
                        icon: const Icon(Icons.privacy_tip_outlined),
                        label: Text(
                          context.uiCopy(
                            zh: '閱讀隱私權政策',
                            en: 'Read the Privacy Policy',
                          ),
                        ),
                      ),
                      const Divider(),
                      CheckboxListTile(
                        key: const Key('accept_terms_checkbox'),
                        value: _agreed,
                        onChanged: _saving
                            ? null
                            : (value) =>
                                  setState(() => _agreed = value ?? false),
                        controlAffinity: ListTileControlAffinity.leading,
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          context.uiCopy(
                            zh: '我已閱讀並同意服務條款、零容忍政策與社群安全規範',
                            en: 'I have read and agree to the Terms, zero-tolerance policy, and Community Safety Rules',
                          ),
                          style: TextStyle(color: foreground, height: 1.45),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 22),
                FilledButton(
                  key: const Key('accept_terms_continue'),
                  onPressed: _agreed && !_saving ? _accept : null,
                  style: FilledButton.styleFrom(backgroundColor: accent),
                  child: Text(
                    context.uiCopy(zh: '同意並繼續', en: 'Agree and Continue'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
