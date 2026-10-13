import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/chat/line_attendance_candidate_parser.dart';
import 'package:sk_works/features/chat/line_attendance_candidate_validator.dart';

LineAttendanceCandidate candidate({
  required int day,
  required String site,
  required String worker,
}) {
  return LineAttendanceCandidate(
    workDate: DateTime(2026, 9, day),
    siteName: site,
    workerName: worker,
    sourceSender: '三嶋',
    sourceTimestamp: DateTime(2026, 9, day, 7),
  );
}

void main() {
  group('LineAttendanceCandidateValidator', () {
    test('removes exact duplicate attendance candidates', () {
      final result = const LineAttendanceCandidateValidator().validate([
        candidate(day: 18, site: '東京海上', worker: '三嶋'),
        candidate(day: 18, site: '東京海上', worker: '三嶋'),
        candidate(day: 18, site: '江戸川', worker: '秋元'),
      ]);

      expect(result.uniqueCandidates, hasLength(2));
      expect(result.duplicateCount, 1);
      expect(result.conflicts, isEmpty);
    });

    test('flags same worker assigned to multiple sites on the same day', () {
      final result = const LineAttendanceCandidateValidator().validate([
        candidate(day: 18, site: '東京海上', worker: '三嶋'),
        candidate(day: 18, site: '江戸川', worker: '三嶋'),
        candidate(day: 18, site: '江戸川', worker: '秋元'),
      ]);

      expect(result.uniqueCandidates, hasLength(3));
      expect(result.duplicateCount, 0);
      expect(result.conflicts, hasLength(1));
      expect(result.conflicts.single.workerName, '三嶋');
      expect(result.conflicts.single.siteNames, ['東京海上', '江戸川']);
    });

    test('does not flag same worker on different dates', () {
      final result = const LineAttendanceCandidateValidator().validate([
        candidate(day: 17, site: '東京海上', worker: '三嶋'),
        candidate(day: 18, site: '江戸川', worker: '三嶋'),
      ]);

      expect(result.conflicts, isEmpty);
    });
  });
}
