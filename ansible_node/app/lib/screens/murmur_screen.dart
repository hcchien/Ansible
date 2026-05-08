import 'package:ansible_store/ansible_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

class MurmurScreen extends StatefulWidget {
  const MurmurScreen({
    super.key,
    required this.authorDid,
    this.contentItemRepository,
  });

  final String authorDid;
  final ContentItemRepository? contentItemRepository;

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
    setState(() {
      _saving = false;
      _bodyController.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        const Text(
          '捕捉 Murmur',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        const Text(
          'Private, local-only by default.',
          style: TextStyle(color: Colors.white70),
        ),
        const SizedBox(height: 16),
        TextField(
          key: const Key('murmur_body_field'),
          controller: _bodyController,
          maxLength: _limit,
          minLines: 7,
          maxLines: 10,
          inputFormatters: [LengthLimitingTextInputFormatter(_limit)],
          buildCounter:
              (
                context, {
                required currentLength,
                required isFocused,
                required maxLength,
              }) {
                return Text(
                  '$currentLength / $maxLength',
                  style: const TextStyle(color: Colors.white60),
                );
              },
          decoration: const InputDecoration(
            hintText: 'Write a raw thought before it becomes a note.',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: const Icon(Icons.add_comment_outlined),
            label: const Text('Save murmur'),
          ),
        ),
      ],
    );
  }
}
