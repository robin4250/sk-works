import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/shifts/own_published_shift_gateway.dart';

void main() {
  Map<String, Object?> row(String date) => {'work_date': date, 'revision': 1, 'plan': {
    'site_id': 'site', 'holiday': false, 'night': true, 'start_minute': 1320,
    'end_minute': 360, 'check_late': true, 'check_early': false}};
  test('requests own month and preserves confirmed overnight schedule', () async {
    final gateway = OwnPublishedShiftGateway((name, params) async {
      expect(name, 'list_own_published_shifts');
      expect(params, {'p_company': 'company', 'p_from': '2026-10-01', 'p_to': '2026-10-31'});
      return [row('2026-10-25')];
    });
    final result = await gateway.listMonth('company', DateTime(2026, 10));
    expect(result.single.night, isTrue);
    expect(result.single.endMinute, 360);
  });
  test('rejects duplicate, invalid and incomplete results instead of silently hiding them', () async {
    for (final result in [null, [row('2026-10-25'), row('2026-10-25')], [row('2026-11-01')], [row('2026-02-30')], [{'work_date': '2026-10-01'}]]) {
      final gateway = OwnPublishedShiftGateway((_, __) async => result);
      expect(() => gateway.listMonth('company', DateTime(2026, 10)), throwsFormatException);
    }
  });
  test('propagates server access and network errors', () async {
    final gateway = OwnPublishedShiftGateway((_, __) async => throw StateError('access denied'));
    expect(() => gateway.listMonth('company', DateTime(2026, 10)), throwsStateError);
  });
}
