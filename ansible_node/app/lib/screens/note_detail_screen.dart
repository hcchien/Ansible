import 'package:ansible_store/ansible_store.dart';
import 'package:flutter/material.dart';

import '../l10n/app_l10n.dart';
import '../theme/ansible_design.dart';
import '../widgets/note_markdown_text.dart';

class NoteDetailScreen extends StatelessWidget {
  const NoteDetailScreen({
    super.key,
    required this.note,
    this.sourceMurmurs = const [],
    this.onEdit,
  });

  final ContentItem note;
  final List<ContentItem> sourceMurmurs;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AnsibleDesign.paper,
      body: SafeArea(
        child: Column(
          children: [
            _TopBar(note: note, onEdit: onEdit),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(22, 6, 22, 24),
                children: [
                  _MetaLabel(
                    context.uiCopy(
                      zh: 'NOTE · 始於 ${_formatDate(note.createdAt)}',
                      en: 'NOTE · since ${_formatDate(note.createdAt)}',
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    note.title ??
                        context.uiCopy(zh: '未命名筆記', en: 'Untitled note'),
                    style: const TextStyle(
                      fontSize: 30,
                      height: 1.2,
                      fontWeight: FontWeight.w500,
                      color: AnsibleDesign.ink,
                      letterSpacing: 0,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _LineageRail(
                    count: sourceMurmurs.length,
                    start: note.createdAt,
                    end: note.updatedAt,
                  ),
                  const _Hairline(margin: EdgeInsets.only(top: 8, bottom: 18)),
                  NoteMarkdownBody(
                    note.body,
                    style: const TextStyle(
                      fontSize: AnsibleDesign.readingTextSize,
                      height: 1.75,
                      color: AnsibleDesign.ink,
                    ),
                  ),
                  const _Hairline(margin: EdgeInsets.only(top: 24, bottom: 16)),
                  _SourceLineageSection(sourceMurmurs: sourceMurmurs),
                ],
              ),
            ),
            _BottomActionBar(onEdit: onEdit),
          ],
        ),
      ),
    );
  }

  static String _formatDate(DateTime value) {
    final local = value.toLocal();
    return '${local.year}.${local.month.toString().padLeft(2, '0')}.${local.day.toString().padLeft(2, '0')}';
  }

  static String _visibilityLabel(
    BuildContext context,
    ContentVisibility visibility,
  ) {
    return switch (visibility) {
      ContentVisibility.private => context.uiCopy(zh: '私人', en: 'private'),
      ContentVisibility.followers => context.uiCopy(
        zh: '僅限已核准的追蹤者',
        en: 'approved followers',
      ),
      ContentVisibility.unlisted => context.uiCopy(zh: '未列出', en: 'unlisted'),
      ContentVisibility.public => context.uiCopy(zh: '公開', en: 'public'),
    };
  }

  static Color _visibilityColor(ContentVisibility visibility) {
    return switch (visibility) {
      ContentVisibility.private => AnsibleDesign.inkMuted,
      ContentVisibility.followers => AnsibleDesign.lavender,
      ContentVisibility.unlisted => AnsibleDesign.spore,
      ContentVisibility.public => AnsibleDesign.accent,
    };
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.note, required this.onEdit});

  final ContentItem note;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 8, 22, 6),
      child: Row(
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => Navigator.of(context).maybePop(),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                context.uiCopy(zh: '← 草地', en: '← Home'),
                style: const TextStyle(
                  fontFamily: AnsibleDesign.mono,
                  fontSize: AnsibleDesign.navTextSize,
                  color: AnsibleDesign.inkMuted,
                  letterSpacing: 1.6,
                ),
              ),
            ),
          ),
          const Spacer(),
          AnsibleStatusChip(
            label: NoteDetailScreen._visibilityLabel(context, note.visibility),
            dot: NoteDetailScreen._visibilityColor(note.visibility),
          ),
          const SizedBox(width: 10),
          PopupMenuButton<String>(
            tooltip: context.uiCopy(zh: '更多', en: 'More'),
            icon: const Text(
              '···',
              style: TextStyle(
                fontFamily: AnsibleDesign.mono,
                fontSize: 13,
                color: AnsibleDesign.inkMuted,
                letterSpacing: 1,
              ),
            ),
            onSelected: (value) {
              if (value == 'edit' && onEdit != null) {
                Navigator.of(context).pop();
                onEdit!();
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'edit',
                enabled: onEdit != null,
                child: Text(context.uiCopy(zh: '編輯', en: 'Edit')),
              ),
              PopupMenuItem(
                value: 'share',
                enabled: false,
                child: Text(context.uiCopy(zh: '分享', en: 'Share')),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LineageRail extends StatelessWidget {
  const _LineageRail({
    required this.count,
    required this.start,
    required this.end,
  });

  final int count;
  final DateTime start;
  final DateTime end;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        CustomPaint(
          size: const Size(44, 10),
          painter: _LineageDotsPainter(count),
        ),
        const SizedBox(width: 10),
        Text(
          context.uiCopy(
            zh: '由 $count 個 murmur 編成',
            en: 'Built from $count murmurs',
          ),
          style: const TextStyle(fontSize: 11.5, color: AnsibleDesign.inkFaint),
        ),
        const Spacer(),
        Text(
          '${_shortDate(start)} → ${_shortDate(end)}',
          style: const TextStyle(
            fontFamily: AnsibleDesign.mono,
            fontSize: 9,
            letterSpacing: 1,
            color: AnsibleDesign.inkFaint,
          ),
        ),
      ],
    );
  }

  static String _shortDate(DateTime value) {
    final local = value.toLocal();
    return '${local.month.toString().padLeft(2, '0')}.${local.day.toString().padLeft(2, '0')}';
  }
}

class _LineageDotsPainter extends CustomPainter {
  const _LineageDotsPainter(this.count);

  final int count;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = AnsibleDesign.inkFaint;
    const xs = [3.0, 11.0, 18.0, 26.0, 32.0, 40.0];
    final visibleCount = count.clamp(0, xs.length);
    for (var i = 0; i < visibleCount; i += 1) {
      paint.color = AnsibleDesign.inkFaint.withValues(alpha: 0.35 + i * 0.1);
      canvas.drawCircle(Offset(xs[i], size.height / 2), 1.5, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _LineageDotsPainter oldDelegate) {
    return oldDelegate.count != count;
  }
}

class _SourceLineageSection extends StatelessWidget {
  const _SourceLineageSection({required this.sourceMurmurs});

  final List<ContentItem> sourceMurmurs;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _MetaLabel(context.uiCopy(zh: '來源 · LINEAGE', en: 'LINEAGE')),
        const SizedBox(height: 8),
        if (sourceMurmurs.isEmpty)
          Text(
            context.uiCopy(
              zh: '尚未連結 murmur 來源。',
              en: 'No murmur sources linked yet.',
            ),
            style: const TextStyle(
              fontSize: 12,
              height: 1.6,
              color: AnsibleDesign.inkMuted,
              fontStyle: FontStyle.italic,
            ),
          )
        else
          for (final murmur in sourceMurmurs.take(4))
            Padding(
              padding: const EdgeInsets.only(bottom: 7),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  SizedBox(
                    width: 86,
                    child: Text(
                      _formatMurmurTime(murmur.createdAt),
                      style: const TextStyle(
                        fontFamily: AnsibleDesign.mono,
                        fontSize: 9,
                        letterSpacing: 1,
                        color: AnsibleDesign.inkFaint,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      murmur.body,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AnsibleDesign.inkMuted,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        if (sourceMurmurs.length > 4)
          Text(
            context.uiCopy(
              zh: '+ 還有 ${sourceMurmurs.length - 4} 則',
              en: '+ ${sourceMurmurs.length - 4} more',
            ),
            style: const TextStyle(
              fontFamily: AnsibleDesign.mono,
              fontSize: 9,
              color: AnsibleDesign.inkFaint,
              letterSpacing: 1,
            ),
          ),
      ],
    );
  }

  static String _formatMurmurTime(DateTime value) {
    final local = value.toLocal();
    return '${local.month.toString().padLeft(2, '0')}.${local.day.toString().padLeft(2, '0')} ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }
}

class _BottomActionBar extends StatelessWidget {
  const _BottomActionBar({required this.onEdit});

  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(22, 12, 22, 12),
      decoration: const BoxDecoration(
        color: AnsibleDesign.paperElev,
        border: Border(
          top: BorderSide(color: AnsibleDesign.ruleSoft, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          _TextAction(
            label: context.uiCopy(zh: '編輯', en: 'Edit'),
            onTap: onEdit == null
                ? () => _showPending(context)
                : () {
                    Navigator.of(context).pop();
                    onEdit!();
                  },
          ),
          const SizedBox(width: 18),
          _TextAction(
            label: context.uiCopy(zh: '分享', en: 'Share'),
            onTap: () => _showPending(context),
          ),
          const Spacer(),
          OutlinedButton(
            onPressed: () => _showPending(context),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              visualDensity: VisualDensity.compact,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const _AccentDot(),
                const SizedBox(width: 8),
                Text(
                  context.uiCopy(
                    zh: '請 AI 整理這篇 →',
                    en: 'Ask AI to organize this →',
                  ),
                  style: const TextStyle(fontSize: 12, letterSpacing: 0.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showPending(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          context.uiCopy(
            zh: '這個動作還沒有開放',
            en: 'This action is not available yet',
          ),
        ),
      ),
    );
  }
}

class _TextAction extends StatelessWidget {
  const _TextAction({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(
          label,
          style: const TextStyle(
            fontFamily: AnsibleDesign.mono,
            fontSize: 10,
            letterSpacing: 1.4,
            color: AnsibleDesign.inkMuted,
          ),
        ),
      ),
    );
  }
}

class _AccentDot extends StatelessWidget {
  const _AccentDot();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 5,
      height: 5,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: AnsibleDesign.accent,
      ),
    );
  }
}

class _Hairline extends StatelessWidget {
  const _Hairline({this.margin = EdgeInsets.zero});

  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 0.5,
      margin: margin,
      color: AnsibleDesign.ruleSoft,
    );
  }
}

class _MetaLabel extends StatelessWidget {
  const _MetaLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: const TextStyle(
        fontFamily: AnsibleDesign.mono,
        fontSize: 11,
        letterSpacing: 1.8,
        color: AnsibleDesign.inkFaint,
      ),
    );
  }
}
