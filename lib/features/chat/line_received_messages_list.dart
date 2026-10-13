import 'package:flutter/material.dart';

/// Rows are supplied in ascending source order. The viewport starts at the
/// newest post, while scrolling up reveals older posts in chronological order.
class LineReceivedMessagesList extends StatelessWidget {
  const LineReceivedMessagesList({super.key, required this.rows});
  final List<Map<String, dynamic>> rows;

  @override
  Widget build(BuildContext context) => ListView.separated(
    reverse: true,
    padding: const EdgeInsets.all(16),
    itemCount: rows.length,
    separatorBuilder: (_, index) => const SizedBox(height: 12),
    itemBuilder: (context, index) {
      final row = rows[rows.length - 1 - index];
      final at = DateTime.tryParse(row['sent_at']?.toString() ?? '')?.toLocal();
      final date = at == null ? '' : '  ${at.year}/${at.month.toString().padLeft(2, '0')}/${at.day.toString().padLeft(2, '0')} ${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';
      return Card(child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${row['sender_display_name'] ?? 'LINE'}$date',
            style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: 8),
          SelectableText(row['body']?.toString() ?? ''),
        ]),
      ));
    },
  );
}
