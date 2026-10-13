import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/chat/line_attendance_reference_matcher.dart';

void main() {
  group('LineAttendanceReferenceMatcher', () {
    const matcher = LineAttendanceReferenceMatcher();

    test('matches exact normalized site names', () {
      final result = matcher.match(
        input: ' 東京海上 ',
        candidates: const ['東京海上', '愛宕', '江戸川'],
      );

      expect(result.isMatched, isTrue);
      expect(result.matchedValue, '東京海上');
      expect(result.isAmbiguous, isFalse);
    });

    test('normalizes spaces and Japanese parentheses only', () {
      final result = matcher.match(
        input: '飯chan.D1 （錦糸町）',
        candidates: const ['飯chan.D1(錦糸町)', '別店舗'],
      );

      expect(result.isMatched, isTrue);
      expect(result.matchedValue, '飯chan.D1(錦糸町)');
    });

    test('does not fuzzy-match different names', () {
      final result = matcher.match(
        input: '東京海上',
        candidates: const ['東京海上日動', '東京海上本館'],
      );

      expect(result.isMatched, isFalse);
      expect(result.matchedValue, isNull);
      expect(result.isAmbiguous, isFalse);
    });

    test('marks duplicate normalized names as ambiguous', () {
      final result = matcher.match(
        input: '三上',
        candidates: const ['三上', ' 三 上 '],
      );

      expect(result.isMatched, isFalse);
      expect(result.matchedValue, isNull);
      expect(result.isAmbiguous, isTrue);
    });

    test('empty input never matches', () {
      final result = matcher.match(
        input: '   ',
        candidates: const ['東京海上'],
      );

      expect(result.isMatched, isFalse);
      expect(result.isAmbiguous, isFalse);
    });
  });
}
