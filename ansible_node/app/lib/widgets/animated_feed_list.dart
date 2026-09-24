import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../l10n/app_l10n.dart';

/// Keeps row identity and the mounted scroll position across background reads.
/// New ordering waits for the reader when away from the top; removals apply
/// immediately so blocked/deleted content is never held by the UI cache.
class AnimatedFeedList<T> extends StatefulWidget {
  const AnimatedFeedList({
    super.key,
    required this.items,
    required this.itemId,
    required this.itemRevision,
    required this.itemBuilder,
  });

  final List<T> items;
  final String Function(T) itemId;
  final Object Function(T) itemRevision;
  final Widget Function(BuildContext, T) itemBuilder;

  @override
  State<AnimatedFeedList<T>> createState() => _AnimatedFeedListState<T>();
}

class _AnimatedFeedListState<T> extends State<AnimatedFeedList<T>> {
  final _scroll = ScrollController();
  late List<T> _visible = List.of(widget.items);
  List<T>? _pending;
  Set<String> _arrivals = {};

  @override
  void didUpdateWidget(covariant AnimatedFeedList<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    final before = _visible.map(widget.itemId).toList();
    final after = widget.items.map(widget.itemId).toList();
    final byId = {for (final item in widget.items) widget.itemId(item): item};
    final reading = _scroll.hasClients && _scroll.offset > 24;
    if (reading &&
        !listEquals(before, after) &&
        before.every(byId.containsKey)) {
      _pending = List.of(widget.items);
      _visible = [for (final id in before) byId[id] as T];
    } else {
      _apply(widget.items);
    }
  }

  void _apply(List<T> items) {
    final existing = _visible.map(widget.itemId).toSet();
    _arrivals = items.map(widget.itemId).toSet().difference(existing);
    _visible = List.of(items);
    _pending = null;
  }

  void _showUpdates() {
    final items = _pending;
    if (items == null) return;
    setState(() => _apply(items));
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final indexes = {
      for (var i = 0; i < _visible.length; i++) widget.itemId(_visible[i]): i,
    };
    return Stack(
      children: [
        ListView.builder(
          controller: _scroll,
          itemCount: _visible.length,
          padding: const EdgeInsets.only(bottom: 12),
          findChildIndexCallback: (key) =>
              key is ValueKey<String> ? indexes[key.value] : null,
          itemBuilder: (context, index) {
            final item = _visible[index];
            final id = widget.itemId(item);
            return FeedUpdateTransition(
              key: ValueKey(id),
              revision: widget.itemRevision(item),
              animateEntry: _arrivals.contains(id),
              child: Padding(
                padding: EdgeInsets.only(
                  bottom: index + 1 < _visible.length ? 12 : 0,
                ),
                child: widget.itemBuilder(context, item),
              ),
            );
          },
        ),
        if (_pending != null)
          Positioned(
            top: 8,
            left: 0,
            right: 0,
            child: Center(
              child: FilledButton.icon(
                key: const Key('feed_show_updates'),
                onPressed: _showUpdates,
                icon: const Icon(Icons.arrow_upward, size: 16),
                label: Text(context.uiCopy(zh: '查看更新', en: 'Show updates')),
              ),
            ),
          ),
      ],
    );
  }
}

/// Brief row-only fade/translation; keeps the child state and layout height.
class FeedUpdateTransition extends StatefulWidget {
  const FeedUpdateTransition({
    super.key,
    required this.revision,
    required this.child,
    this.animateEntry = false,
  });

  final Object revision;
  final bool animateEntry;
  final Widget child;

  @override
  State<FeedUpdateTransition> createState() => _FeedUpdateTransitionState();
}

class _FeedUpdateTransitionState extends State<FeedUpdateTransition>
    with SingleTickerProviderStateMixin {
  late final _animation = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
    value: 1,
  );
  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _animation.value = 1;
    } else if (!_initialized && widget.animateEntry) {
      _animation.forward(from: 0);
    }
    _initialized = true;
  }

  @override
  void didUpdateWidget(covariant FeedUpdateTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.revision != oldWidget.revision &&
        !MediaQuery.disableAnimationsOf(context)) {
      _animation.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _animation,
    child: widget.child,
    builder: (context, child) {
      final progress = Curves.easeOutCubic.transform(_animation.value);
      return Opacity(
        opacity: 0.65 + 0.35 * progress,
        child: Transform.translate(
          offset: Offset(0, 6 * (1 - progress)),
          child: child,
        ),
      );
    },
  );
}
