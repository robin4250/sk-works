import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/daily_reports/daily_report_shift_context.dart';

Map<String, dynamic> start({
  String worker = 'worker', String? site = 'site', String? route,
  String? vehicle = 'vehicle-at-start', String? day = '2026-10-31',
  String at = '2026-10-31T20:00:00',
}) => {
  'worker_id': worker, 'event_type': 'clock_in', 'site_id': site,
  'route_assignment_id': route, 'vehicle_id': vehicle,
  'work_date': day, 'confirmed_at': at,
};

void main() {
  final day = DateTime(2026, 10, 31);
  test('night shift uses original start vehicle, not a subsequent selection', () {
    final original = start();
    final later = start(vehicle: 'later-vehicle', at: '2026-10-31T22:00:00');
    final snapshot = dailyReportClockInSnapshot([later, original],
        workerId: 'worker', workDate: day, siteId: 'site');
    expect(snapshot?['vehicle_id'], 'vehicle-at-start');
  });
  test('canonical null vehicle remains evidence and suppresses selection fallback', () {
    final snapshot = dailyReportClockInSnapshot([start(vehicle: null)],
        workerId: 'worker', workDate: day, siteId: 'site');
    expect(snapshot, isNotNull);
    expect(snapshot?['vehicle_id'], isNull);
  });
  test('destination and worker isolate the snapshot', () {
    final rows = [start(worker: 'other'), start(site: 'other'),
      start(site: null, route: 'route', vehicle: 'route-vehicle')];
    expect(dailyReportClockInSnapshot(rows, workerId: 'worker',
        workDate: day, siteId: 'site'), isNull);
    final snapshot = dailyReportClockInSnapshot(rows, workerId: 'worker',
        workDate: day, routeId: 'route');
    expect(snapshot?['vehicle_id'], 'route-vehicle');
    expect(snapshot?['route_assignment_id'], 'route');
  });
  test('first legacy start preserves prior fallback even if a later start is canonical', () {
    final rows = [start(day: null), start(at: '2026-10-31T22:00:00')];
    expect(dailyReportClockInSnapshot(rows, workerId: 'worker',
        workDate: day, siteId: 'site'), isNull);
  });
  test('explicit server work date keeps a next-day start in the owning report day', () {
    final row = start(at: '2026-11-01T01:00:00');
    expect(dailyReportClockInSnapshot([row], workerId: 'worker',
        workDate: day, siteId: 'site'), row);
    expect(dailyReportClockInSnapshot([row], workerId: 'worker',
        workDate: DateTime(2026, 11, 1), siteId: 'site'), isNull);
  });
  test('malformed and end records never become report vehicle snapshots', () {
    final rows = [start(at: 'bad'), {...start(), 'event_type': 'clock_out'}];
    expect(dailyReportClockInSnapshot(rows, workerId: 'worker',
        workDate: day, siteId: 'site'), isNull);
  });
}
