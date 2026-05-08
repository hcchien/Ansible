import 'package:ansible_store/ansible_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

import '../theme/ansible_design.dart';
import 'murmur_detail_screen.dart';

class MurmurScreen extends StatefulWidget {
  const MurmurScreen({
    super.key,
    required this.authorDid,
    this.contentItemRepository,
    this.recentMurmurs = const [],
    this.onSaved,
  });

  final String authorDid;
  final ContentItemRepository? contentItemRepository;
  final List<ContentItem> recentMurmurs;
  final Future<void> Function()? onSaved;

  @override
  State<MurmurScreen> createState() => _MurmurScreenState();
}

class _MurmurScreenState extends State<MurmurScreen> {
  static const _limit = 500;
  final _bodyController = TextEditingController();
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
    await widget.contentItemRepository!.create(
      ContentItem(
        id: const Uuid().v4(),
        authorDid: widget.authorDid,
        mode: ContentMode.murmur,
        body: body,
        status: ContentStatus.active,
        visibility: ContentVisibility.private,
        createdAt: now,
        updatedAt: now,
      ),
    );
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
              const Text(
                '一句話、一個直覺、一個還沒理順的問題都可以。沒人會看到。',
                style: TextStyle(
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
              const Row(
                children: [
                  AnsibleStatusChip(
                    label: 'PRIVATE',
                    dot: AnsibleDesign.inkMuted,
                  ),
                  SizedBox(width: 8),
                  Text(
                    '預設只給自己',
                    style: TextStyle(
                      color: AnsibleDesign.inkFaint,
                      fontStyle: FontStyle.italic,
                      fontSize: 12,
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
                  _RecentMurmurRow(murmur: murmur),
            ],
          ),
        ),
      ],
    );
  }
}

class _RecentMurmurRow extends StatelessWidget {
  const _RecentMurmurRow({required this.murmur});

  final ContentItem murmur;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => MurmurDetailScreen(murmur: murmur)),
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 11),
        decoration: const BoxDecoration(
          border: Border(
            bottom: BorderSide(color: AnsibleDesign.ruleSoft, width: 0.5),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 5,
              height: 5,
              margin: const EdgeInsets.only(top: 8),
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: AnsibleDesign.inkFaint,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                murmur.body,
                style: const TextStyle(
                  fontSize: 14,
                  height: 1.55,
                  color: AnsibleDesign.ink,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Text(
              _formatTime(murmur.createdAt),
              style: const TextStyle(
                fontFamily: AnsibleDesign.mono,
                fontSize: 9,
                color: AnsibleDesign.inkFaint,
                letterSpacing: 0.8,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime value) {
    return '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
  }
}
