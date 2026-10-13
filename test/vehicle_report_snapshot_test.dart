import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/daily_reports/vehicle_report_snapshot.dart';

Map<String, Object?> snapshot({bool event = true, String worker = 'driver', String source = 'start',
    String date = '2026-10-31', double current = 1120, double previous = 1100, double distance = 20}) => {
  'has_claim': true, 'has_event': event, 'worker_id': worker,
  'source_clock_in_id': source, 'vehicle_id': 'vehicle', 'vehicle_name': '車両1234',
  'event_id': event ? 'event' : null, 'work_date': date,
  'previous_km': previous, 'current_km': event ? current : null, 'distance_km': event ? distance : null,
};

void main() {
  test('report uses original driver event values, including manual distance after decrease', () {
    final row = parseVehicleReportContext([snapshot(current: 10, previous: 1100, distance: 35)], '2026-10-31').single;
    expect(row.previousKm, 1100);
    expect(row.currentKm, 10);
    expect(row.distanceKm, 35);
    expect(row.sourceId, 'start');
  });
  test('missing meter remains pending, never guessed from vehicle current value', () {
    final row = parseVehicleReportContext([snapshot(event: false)], '2026-10-31').single;
    expect(row.hasEvent, isFalse);
    expect(row.currentKm, isNull);
    expect(row.distanceKm, isNull);
  });
  test('ambiguous driver sources, wrong month and incomplete event are rejected', () {
    expect(() => parseVehicleReportContext([snapshot(), snapshot(source: 'second')], '2026-10-31'), throwsStateError);
    expect(() => parseVehicleReportContext([snapshot(date: '2026-11-01')], '2026-10-31'), throwsStateError);
    expect(() => parseVehicleReportContext([{...snapshot(), 'current_km': null}], '2026-10-31'), throwsStateError);
  });
}
