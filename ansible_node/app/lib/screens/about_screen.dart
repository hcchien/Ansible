import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../config/app_environment.dart';
import '../l10n/app_l10n.dart';
import '../services/external_url_launcher.dart';
import '../theme/ansible_design.dart';
import '../widgets/ansible_screen_chrome.dart';

/// About screen: app identity + the legal / policy pages required for store
/// submission (privacy policy, terms, about, account deletion). Each row opens
/// the corresponding page on the public web frontend in the external browser.
class AboutScreen extends StatefulWidget {
  const AboutScreen({
    super.key,
    this.urlLauncher = const UrlLauncherExternalUrlLauncher(),
    this.forumWebBaseUrl = AppEnvironment.forumWebBaseUrl,
  });

  /// Injectable for tests; defaults to url_launcher in external-browser mode.
  final ExternalUrlLauncher urlLauncher;

  /// Origin of the public web frontend hosting the legal pages. Defaults to
  /// the compile-time `ANSIBLE_FORUM_WEB_BASE_URL` dart-define
  /// (https://forum.elix.cool).
  final String forumWebBaseUrl;

  @override
  State<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends State<AboutScreen> {
  String? _versionLabel;

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    String? label;
    try {
      final info = await PackageInfo.fromPlatform();
      label = 'v${info.version} (${info.buildNumber})';
    } catch (_) {
      label = null; // Platform channel unavailable; hide the version line.
    }
    if (!mounted) return;
    setState(() => _versionLabel = label);
  }

  Uri _legalUri(String path) {
    final base = widget.forumWebBaseUrl.replaceFirst(RegExp(r'/+$'), '');
    return Uri.parse('$base$path');
  }

  Future<void> _openLegalPage(BuildContext context, String path) async {
    final uri = _legalUri(path);
    final opened = await widget.urlLauncher.open(uri);
    if (opened || !context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          context.uiCopy(
            zh: '無法開啟瀏覽器，請手動前往 $uri',
            en: 'Could not open the browser. Please visit $uri',
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnsibleScreenScaffold(
      title: context.uiCopy(zh: '關於 · ABOUT', en: 'ABOUT'),
      leadingLabel: context.uiCopy(zh: '← 設定', en: '← Settings'),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(22, 0, 22, 32),
        children: [
          const SizedBox(height: 12),
          const Center(
            child: Text(
              'Elix',
              style: TextStyle(
                fontFamily: AnsibleDesign.serif,
                fontSize: 30,
                fontWeight: FontWeight.w700,
                color: AnsibleDesign.ink,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Center(
            child: Text(
              context.uiCopy(zh: '去中心化、身分自主的討論社群', en: 'A decentralized, self-sovereign discussion community'),
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: AnsibleDesign.serif,
                fontSize: 14,
                color: AnsibleDesign.inkMuted,
              ),
            ),
          ),
          if (_versionLabel != null) ...[
            const SizedBox(height: 6),
            Center(
              child: Text(
                _versionLabel!,
                key: const Key('about_version_label'),
                style: const TextStyle(
                  fontFamily: AnsibleDesign.mono,
                  fontSize: 11,
                  letterSpacing: 1.2,
                  color: AnsibleDesign.inkFaint,
                ),
              ),
            ),
          ],
          const SizedBox(height: 24),
          AnsibleMonoLabel(
            context.uiCopy(zh: '政策與條款 · LEGAL', en: 'LEGAL'),
          ),
          const SizedBox(height: 8),
          AnsibleRuleGroup(
            children: [
              AnsibleSettingsRow(
                glyph: '§',
                label: context.uiCopy(zh: '隱私權政策', en: 'Privacy Policy'),
                en: 'PRIVACY',
                onTap: () => _openLegalPage(context, '/privacy'),
              ),
              AnsibleSettingsRow(
                glyph: '¶',
                label: context.uiCopy(zh: '服務條款', en: 'Terms of Service'),
                en: 'TERMS',
                onTap: () => _openLegalPage(context, '/terms'),
              ),
              AnsibleSettingsRow(
                glyph: 'i',
                label: context.uiCopy(zh: '關於 Elix', en: 'About Elix'),
                en: 'ABOUT ELIX',
                onTap: () => _openLegalPage(context, '/about'),
              ),
              AnsibleSettingsRow(
                glyph: '×',
                label: context.uiCopy(
                  zh: '刪除帳號與資料',
                  en: 'Delete account & data',
                ),
                en: 'DELETE ACCOUNT',
                sub: context.uiCopy(
                  zh: '如何刪除，以及資料會發生什麼事',
                  en: 'How to delete, and what happens to your data',
                ),
                last: true,
                onTap: () => _openLegalPage(context, '/account-deletion'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
