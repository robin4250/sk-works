import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/attendance/attendance_shift_context.dart';
import 'package:sk_works/features/attendance/attendance_work_date.dart';

Map<String, dynamic> event(String id, String type, String at, {
  String worker = 'worker-a', String? source, String? workDate,
  String? site = 'site-a', String? route,
}) => {
  'id': id, 'worker_id': worker, 'event_type': type, 'confirmed_at': at,
  'source_clock_in_id': source, 'work_date': workDate,
  'site_id': site, 'route_assignment_id': route, 'verification_mode': 'gps_auto',
  'sites': {'name': 'Site A'}, 'route_assignments': {'route_name': 'Route A'},
};

void main() {
  for (final boundary in [
    ['2026-10-31', '2026-11-01'],
    ['2026-12-31', '2027-01-01'],
    ['2026-10-08', '2026-10-09'],
  ]) {
    final previous = boundary[0];
    final next = boundary[1];
    test('unclosed GPS start remains eligible next morning across $previous', () {
      final rows = [event('start', 'clock_in', '${previous}T20:00:00', workDate: previous)];
      final shifts = openAttendanceShifts(rows, workerId: 'worker-a', now: DateTime.parse('${next}T05:00:00'));
      expect(shifts.single.id, 'start');
      expect(shifts.single.workDate, DateTime.parse(previous));
      expect(shifts.single.clockIn, DateTime.parse('${previous}T20:00:00'));
    });
    test('explicit end closes its start and belongs to original month $previous', () {
      final start = event('start', 'clock_in', '${previous}T20:00:00', workDate: previous);
      final end = event('end', 'clock_out', '${next}T05:00:00', source: 'start', workDate: previous);
      expect(openAttendanceShifts([start, end], workerId: 'worker-a', now: DateTime.parse('${next}T06:00:00')), isEmpty);
      expect(attendanceEventWorkDate(DateTime.parse('${next}T05:00:00'), null, workDate: end['work_date']), DateTime.parse(previous));
      expect(end['confirmed_at'], '${next}T05:00:00');
    });
    test('new daytime start remains eligible after overnight end $previous', () {
      final rows = [
        event('night', 'clock_in', '${previous}T20:00:00', workDate: previous),
        event('out', 'clock_out', '${next}T05:00:00', source: 'night', workDate: previous),
        event('day', 'clock_in', '${next}T08:00:00', workDate: next),
      ];
      expect(openAttendanceShifts(rows.reversed, workerId: 'worker-a', now: DateTime.parse('${next}T09:00:00')).single.id, 'day');
    });
  }
  test('multiple starts are returned, never silently reduced to the latest', () {
    final rows = [
      event('second', 'clock_in', '2026-10-09T02:00:00', site: null, route: 'route-a'),
      event('first', 'clock_in', '2026-10-08T20:00:00'),
    ];
    final shifts = openAttendanceShifts(rows, workerId: 'worker-a', now: DateTime(2026, 10, 9, 5));
    expect(shifts.map((s) => s.id), ['first', 'second']);
    expect(shifts.last.routeId, 'route-a');
    expect(shifts.last.siteId, isNull);
  });
  test('source end does not close a different start', () {
    final rows = [
      event('a', 'clock_in', '2026-10-08T20:00:00'),
      event('b', 'clock_in', '2026-10-08T22:00:00'),
      event('out', 'clock_out', '2026-10-09T05:00:00', source: 'a'),
    ];
    expect(openAttendanceShifts(rows, workerId: 'worker-a', now: DateTime(2026, 10, 9, 6)).single.id, 'b');
  });
  test('old unlinked ends retain civil date and prevent ambiguous reuse', () {
    final rows = [event('start', 'clock_in', '2026-10-08T20:00:00'), event('legacy-end', 'clock_out', '2026-10-09T05:00:00')];
    expect(openAttendanceShifts(rows, workerId: 'worker-a', now: DateTime(2026, 10, 9, 6)), isEmpty);
    expect(attendanceEventWorkDate(DateTime(2026, 10, 9, 5), null), DateTime(2026, 10, 9));
    expect(rows.last['source_clock_in_id'], isNull);
  });
  test('legacy end does not suppress a subsequent real start', () {
    final rows = [event('out', 'clock_out', '2026-10-09T05:00:00'), event('start', 'clock_in', '2026-10-09T08:00:00')];
    expect(openAttendanceShifts(rows, workerId: 'worker-a', now: DateTime(2026, 10, 9, 9)).single.id, 'start');
  });
  test('other workers and their closing records cannot change own candidates', () {
    final rows = [
      event('own', 'clock_in', '2026-10-08T20:00:00'),
      event('foreign-start', 'clock_in', '2026-10-09T02:00:00', worker: 'worker-b'),
      event('foreign-end', 'clock_out', '2026-10-09T05:00:00', worker: 'worker-b', source: 'own'),
    ];
    expect(openAttendanceShifts(rows, workerId: 'worker-a', now: DateTime(2026, 10, 9, 6)).single.id, 'own');
  });
  test('future events never start or end the current shift', () {
    final rows = [event('own', 'clock_in', '2026-10-08T20:00:00'), event('future', 'clock_in', '2026-10-09T08:00:00'), event('out', 'clock_out', '2026-10-09T07:00:00', source: 'own')];
    expect(openAttendanceShifts(rows, workerId: 'worker-a', now: DateTime(2026, 10, 9, 6)).single.id, 'own');
  });
  test('stale and malformed starts are not resumed without a correction', () {
    final rows = [event('stale', 'clock_in', '2026-10-07T20:00:00'), event('bad', 'clock_in', 'bad-date'), event('', 'clock_in', '2026-10-09T02:00:00')];
    expect(openAttendanceShifts(rows, workerId: 'worker-a', now: DateTime(2026, 10, 9, 6)), isEmpty);
  });
  test('duplicate transport rows cannot duplicate the selectable target', () {
    final row = event('start', 'clock_in', '2026-10-08T20:00:00');
    expect(openAttendanceShifts([row, row], workerId: 'worker-a', now: DateTime(2026, 10, 9, 6)), hasLength(1));
  });
  test('canonical server date wins; legacy report ownership is preserved', () {
    final confirmed = DateTime(2026, 11, 1, 5);
    expect(attendanceEventWorkDate(confirmed, {'report_date': '2026-11-01'}, workDate: '2026-10-31'), DateTime(2026, 10, 31));
    expect(attendanceEventWorkDate(confirmed, {'report_date': '2026-10-31'}), DateTime(2026, 10, 31));
    expect(attendanceEventWorkDate(confirmed, null, workDate: 'invalid'), DateTime(2026, 11, 1));
  });
}
