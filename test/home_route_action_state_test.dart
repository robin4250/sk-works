import 'package:flutter_test/flutter_test.dart';

import 'package:sk_works/features/home/home_route_action_state.dart';

void main() {
  Map<String, dynamic> workspace() => {
    'source_clock_in_id': 'shift',
    'visit_contract_version': 1,
    'enabled': true,
    'is_open': true,
    'work_date': '2026-10-11',
    'stops': [
      {'id': 'site'},
    ],
    'visits': <Map<String, dynamic>>[],
  };
  Map<String, dynamic> visit() => {
    'start_capture_id': 'arrival',
    'route_stop_id': 'site',
    'work_date': '2026-10-11',
    'started_at': '2026-10-11T09:00:00+09:00',
    'end_capture_id': null,
    'ended_at': null,
  };
  test('arrival, move and next arrival follow confirmed visit lifecycle', () {
    final ws = workspace();
    expect(homeRouteActionState(ws, 'shift'), HomeRouteActionState.arrive);
    final row = visit();
    ws['visits'] = [row];
    expect(homeRouteActionState(ws, 'shift'), HomeRouteActionState.move);
    row['end_capture_id'] = 'departure';
    row['ended_at'] = '2026-10-11T10:00:00+09:00';
    expect(homeRouteActionState(ws, 'shift'), HomeRouteActionState.arrive);
  });
  test('closed, disabled, unrelated or incomplete contracts stay disabled', () {
    for (final patch in [
      {'is_open': false},
      {'enabled': false},
      {'visit_contract_version': null},
      {'source_clock_in_id': 'other'},
      {'visits': null},
      {'stops': []},
      {
        'visits': [visit(), visit()],
      },
      {
        'visits': [
          {...visit(), 'route_stop_id': 'other'},
        ],
      },
      {
        'visits': [
          {...visit(), 'ended_at': '2026-10-11T10:00:00+09:00'},
        ],
      },
    ]) {
      expect(
        homeRouteActionState({...workspace(), ...patch}, 'shift'),
        HomeRouteActionState.unavailable,
        reason: patch.toString(),
      );
    }
  });
}
