import 'dart:async';

import 'package:flutter/material.dart';

import '../l10n/app_l10n.dart';
import '../theme/ansible_design.dart';

/// Bridges the app-wide sync affordance to the authenticated [HomeShell].
///
/// The controller deliberately owns no sync or identity data. It only exposes
/// the already constitution-gated manual sync action while the shell is
/// mounted, so adding the shortcut does not create a new publication path.
class ElixGlobalSyncController extends ChangeNotifier {
  Future<void> Function()? _action;
  bool _syncing = false;

  bool get isAvailable => _action != null;
  bool get isSyncing => _syncing;

  void attach(Future<void> Function() action) {
    if (identical(_action, action)) return;
    _action = action;
  }

  void detach(Future<void> Function() action) {
    if (_action != action) return;
    _action = null;
  }

  Future<bool> trigger() async {
    final action = _action;
    if (action == null || _syncing) return false;
    _syncing = true;
    notifyListeners();
    try {
      await action();
      return true;
    } finally {
      _syncing = false;
      notifyListeners();
    }
  }
}

/// The compact sync row introduced across all App screens in the 2026-09-01
/// Elix handoff. It sits directly below the platform status bar.
class ElixGlobalSyncShortcutRow extends StatelessWidget {
  const ElixGlobalSyncShortcutRow({
    super.key,
    required this.controller,
    this.onUnavailable,
  });

  final ElixGlobalSyncController controller;
  final VoidCallback? onUnavailable;

  Future<void> _handleTap() async {
    if (!await controller.trigger()) onUnavailable?.call();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final dark = Theme.of(context).brightness == Brightness.dark;
        final background = dark ? AnsibleDesign.darkOchre : AnsibleDesign.ochre;
        final label = context.l10n.sync;
        return SizedBox(
          key: const Key('global_sync_shortcut'),
          height: 28,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 2, 16, 4),
            child: Align(
              alignment: Alignment.centerRight,
              child: Semantics(
                button: true,
                label: label,
                child: Material(
                  color: background,
                  borderRadius: BorderRadius.circular(999),
                  elevation: 2,
                  shadowColor: Colors.black.withValues(alpha: 0.15),
                  child: InkWell(
                    key: const Key('global_sync_shortcut_button'),
                    onTap: controller.isSyncing
                        ? null
                        : () => unawaited(_handleTap()),
                    borderRadius: BorderRadius.circular(999),
                    child: SizedBox(
                      height: 22,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(6, 0, 8, 0),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (controller.isSyncing)
                              const SizedBox.square(
                                dimension: 12,
                                child: CircularProgressIndicator(
                                  strokeWidth: 1.5,
                                  color: Colors.white,
                                ),
                              )
                            else
                              const Icon(
                                Icons.sync,
                                size: 12,
                                color: Colors.white,
                              ),
                            const SizedBox(width: 4),
                            Text(
                              label,
                              style: const TextStyle(
                                fontFamily: AnsibleDesign.mono,
                                fontSize: 9.5,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.4,
                                color: Colors.white,
                                height: 1,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
