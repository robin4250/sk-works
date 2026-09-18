import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/chat/line_history_parser.dart';
import 'package:sk_works/features/chat/line_history_summary.dart';

void main() {
  group('LineHistorySummary', () {
    test('summarizes participants, date range, and message counts', () {
      final messages = [
        LineHistoryMessage(
          timestamp: DateTime(2026, 9, 18, 8, 15),
          sender: '田中',
          body: '開始',
        ),
        LineHistoryMessage(
          timestamp: DateTime(2026, 9, 18, 8, 16),
          sender: '佐藤',
          body: '到着',
        ),
        LineHistoryMessage(
          timestamp: DateTime(2026, 9, 19, 7, 55),
          sender: '田中',
          body: '開始',
        ),
      ];

      final summary = LineHistorySummary.fromMessages(messages);

      expect(summary.totalMessages, 3);
      expect(summary.participantCount, 2);
      expect(summary.firstTimestamp, DateTime(2026, 9, 18, 8, 15));
      expect(summary.lastTimestamp, DateTime(2026, 9, 19, 7, 55));
      expect(summary.messageCountBySender.keys.toList(), ['田中', '佐藤']);
      expect(summary.messageCountBySender['田中'], 2);
      expect(summary.messageCountBySender['佐藤'], 1);
    });

    test('handles an empty preview', () {
      final summary = LineHistorySummary.fromMessages(
        const <LineHistoryMessage>[],
      );

      expect(summary.totalMessages, 0);
      expect(summary.participantCount, 0);
      expect(summary.firstTimestamp, isNull);
      expect(summary.lastTimestamp, isNull);
      expect(summary.messageCountBySender, isEmpty);
    });
  });
}
