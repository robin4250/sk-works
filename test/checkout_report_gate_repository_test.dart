import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/attendance/checkout_report_gate_repository.dart';

const _actor = '00000000-0000-0000-0000-000000000001';
String _id(int value) => '00000000-0000-0000-0000-${value.toString().padLeft(12, '0')}';
Map<String, Object?> _row() => {
  'company_id': _id(2), 'worker_id': _id(3), 'work_date': '2026-10-21',
  'site_id': _id(4), 'route_assignment_id': null, 'report_id': null,
  'source_clock_in_id': _id(5), 'clock_out_id': _id(6),
  'registration_state': 'reporter_signature_missing', 'blocking': true,
  'scope_fingerprint': 'authoritative-source-fingerprint',
};
Map<String, Object?> _response(List<Object?> items) => {'schema': 1, 'actor_id': _actor, 'enforcement_enabled': true, 'effective_from': '2026-10-01', 'items': items};
void main() {
  test('empty authoritative response alone proves no outstanding reporter registration', () {
    expect(CheckoutReportGateRepository.parse(_response([]), _actor), isEmpty);
  });
  test('explicit OFF is distinguished by validated capability, never inferred from missing fields', () {
    expect(CheckoutReportGateRepository.parse({..._response([]), 'enforcement_enabled': false, 'effective_from': null}, _actor), isEmpty);
  });
  test('missing and reporter-saved responsible-pending states preserve separate gate contract', () {
    final row = _row();
    final pending = CheckoutReportGateRepository.parse(_response([row]), _actor).single;
    expect(pending.blocking, true);
    final waiting = CheckoutReportGateRepository.parse(_response([{...row,
      'registration_state': 'reporter_saved_waiting_supervisor', 'blocking': false,
      'report_id': _id(7)}]), _actor).single;
    expect(waiting.blocking, false);
    expect(waiting.reportId, _id(7));
  });
  test('only authoritative multi-member choice can defer without a report', () {
    final choice = {..._row(), 'registration_state': 'report_choice_required',
      'choice_available': true, 'member_count': 2};
    expect(CheckoutReportGateRepository.parse(_response([choice]), _actor).single.memberCount, 2);
    final deferred = {...choice, 'registration_state': 'checkout_deferred', 'blocking': false};
    expect(CheckoutReportGateRepository.parse(_response([deferred]), _actor).single.reportId, isNull);
    expect(() => CheckoutReportGateRepository.parse(_response([{...choice, 'member_count': 1}]), _actor), throwsStateError);
    expect(() => CheckoutReportGateRepository.parse(_response([{...deferred, 'choice_available': false}]), _actor), throwsStateError);
    expect(() => CheckoutReportGateRepository.parse(_response([{...choice, 'member_count': '2'}]), _actor), throwsStateError);
  });
  for (final bad in ['actor', 'schema', 'items', 'date', 'identity', 'destination', 'state', 'duplicate', 'capability', 'rolloutdate', 'offitems', 'unlinkedunlock']) {
    test('unknown or inconsistent $bad is never interpreted as no pending work', () {
      final row = _row();
      final response = _response([row]);
      switch (bad) {
        case 'actor': response['actor_id'] = _id(99);
        case 'schema': response['schema'] = 2;
        case 'items': response.remove('items');
        case 'date': row['work_date'] = '2026-02-31';
        case 'identity': row['source_clock_in_id'] = 'invalid';
        case 'destination': row['route_assignment_id'] = _id(8);
        case 'state': row['blocking'] = false; row['registration_state'] = 'unknown';
        case 'duplicate': response['items'] = [row, row];
        case 'capability': response.remove('enforcement_enabled');
        case 'rolloutdate': response['effective_from'] = null;
        case 'offitems': response['enforcement_enabled'] = false; response['effective_from'] = null;
        case 'unlinkedunlock': row['blocking'] = false; row['registration_state'] = 'reporter_saved_waiting_supervisor';
      }
      expect(() => CheckoutReportGateRepository.parse(response, _actor), throwsStateError);
    });
  }
}
