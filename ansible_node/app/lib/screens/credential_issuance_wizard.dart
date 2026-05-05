import 'package:ansible_store/ansible_store.dart';
import 'package:flutter/material.dart';

import '../services/external_url_launcher.dart';
import '../services/vc_issuer_client.dart';
import 'tw_provider_credential_screen.dart';

enum CredentialIssuanceFlow { twProvider, emailOtp }

class CredentialIssuanceWizard extends StatefulWidget {
  const CredentialIssuanceWizard({
    super.key,
    required this.holderDid,
    this.vcIssuerClient,
    this.urlLauncher,
    this.walletRepository,
    this.pollInterval = const Duration(seconds: 2),
    this.pollTimeout = const Duration(minutes: 2),
    this.onCredentialStored,
  });

  final String holderDid;
  final VcIssuerClient? vcIssuerClient;
  final ExternalUrlLauncher? urlLauncher;
  final WalletRepository? walletRepository;
  final Duration pollInterval;
  final Duration pollTimeout;
  final VoidCallback? onCredentialStored;

  @override
  State<CredentialIssuanceWizard> createState() =>
      _CredentialIssuanceWizardState();
}

class _CredentialIssuanceWizardState extends State<CredentialIssuanceWizard> {
  CredentialIssuanceFlow? _selectedFlow;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '加入憑證',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '選擇你要使用的身份驗證方式',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 20),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    alignment: WrapAlignment.center,
                    children: [
                      _FlowOptionButton(
                        icon: Icons.badge_outlined,
                        label: 'TW 身份驗證',
                        selected:
                            _selectedFlow == CredentialIssuanceFlow.twProvider,
                        onTap: () => _select(CredentialIssuanceFlow.twProvider),
                      ),
                      _FlowOptionButton(
                        icon: Icons.email_outlined,
                        label: 'Email OTP / Legacy',
                        selected:
                            _selectedFlow == CredentialIssuanceFlow.emailOtp,
                        onTap: () => _select(CredentialIssuanceFlow.emailOtp),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 180),
                    child: _buildSelectedPanel(),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _select(CredentialIssuanceFlow flow) {
    setState(() => _selectedFlow = flow);
  }

  Widget _buildSelectedPanel() {
    switch (_selectedFlow) {
      case CredentialIssuanceFlow.twProvider:
        return TwProviderCredentialPanel(
          key: const ValueKey('tw-provider-panel'),
          holderDid: widget.holderDid,
          vcIssuerClient: widget.vcIssuerClient,
          urlLauncher: widget.urlLauncher,
          walletRepository: widget.walletRepository,
          pollInterval: widget.pollInterval,
          pollTimeout: widget.pollTimeout,
          onCredentialStored: widget.onCredentialStored,
        );
      case CredentialIssuanceFlow.emailOtp:
        return const EmailOtpCredentialPanel(key: ValueKey('email-otp-panel'));
      case null:
        return const SizedBox.shrink(key: ValueKey('no-flow-selected'));
    }
  }
}

class EmailOtpCredentialPanel extends StatelessWidget {
  const EmailOtpCredentialPanel({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Icon(
          Icons.verified_user_outlined,
          size: 56,
          color: Color(0xFF1A56A4),
        ),
        const SizedBox(height: 16),
        Text(
          'Email 身份驗證',
          textAlign: TextAlign.center,
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}

class _FlowOptionButton extends StatelessWidget {
  const _FlowOptionButton({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected
        ? Theme.of(context).colorScheme.primary
        : Theme.of(context).colorScheme.onSurfaceVariant;

    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, color: color),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        foregroundColor: color,
        side: BorderSide(
          color: selected
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).dividerColor,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
    );
  }
}
