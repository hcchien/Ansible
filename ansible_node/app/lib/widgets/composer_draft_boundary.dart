import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import '../l10n/app_l10n.dart';
import '../services/composer_draft_store.dart';

/// Persists editable state only. A successful pop waits for the draft write;
/// callers clear it only after committing the composed content locally.
class ComposerDraftBoundary extends StatefulWidget {
  const ComposerDraftBoundary({
    super.key,
    required this.draftKey,
    required this.snapshot,
    required this.restore,
    required this.controllers,
    required this.child,
  });
  final String? draftKey;
  final Map<String, dynamic> Function() snapshot;
  final void Function(Map<String, dynamic>) restore;
  final List<TextEditingController> controllers;
  final Widget child;
  @override
  State<ComposerDraftBoundary> createState() => _ComposerDraftBoundaryState();
}

class _ComposerDraftBoundaryState extends State<ComposerDraftBoundary>
    with WidgetsBindingObserver {
  Timer? _timer;
  bool _ready = false;
  bool _failed = false;
  bool _canPop = false;
  bool _leaving = false;
  String? _last;
  Map<String, dynamic>? _pendingData;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    for (final c in widget.controllers) {
      c.addListener(_changed);
    }
    // Defer the restore prompt until the route and its inherited widgets exist.
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final key = widget.draftKey;
    try {
      final saved = key == null
          ? null
          : await ComposerDraftStore.shared.read(key);
      if (!mounted) return;
      if (saved != null && _hasText(saved)) {
        final resume = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            title: Text(
              context.uiCopy(zh: '繼續上次的草稿？', en: 'Continue your draft?'),
            ),
            content: Text(
              context.uiCopy(
                zh: '草稿只保存在這台裝置，尚未發表。',
                en: 'This draft is saved on this device and has not been published.',
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(context.uiCopy(zh: '捨棄草稿', en: 'Discard draft')),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(context.uiCopy(zh: '繼續編輯', en: 'Continue editing')),
              ),
            ],
          ),
        );
        if (!mounted) return;
        if (resume == true) {
          widget.restore(saved);
        } else {
          await ComposerDraftStore.shared.clear(key!);
        }
      }
      if (mounted) {
        setState(() {
          _ready = true;
          _failed = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  bool _hasText(Map<String, dynamic> data) => [
    'body',
    'title',
    'content',
  ].any((key) => (data[key] as String? ?? '').trim().isNotEmpty);
  void _changed() {
    if (!_ready || _leaving || widget.draftKey == null) return;
    _pendingData = widget.snapshot();
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 350), _save);
  }

  Future<bool> _persist(Map<String, dynamic> data) async {
    final key = widget.draftKey;
    if (key == null) return true;
    final encoded = jsonEncode(data);
    if (_last == encoded) return true;
    try {
      if (_hasText(data)) {
        await ComposerDraftStore.shared.write(key, data);
      } else {
        await ComposerDraftStore.shared.clear(key);
      }
      _last = encoded;
      if (mounted && _failed) setState(() => _failed = false);
      return true;
    } catch (_) {
      if (mounted) setState(() => _failed = true);
      return false;
    }
  }

  Future<bool> _save() async {
    if (!_ready) return widget.draftKey == null;
    _pendingData = widget.snapshot();
    return _persist(_pendingData!);
  }

  Future<void> _pop(Object? result) async {
    if (_leaving) return;
    _leaving = true;
    _timer?.cancel();
    if (!await _save()) {
      _leaving = false;
      return;
    }
    if (!mounted) return;
    _pendingData = null;
    setState(() => _canPop = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).pop(result);
    });
  }

  @override
  void didUpdateWidget(covariant ComposerDraftBoundary oldWidget) {
    super.didUpdateWidget(oldWidget);
    for (final c in oldWidget.controllers) {
      c.removeListener(_changed);
    }
    for (final c in widget.controllers) {
      c.addListener(_changed);
    }
    _changed();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      _timer?.cancel();
      _save();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    // Use the captured value: parent controllers can be disposed already when
    // an embedded composer is removed by a tab switch instead of a route pop.
    final data = _pendingData;
    if (data != null && !_leaving) unawaited(_persist(data));
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: _canPop,
    onPopInvokedWithResult: (didPop, result) {
      if (!didPop) _pop(result);
    },
    child: Material(
      child: Column(
        children: [
          if (_failed)
            MaterialBanner(
              content: Text(
                context.uiCopy(
                  zh: '草稿儲存空間目前無法使用，請保持此頁並重試。',
                  en: 'Draft storage is unavailable. Keep this page open and retry.',
                ),
              ),
              actions: [
                TextButton(
                  onPressed: _ready ? _save : _load,
                  child: Text(context.uiCopy(zh: '重試', en: 'Retry')),
                ),
              ],
            ),
          Expanded(
            child: AbsorbPointer(absorbing: !_ready, child: widget.child),
          ),
        ],
      ),
    ),
  );
}
