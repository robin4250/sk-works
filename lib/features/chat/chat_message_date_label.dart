import 'package:flutter/material.dart';

/// Message and reference dates are compared in the device's local time zone.
String chatMessageDateLabel(String? sentAt, {DateTime? now}) {
  final sent = sentAt == null ? null : DateTime.tryParse(sentAt)?.toLocal();
  if (sent == null) return '';
  final today = (now ?? DateTime.now()).toLocal();
  if (sent.year != today.year) {
    return '${sent.year}年${sent.month}月${sent.day}日';
  }
  if (sent.month != today.month) return '${sent.month}月${sent.day}日';
  return sent.day == today.day ? '' : '${sent.day}日';
}

/// A compact date above the message; the existing adjacent time stays intact.
class ChatMessageDateLabel extends StatelessWidget {
  const ChatMessageDateLabel({super.key, required this.sentAt, this.now});

  final String? sentAt;
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final label = chatMessageDateLabel(sentAt, now: now);
    if (label.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          fontSize: 10,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
