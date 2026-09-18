import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/chat/line_attendance_status_parser.dart';

void main() {
  group('LineAttendanceStatusParser', () {
    const parser = LineAttendanceStatusParser();

    test('parses regular time and steel allowance', () {
      final result = parser.parse(
        '東京海上　定時〈鉄骨〉\n愛宕　　　定時\n江戸川　　定時',
      );

      expect(result, hasLength(3));
      expect(result[0].siteName, '東京海上');
      expect(result[0].isRegularTime, isTrue);
      expect(result[0].hasSteelAllowance, isTrue);
      expect(result[1].hasSteelAllowance, isFalse);
    });

    test('parses decimal overtime hours with optional H suffix', () {
      final result = parser.parse(
        '東京海上　残業2H〈鉄骨〉\n愛宕　残業0.5',
      );

      expect(result, hasLength(2));
      expect(result[0].overtimeHours, 2);
      expect(result[0].hasSteelAllowance, isTrue);
      expect(result[1].overtimeHours, 0.5);
    });

    test('normalizes full-width overtime digits', () {
      final result = parser.parse('愛宕　残業１．５');

      expect(result, hasLength(1));
      expect(result.single.overtimeHours, 1.5);
    });

    test('parses early and night work markers', () {
      final result = parser.parse(
        '現場A　早出1\n現場B　夜勤',
      );

      expect(result, hasLength(2));
      expect(result[0].earlyHours, 1);
      expect(result[1].isNightWork, isTrue);
    });

    test('ignores non-attendance text', () {
      final result = parser.parse(
        '9月18日(金)\n東京海上　三嶋、三上\nおはようございます',
      );

      expect(result, isEmpty);
    });
  });
}
