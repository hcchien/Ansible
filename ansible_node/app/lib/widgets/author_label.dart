import 'package:flutter/material.dart';

import '../services/handle_resolver.dart';

/// Renders a post author's byline as their handle (resolved from the DID),
/// falling back to a shortened DID while loading or when unresolved. Reactive:
/// once the handle resolves it replaces the fallback without a manual refresh.
class AuthorLabel extends StatelessWidget {
  const AuthorLabel({
    super.key,
    required this.did,
    this.style,
    this.maxLines = 1,
    this.overflow = TextOverflow.ellipsis,
    this.resolver,
  });

  final String did;
  final TextStyle? style;
  final int maxLines;
  final TextOverflow overflow;

  /// Overridable for tests; defaults to the shared process-wide resolver.
  final HandleResolver? resolver;

  @override
  Widget build(BuildContext context) {
    final r = resolver ?? HandleResolver.shared;
    return FutureBuilder<String?>(
      initialData: r.cached(did),
      future: r.handleFor(did),
      builder: (context, snapshot) {
        final handle = snapshot.data;
        final text = (handle != null && handle.isNotEmpty)
            ? handle
            : shortenDid(did);
        return Text(text, style: style, maxLines: maxLines, overflow: overflow);
      },
    );
  }
}
