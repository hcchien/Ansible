import 'package:flutter/material.dart';

import '../services/handle_resolver.dart';

/// Renders a post author's public label in display-name → handle → short-DID
/// order. Display names are presentation-only; [did] remains the identity used
/// for navigation, authorization and verification.
class AuthorLabel extends StatelessWidget {
  const AuthorLabel({
    super.key,
    required this.did,
    this.style,
    this.maxLines = 1,
    this.overflow = TextOverflow.ellipsis,
    this.resolver,
    this.profileResolver,
    this.displayName,
    this.handle,
  });

  final String did;
  final TextStyle? style;
  final int maxLines;
  final TextOverflow overflow;

  /// Overridable for tests; defaults to the shared process-wide resolver.
  final HandleResolver? resolver;

  /// Optional public profile data carried by an AppView response. It avoids a
  /// second lookup for feeds that already contain this presentation data.
  final String? displayName;
  final String? handle;

  /// Overridable for tests; resolves published display name then handle.
  final PublicProfileResolver? profileResolver;

  @override
  Widget build(BuildContext context) {
    final direct = _preferredLabel(displayName, handle);
    if (direct != null) {
      return Text(direct, style: style, maxLines: maxLines, overflow: overflow);
    }
    final profile = profileResolver ?? PublicProfileResolver.shared;
    final fallback = resolver ?? HandleResolver.shared;
    return FutureBuilder<PublicAuthorProfile?>(
      initialData: profile.cached(did),
      future: profile.profileFor(did),
      builder: (context, snapshot) {
        final text =
            snapshot.data?.preferredLabel ??
            fallback.cached(did) ??
            shortenDid(did);
        return Text(text, style: style, maxLines: maxLines, overflow: overflow);
      },
    );
  }

  String? _preferredLabel(String? name, String? candidateHandle) {
    final normalizedName = name?.trim();
    if (normalizedName != null && normalizedName.isNotEmpty) {
      return normalizedName;
    }
    final normalizedHandle = candidateHandle?.trim();
    return normalizedHandle != null && normalizedHandle.isNotEmpty
        ? (normalizedHandle.startsWith('@')
              ? normalizedHandle
              : '@$normalizedHandle')
        : null;
  }
}
