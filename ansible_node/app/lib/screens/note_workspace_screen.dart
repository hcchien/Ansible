import 'package:ansible_store/ansible_store.dart';
import 'package:flutter/material.dart';

class NoteWorkspaceScreen extends StatelessWidget {
  const NoteWorkspaceScreen({super.key, this.notes = const []});

  final List<ContentItem> notes;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        const Text(
          'Notes',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.04),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Row(
            children: [
              Icon(Icons.link, size: 18, color: Color(0xFFFFB76B)),
              SizedBox(width: 8),
              Text(
                'Linked murmurs',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (notes.isEmpty)
          const Text('No notes yet.', style: TextStyle(color: Colors.white70))
        else
          for (final note in notes)
            ListTile(
              title: Text(note.title ?? 'Untitled note'),
              subtitle: Text(
                note.body,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
      ],
    );
  }
}
