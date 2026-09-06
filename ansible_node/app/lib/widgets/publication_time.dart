import 'package:flutter/material.dart';

/// Publication time in the reader's local timezone, never the sync/edit time.
class PublicationTime extends StatelessWidget {
  const PublicationTime({super.key, required this.date, required this.color});

  final DateTime date;
  final Color color;

  static String label(DateTime date) {
    final local = date.toLocal();
    String pad(int value) => value.toString().padLeft(2, '0');
    return '${local.year}-${pad(local.month)}-${pad(local.day)} '
        '${pad(local.hour)}:${pad(local.minute)}';
  }

  @override
  Widget build(BuildContext context) =>
      Text(label(date), style: TextStyle(fontSize: 12, color: color));
}
