import 'package:flutter/material.dart';

import '../theme/ansible_design.dart';

class NoteMarkdownEditingController extends TextEditingController {
  NoteMarkdownEditingController({super.text});

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    return buildNoteMarkdownTextSpan(
      text: text,
      baseStyle: style,
      stripSyntax: true,
    );
  }
}

class NoteMarkdownBody extends StatelessWidget {
  const NoteMarkdownBody(
    this.text, {
    super.key,
    this.style = const TextStyle(
      fontSize: AnsibleDesign.readingTextSize,
      height: 1.75,
      color: AnsibleDesign.ink,
    ),
    this.maxLines,
    this.overflow = TextOverflow.clip,
  });

  final String text;
  final TextStyle style;
  final int? maxLines;
  final TextOverflow overflow;

  @override
  Widget build(BuildContext context) {
    return RichText(
      maxLines: maxLines,
      overflow: overflow,
      text: buildNoteMarkdownTextSpan(text: text, baseStyle: style),
    );
  }
}

TextSpan buildNoteMarkdownTextSpan({
  required String text,
  TextStyle? baseStyle,
  bool stripSyntax = true,
}) {
  final style =
      baseStyle ??
      const TextStyle(
        fontSize: AnsibleDesign.readingTextSize,
        height: 1.75,
        color: AnsibleDesign.ink,
      );
  final spans = <TextSpan>[];
  final lines = text.split('\n');

  for (var index = 0; index < lines.length; index += 1) {
    final line = lines[index];
    final isHeading = line.startsWith('## ');
    final isQuote = line.startsWith('> ');
    final bodyStart = isHeading ? 3 : (isQuote ? 2 : 0);
    final body = line.substring(bodyStart);
    if (!stripSyntax && bodyStart > 0) {
      spans.add(
        TextSpan(
          text: line.substring(0, bodyStart),
          style: style.copyWith(color: AnsibleDesign.inkFaint),
        ),
      );
    }
    final lineStyle = style.merge(
      TextStyle(
        fontSize: isHeading ? (style.fontSize ?? 15) + 5 : null,
        fontWeight: isHeading ? FontWeight.w600 : null,
        color: isQuote ? AnsibleDesign.inkMuted : null,
        fontStyle: isQuote ? FontStyle.italic : null,
      ),
    );
    spans.addAll(_inlineSpans(body, lineStyle, stripSyntax: stripSyntax));
    if (index < lines.length - 1) {
      spans.add(TextSpan(text: '\n', style: style));
    }
  }

  return TextSpan(style: style, children: spans);
}

List<TextSpan> _inlineSpans(
  String text,
  TextStyle style, {
  required bool stripSyntax,
}) {
  final spans = <TextSpan>[];
  var index = 0;

  while (index < text.length) {
    final match = _nextMatch(text, index);
    if (match == null) {
      spans.add(TextSpan(text: text.substring(index), style: style));
      break;
    }
    if (match.start > index) {
      spans.add(
        TextSpan(text: text.substring(index, match.start), style: style),
      );
    }
    if (!stripSyntax) {
      spans.add(
        TextSpan(
          text: match.open,
          style: style.copyWith(color: AnsibleDesign.inkFaint),
        ),
      );
    }
    spans.add(TextSpan(text: match.text, style: style.merge(match.styleDelta)));
    if (!stripSyntax) {
      spans.add(
        TextSpan(
          text: match.close,
          style: style.copyWith(color: AnsibleDesign.inkFaint),
        ),
      );
    }
    index = match.end;
  }

  return spans;
}

_MarkdownMatch? _nextMatch(String text, int start) {
  final candidates =
      [
          _matchDelimited(
            text,
            start,
            open: '**',
            close: '**',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          _matchDelimited(
            text,
            start,
            open: '_',
            close: '_',
            style: const TextStyle(fontStyle: FontStyle.italic),
          ),
          _matchDelimited(
            text,
            start,
            open: '<u>',
            close: '</u>',
            style: const TextStyle(decoration: TextDecoration.underline),
          ),
          _matchLink(text, start),
        ].whereType<_MarkdownMatch>().toList()
        ..sort((a, b) => a.start.compareTo(b.start));

  return candidates.isEmpty ? null : candidates.first;
}

_MarkdownMatch? _matchDelimited(
  String text,
  int start, {
  required String open,
  required String close,
  required TextStyle style,
}) {
  final openIndex = text.indexOf(open, start);
  if (openIndex < 0) return null;
  final contentStart = openIndex + open.length;
  final closeIndex = text.indexOf(close, contentStart);
  if (closeIndex < 0) return null;
  return _MarkdownMatch(
    start: openIndex,
    end: closeIndex + close.length,
    open: open,
    close: close,
    text: text.substring(contentStart, closeIndex),
    styleDelta: style,
  );
}

_MarkdownMatch? _matchLink(String text, int start) {
  final openIndex = text.indexOf('[', start);
  if (openIndex < 0) return null;
  final labelEnd = text.indexOf('](', openIndex + 1);
  if (labelEnd < 0) return null;
  final urlEnd = text.indexOf(')', labelEnd + 2);
  if (urlEnd < 0) return null;
  return _MarkdownMatch(
    start: openIndex,
    end: urlEnd + 1,
    open: '[',
    close: text.substring(labelEnd, urlEnd + 1),
    text: text.substring(openIndex + 1, labelEnd),
    styleDelta: const TextStyle(
      color: AnsibleDesign.accent,
      decoration: TextDecoration.underline,
    ),
  );
}

class _MarkdownMatch {
  const _MarkdownMatch({
    required this.start,
    required this.end,
    required this.open,
    required this.close,
    required this.text,
    required this.styleDelta,
  });

  final int start;
  final int end;
  final String open;
  final String close;
  final String text;
  final TextStyle styleDelta;
}
