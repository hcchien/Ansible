import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/platform_capabilities.dart';

/// Desktop-native keyboard access without changing the mobile interaction
/// model. Shortcuts are deliberately limited to reversible navigation/actions.
class DesktopShortcutScope extends StatelessWidget {
  const DesktopShortcutScope({
    super.key,
    required this.child,
    required this.onCompose,
    required this.onRefresh,
    this.capabilities,
  });

  final Widget child;
  final VoidCallback onCompose;
  final VoidCallback onRefresh;
  final PlatformCapabilities? capabilities;

  @override
  Widget build(BuildContext context) {
    final platform = capabilities ?? PlatformCapabilities.current;
    if (!platform.desktop) return child;

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyN, meta: true): onCompose,
        const SingleActivator(LogicalKeyboardKey.keyN, control: true): onCompose,
        const SingleActivator(LogicalKeyboardKey.keyR, meta: true): onRefresh,
        const SingleActivator(LogicalKeyboardKey.keyR, control: true): onRefresh,
      },
      child: Focus(autofocus: true, child: child),
    );
  }
}
