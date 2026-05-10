import 'package:ansible_store/ansible_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

import '../theme/ansible_design.dart';
import '../widgets/content_visibility_sheet.dart';
import 'murmur_detail_screen.dart';

class MurmurScreen extends StatefulWidget {
  const MurmurScreen({
    super.key,
    required this.authorDid,
    this.contentItemRepository,
    this.recentMurmurs = const [],
    this.murmurReferenceCounts = const {},
    this.onSaved,
    this.onPublishContentItem,
  });

  final String authorDid;
  final ContentItemRepository? contentItemRepository;
  final List<ContentItem> recentMurmurs;
  final Map<String, int> murmurReferenceCounts;
  final Future<void> Function()? onSaved;
  final Future<void> Function(
    ContentItem item,
    DistributionPreference preference,
  )?
  onPublishContentItem;

  @override
  State<MurmurScreen> createState() => _MurmurScreenState();
}

class _MurmurScreenState extends State<MurmurScreen> {
  static const _limit = 500;
  final _bodyController = TextEditingController();
  ContentVisibility _visibility = ContentVisibility.private;
  DistributionPreference _distributionPreference =
      DistributionPreference.localOnly;
  bool _saving = false;

  @override
  void dispose() {
    _bodyController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final body = _bodyController.text.trim();
    if (body.isEmpty || widget.contentItemRepository == null) return;
    setState(() => _saving = true);
    final now = DateTime.now().toUtc();
    final item = ContentItem(
      id: const Uuid().v4(),
      authorDid: widget.authorDid,
      mode: ContentMode.murmur,
      body: body,
      status: ContentStatus.active,
      visibility: _visibility,
      createdAt: now,
      updatedAt: now,
      localOnly: _visibility == ContentVisibility.private,
    );
    await widget.contentItemRepository!.create(item);
    if (_visibility != ContentVisibility.private) {
      await widget.onPublishContentItem?.call(item, _distributionPreference);
    }
    if (!mounted) return;
    await widget.onSaved?.call();
    if (!mounted) return;
    setState(() {
      _saving = false;
      _bodyController.clear();
    });
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('已送出')));
  }

  Future<void> _showVisibilitySheet() async {
    final choice = await showContentDistributionSheet(
      context: context,
      current: ContentDistributionChoice(
        visibility: _visibility,
        distributionPreference: _distributionPreference,
      ),
      subjectLabel: '這條 murmur',
    );
    if (choice == null || !mounted) return;
    setState(() {
      _visibility = choice.visibility;
      _distributionPreference = choice.distributionPreference;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              'MURMUR · 碎念',
              style: TextStyle(
                fontFamily: AnsibleDesign.mono,
                fontSize: 10,
                letterSpacing: 1.6,
                color: AnsibleDesign.inkFaint,
              ),
            ),
            const Spacer(),
            const AnsibleStatusChip(label: '本地', dot: AnsibleDesign.spore),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: const Text('送出'),
            ),
          ],
        ),
        const SizedBox(height: 18),
        Expanded(
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              const Text(
                '現在腦子裡\n有什麼半成形的東西嗎？',
                style: TextStyle(
                  fontSize: 23,
                  height: 1.4,
                  fontWeight: FontWeight.w500,
                  color: AnsibleDesign.ink,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _visibility == ContentVisibility.private
                    ? '一句話、一個直覺、一個還沒理順的問題都可以。沒人會看到。'
                    : '一句話、一個直覺、一個還沒理順的問題都可以。這則會標記為可同步。',
                style: const TextStyle(
                  fontSize: 13,
                  height: 1.65,
                  color: AnsibleDesign.inkMuted,
                  fontStyle: FontStyle.italic,
                ),
              ),
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
                decoration: BoxDecoration(
                  color: AnsibleDesign.paperElev,
                  border: Border.all(color: AnsibleDesign.rule, width: 0.5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: TextField(
                  key: const Key('murmur_body_field'),
                  controller: _bodyController,
                  maxLength: _limit,
                  minLines: 8,
                  maxLines: 12,
                  inputFormatters: [LengthLimitingTextInputFormatter(_limit)],
                  style: const TextStyle(
                    fontSize: 18,
                    height: 1.65,
                    color: AnsibleDesign.ink,
                  ),
                  buildCounter:
                      (
                        context, {
                        required currentLength,
                        required isFocused,
                        required maxLength,
                      }) {
                        return Text(
                          '$currentLength / $maxLength',
                          style: const TextStyle(
                            fontFamily: AnsibleDesign.mono,
                            color: AnsibleDesign.inkFaint,
                            fontSize: 9,
                            letterSpacing: 1,
                          ),
                        );
                      },
                  decoration: const InputDecoration(
                    hintText: '這幾個月一直在想的事情是',
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    filled: false,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  InkWell(
                    key: const Key('murmur_visibility_chip'),
                    borderRadius: BorderRadius.circular(999),
                    onTap: _showVisibilitySheet,
                    child: AnsibleStatusChip(
                      label: contentVisibilityMeta(_visibility).label,
                      dot: contentVisibilityMeta(_visibility).dot,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      switch (_visibility) {
                        ContentVisibility.private => '只給自己',
                        ContentVisibility.unlisted => '不列出但可同步',
                        ContentVisibility.public => '公開發布',
                      },
                      style: const TextStyle(
                        color: AnsibleDesign.inkFaint,
                        fontStyle: FontStyle.italic,
                        fontSize: 13.5,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 22),
              const AnsibleSectionHead(zh: '散落', en: 'LOOSE MURMURS'),
              if (widget.recentMurmurs.isEmpty)
                const Text(
                  '送出的碎念會先留在這裡。',
                  style: TextStyle(
                    color: AnsibleDesign.inkMuted,
                    fontStyle: FontStyle.italic,
                  ),
                )
              else
                for (final murmur in widget.recentMurmurs.reversed.take(5))
                  _RecentMurmurRow(
                    murmur: murmur,
                    contentItemRepository: widget.contentItemRepository,
                    referenceCount:
                        widget.murmurReferenceCounts[murmur.id] ?? 0,
                    onDeleted: widget.onSaved,
                  ),
            ],
          ),
        ),
      ],
    );
  }
}

class _RecentMurmurRow extends StatelessWidget {
  const _RecentMurmurRow({
    required this.murmur,
    this.contentItemRepository,
    this.referenceCount = 0,
    this.onDeleted,
  });

  final ContentItem murmur;
  final ContentItemRepository? contentItemRepository;
  final int referenceCount;
  final Future<void> Function()? onDeleted;

  @override
  Widget build(BuildContext context) {
    final row = InkWell(
      key: Key('murmur_row_${murmur.id}'),
      onTap: () => _openDetail(context),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: const BoxDecoration(
          color: AnsibleDesign.paper,
          border: Border(
            bottom: BorderSide(color: AnsibleDesign.ruleSoft, width: 0.5),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  'MURMUR · ${_formatDate(murmur.createdAt)}',
                  style: const TextStyle(
                    fontFamily: AnsibleDesign.mono,
                    fontSize: 8.5,
                    color: AnsibleDesign.inkFaint,
                    letterSpacing: 1.4,
                  ),
                ),
                const SizedBox(width: 8),
                AnsibleStatusChip(
                  label: contentVisibilityMeta(murmur.visibility).label,
                  dot: contentVisibilityMeta(murmur.visibility).dot,
                ),
                const Spacer(),
                Text(
                  referenceCount == 0 ? '未使用' : '$referenceCount 篇引用',
                  style: const TextStyle(
                    fontFamily: AnsibleDesign.mono,
                    fontSize: 9,
                    color: AnsibleDesign.inkFaint,
                    letterSpacing: 0.8,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              murmur.body,
              style: const TextStyle(
                fontSize: AnsibleDesign.readingTextSize,
                height: 1.6,
                color: AnsibleDesign.ink,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
      ),
    );

    if (contentItemRepository == null) {
      return row;
    }

    return Dismissible(
      key: Key('dismissible_murmur_${murmur.id}'),
      direction: DismissDirection.endToStart,
      background: const _DeleteBackground(),
      confirmDismiss: (_) => _confirmDelete(context),
      child: row,
    );
  }

  void _openDetail(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MurmurDetailScreen(
          murmur: murmur,
          contentItemRepository: contentItemRepository,
          onDeleted: onDeleted,
        ),
      ),
    );
  }

  Future<bool> _confirmDelete(BuildContext context) async {
    final repository = contentItemRepository;
    if (repository == null) return false;

    final confirmed = await showMurmurDeleteSheet(
      context: context,
      murmur: murmur,
      referenceCount: referenceCount,
    );
    if (confirmed != true || !context.mounted) return false;

    if (referenceCount > 0) {
      final secondConfirmed = await showMurmurReferenceDeleteSheet(
        context: context,
        referenceCount: referenceCount,
      );
      if (secondConfirmed != true || !context.mounted) return false;
    }

    await repository.delete(murmur.id);
    await onDeleted?.call();
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('已刪除碎念')));
    }
    return true;
  }

  String _formatDate(DateTime value) {
    return '${value.month.toString().padLeft(2, '0')}.${value.day.toString().padLeft(2, '0')}';
  }
}

class _DeleteBackground extends StatelessWidget {
  const _DeleteBackground();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: AnsibleDesign.ruleSoft, width: 0.5),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Container(
            width: 84,
            color: AnsibleDesign.paperElev,
            alignment: Alignment.center,
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.remove_rounded,
                  size: 14,
                  color: AnsibleDesign.inkMuted,
                ),
                SizedBox(width: 6),
                Text(
                  '收起',
                  style: TextStyle(fontSize: 12, color: AnsibleDesign.inkMuted),
                ),
              ],
            ),
          ),
          Container(
            width: 84,
            color: AnsibleDesign.danger,
            alignment: Alignment.center,
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.delete_outline_rounded,
                  size: 15,
                  color: AnsibleDesign.paper,
                ),
                SizedBox(width: 6),
                Text(
                  '刪除',
                  style: TextStyle(
                    fontSize: 13.5,
                    color: AnsibleDesign.paper,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

Future<bool?> showMurmurDeleteSheet({
  required BuildContext context,
  required ContentItem murmur,
  required int referenceCount,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: AnsibleDesign.ink.withValues(alpha: 0.22),
    builder: (sheetContext) {
      return SafeArea(
        top: false,
        child: _MurmurDeleteSheet(
          murmur: murmur,
          referenceCount: referenceCount,
          onCancel: () => Navigator.of(sheetContext).pop(false),
          onDelete: () => Navigator.of(sheetContext).pop(true),
        ),
      );
    },
  );
}

Future<bool?> showMurmurReferenceDeleteSheet({
  required BuildContext context,
  required int referenceCount,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: AnsibleDesign.ink.withValues(alpha: 0.24),
    builder: (sheetContext) {
      return SafeArea(
        top: false,
        child: _BottomActionSheet(
          label: '引用 · REFERENCES',
          title: '確定要讓引用斷開？',
          body:
              '這條 murmur 已經被 $referenceCount 篇 note 引用。刪除後，note 會保留文字，但來源會標記為已移除。',
          cancelLabel: '返回',
          actionLabel: '仍然刪除',
          actionColor: AnsibleDesign.danger,
          onCancel: () => Navigator.of(sheetContext).pop(false),
          onAction: () => Navigator.of(sheetContext).pop(true),
        ),
      );
    },
  );
}

class _MurmurDeleteSheet extends StatelessWidget {
  const _MurmurDeleteSheet({
    required this.murmur,
    required this.referenceCount,
    required this.onCancel,
    required this.onDelete,
  });

  final ContentItem murmur;
  final int referenceCount;
  final VoidCallback onCancel;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return _BottomActionSheet(
      label: '刪除 · DELETE',
      title: '把這條 murmur 拔掉？',
      body: referenceCount == 0
          ? '還沒被任何 note 用過。刪掉之後不留痕跡。'
          : '這條 murmur 已經被 $referenceCount 篇 note 引用。',
      preview: Container(
        margin: const EdgeInsets.fromLTRB(0, 14, 0, 12),
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: const BoxDecoration(
          color: AnsibleDesign.paperElev,
          border: Border(
            left: BorderSide(color: AnsibleDesign.inkFaint, width: 1.5),
          ),
          borderRadius: BorderRadius.only(
            topRight: Radius.circular(6),
            bottomRight: Radius.circular(6),
          ),
        ),
        child: Text(
          murmur.body,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 13,
            height: 1.5,
            color: AnsibleDesign.ink,
            fontStyle: FontStyle.italic,
          ),
        ),
      ),
      footer: const Padding(
        padding: EdgeInsets.only(top: 12),
        child: Center(
          child: Text(
            '被引用過的 murmur 會多問一次——不會直接消失。',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 11,
              color: AnsibleDesign.inkFaint,
              fontStyle: FontStyle.italic,
            ),
          ),
        ),
      ),
      cancelLabel: '留著',
      actionLabel: '刪除',
      actionColor: AnsibleDesign.danger,
      onCancel: onCancel,
      onAction: onDelete,
    );
  }
}

class _BottomActionSheet extends StatelessWidget {
  const _BottomActionSheet({
    required this.label,
    required this.title,
    required this.body,
    required this.cancelLabel,
    required this.actionLabel,
    required this.actionColor,
    required this.onCancel,
    required this.onAction,
    this.preview,
    this.footer,
  });

  final String label;
  final String title;
  final String body;
  final String cancelLabel;
  final String actionLabel;
  final Color actionColor;
  final VoidCallback onCancel;
  final VoidCallback onAction;
  final Widget? preview;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AnsibleDesign.paper,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
        boxShadow: [
          BoxShadow(
            color: AnsibleDesign.ink.withValues(alpha: 0.20),
            blurRadius: 40,
            offset: const Offset(0, -10),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(22, 8, 22, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 32,
              height: 4,
              margin: const EdgeInsets.only(bottom: 14),
              decoration: BoxDecoration(
                color: AnsibleDesign.rule,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Text(
            label,
            style: const TextStyle(
              fontFamily: AnsibleDesign.mono,
              fontSize: 9.5,
              color: AnsibleDesign.danger,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            title,
            style: const TextStyle(
              fontSize: 19,
              height: 1.4,
              fontWeight: FontWeight.w500,
              color: AnsibleDesign.ink,
            ),
          ),
          if (preview != null) preview!,
          Text(
            body,
            style: const TextStyle(
              fontSize: 12.5,
              height: 1.65,
              color: AnsibleDesign.inkMuted,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: onCancel,
                  child: Text(cancelLabel),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  onPressed: onAction,
                  style: FilledButton.styleFrom(backgroundColor: actionColor),
                  child: Text(actionLabel),
                ),
              ),
            ],
          ),
          if (footer != null) footer!,
        ],
      ),
    );
  }
}
