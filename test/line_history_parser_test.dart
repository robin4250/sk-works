import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/chat/line_history_parser.dart';

void main() {
  group('LineHistoryParser', () {
    test('parses dated LINE export messages and multiline bodies', () {
      const source = '''
[LINE] 現場グループのトーク履歴
保存日時：2026/09/18 19:00
2026/09/18(金)
08:15\t田中\tおはようございます
08:16\t佐藤\t現場に着きました
写真は後で送ります
2026/09/19(土)
07:55\t田中\t本日もよろしくお願いします
''';

      final result = const LineHistoryParser().parse(source);

      expect(result.messages, hasLength(3));
      expect(result.messages[0].sender, '田中');
      expect(result.messages[0].body, 'おはようございます');
      expect(result.messages[0].timestamp, DateTime(2026, 9, 18, 8, 15));
      expect(result.messages[1].sender, '佐藤');
      expect(result.messages[1].body, '現場に着きました\n写真は後で送ります');
      expect(result.messages[2].timestamp, DateTime(2026, 9, 19, 7, 55));
      expect(result.ignoredLineCount, 2);
    });

    test('ignores timestamped system lines without a sender and message field', () {
      const source = '''
2026/09/18(金)
08:00\t田中がグループに参加しました。
08:10\t鈴木\t作業開始します
''';

      final result = const LineHistoryParser().parse(source);

      expect(result.messages, hasLength(1));
      expect(result.messages.single.sender, '鈴木');
      expect(result.messages.single.body, '作業開始します');
      expect(result.ignoredLineCount, 1);
    });

    test('accepts dot and Japanese date separators', () {
      const source = '''
2026.9.18
09:00\tA\tdot format
2026年9月19日
09:30\tB\tJapanese format
''';

      final result = const LineHistoryParser().parse(source);

      expect(result.messages, hasLength(2));
      expect(result.messages[0].timestamp, DateTime(2026, 9, 18, 9));
      expect(result.messages[1].timestamp, DateTime(2026, 9, 19, 9, 30));
    });
  });
}
