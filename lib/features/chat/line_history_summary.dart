import 'line_history_parser.dart';

class LineHistorySummary {
  const LineHistorySummary({
    required this.totalMessages,
    required this.firstTimestamp,
    required this.lastTimestamp,
    required this.messageCountBySender,
  });

  final int totalMessages;
  final DateTime? firstTimestamp;
  final DateTime? lastTimestamp;
  final Map<String, int> messageCountBySender;

  int get participantCount => messageCountBySender.length;

  factory LineHistorySummary.fromMessages(
    Iterable<LineHistoryMessage> messages,
  ) {
    final counts = <String, int>{};
    DateTime? firstTimestamp;
    DateTime? lastTimestamp;
    var totalMessages = 0;

    for (final message in messages) {
      totalMessages += 1;
      counts.update(message.sender, (value) => value + 1, ifAbsent: () => 1);

      if (firstTimestamp == null || message.timestamp.isBefore(firstTimestamp)) {
        firstTimestamp = message.timestamp;
      }
      if (lastTimestamp == null || message.timestamp.isAfter(lastTimestamp)) {
        lastTimestamp = message.timestamp;
      }
    }

    final sortedEntries = counts.entries.toList()
      ..sort((a, b) {
        final countOrder = b.value.compareTo(a.value);
        if (countOrder != 0) return countOrder;
        return a.key.compareTo(b.key);
      });

    return LineHistorySummary(
      totalMessages: totalMessages,
      firstTimestamp: firstTimestamp,
      lastTimestamp: lastTimestamp,
      messageCountBySender: Map.unmodifiable({
        for (final entry in sortedEntries) entry.key: entry.value,
      }),
    );
  }
}
