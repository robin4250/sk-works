import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/chat/line_attendance_candidate_parser.dart';
import 'package:sk_works/features/chat/line_history_parser.dart';

void main() {
  group('LineAttendanceCandidateParser', () {
    test('extracts site and workers from dated attendance messages', () {
      final messages = <LineHistoryMessage>[
        LineHistoryMessage(
          timestamp: DateTime(2026, 9, 17, 6, 33),
          sender: '三嶋',
          body: '9月7日（月）\n東京海上　三嶋、三上\n愛宕　　　寺島\n江戸川　　秋元',
        ),
      ];

      final result = const LineAttendanceCandidateParser().parseMessages(messages);

      expect(result, hasLength(4));
      expect(result[0].workDate, DateTime(2026, 9, 7));
      expect(result[0].siteName, '東京海上');
      expect(result[0].workerName, '三嶋');
      expect(result[1].workerName, '三上');
      expect(result[2].siteName, '愛宕');
      expect(result[2].workerName, '寺島');
      expect(result[3].siteName, '江戸川');
      expect(result[3].workerName, '秋元');
    });

    test('supports site line followed by an explicit worker list', () {
      final messages = <LineHistoryMessage>[
        LineHistoryMessage(
          timestamp: DateTime(2026, 2, 17, 7, 28),
          sender: '三嶋',
          body: '2月16日(月)\n守谷　三嶋\n愛宕　寺島\n江戸川\n秋元、三上',
        ),
      ];

      final result = const LineAttendanceCandidateParser().parseMessages(messages);

      expect(result, hasLength(4));
      expect(result[2].siteName, '江戸川');
      expect(result[2].workerName, '秋元');
      expect(result[3].siteName, '江戸川');
      expect(result[3].workerName, '三上');
    });

    test('ignores overtime and fixed-time status messages', () {
      final messages = <LineHistoryMessage>[
        LineHistoryMessage(
          timestamp: DateTime(2026, 4, 7, 6, 31),
          sender: '三嶋',
          body: '4月6日(月)\n東京海上　定時〈鉄骨〉\n愛宕　　　残業１\n江戸川　　定時',
        ),
      ];

      final result = const LineAttendanceCandidateParser().parseMessages(messages);

      expect(result, isEmpty);
    });

    test('accepts full-width digits and explicit year', () {
      final messages = <LineHistoryMessage>[
        LineHistoryMessage(
          timestamp: DateTime(2026, 9, 17, 6, 35),
          sender: '三嶋',
          body: '２０２６年９月9日（水）\n東京海上　三嶋、三上',
        ),
      ];

      final result = const LineAttendanceCandidateParser().parseMessages(messages);

      expect(result, hasLength(2));
      expect(result.first.workDate, DateTime(2026, 9, 9));
    });

    test('accepts slash date format', () {
      final messages = <LineHistoryMessage>[
        LineHistoryMessage(
          timestamp: DateTime(2026, 9, 18, 7),
          sender: '三嶋',
          body: '9/18\n東京海上　三嶋',
        ),
      ];

      final result = const LineAttendanceCandidateParser().parseMessages(messages);

      expect(result, hasLength(1));
      expect(result.single.workDate, DateTime(2026, 9, 18));
    });

    test('does not guess an ambiguous site-only and single-name pair', () {
      final messages = <LineHistoryMessage>[
        LineHistoryMessage(
          timestamp: DateTime(2026, 9, 18, 7),
          sender: '三嶋',
          body: '9月18日\n江戸川\n秋元',
        ),
      ];

      final result = const LineAttendanceCandidateParser().parseMessages(messages);

      expect(result, isEmpty);
    });
  });
}
