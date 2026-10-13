import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/operations/vehicle_driver_meter_input.dart';
import 'package:sk_works/features/operations/vehicle_driver_meter_repository.dart';
import 'package:sk_works/features/operations/vehicle_driver_meter_page.dart';

class _Source implements VehicleDriverMeterSource {
  bool driver = true;
  bool enabled = true;
  bool failSave = false;
  bool wrongTarget = false;
  int calls = 0;
  final ids = <String>[];
  Map<String, dynamic>? existing;
  Map<String, dynamic> claimRow = {
    'source_clock_in_id': 'start', 'company_id': 'company', 'driver_worker_id': 'driver',
    'work_date': '2026-10-31', 'start_odometer_km': 1000, 'ended_at': '2026-11-01T05:00:00+09:00',
  };
  @override
  Future<Map<String, dynamic>?> claim(String id) async => claimRow;
  @override
  Future<bool> isDriver(String companyId, String workerId) async => driver;
  @override
  Future<bool> isEnabled(String companyId) async => enabled;
  @override
  Future<Map<String, dynamic>?> event(String id) async => existing;
  @override
  Future<Map<String, dynamic>> record(Map<String, Object?> parameters) async {
    calls++;
    ids.add(parameters['p_event_id']! as String);
    if (failSave) {
      throw StateError('response lost');
    }
    final current = parameters['p_current_km'] as double;
    return {
      'id': parameters['p_event_id'], 'source_clock_in_id': wrongTarget ? 'other' : 'start',
      'company_id': 'company', 'driver_worker_id': 'driver', 'work_date': '2026-10-31',
      'previous_km': 1000, 'current_km': current,
      'distance_km': parameters['p_manual_distance_km'] ?? ((current * 10).round() - 10000) / 10,
      'baseline_decreased': current < 1000,
    };
  }
}

void main() {
  testWidgets('OFF hides the new entry without recording anything', (tester) async {
    final source = _Source()..enabled = false;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: VehicleDriverMeterEntry(
      sourceClockInId: 'start', repository: VehicleDriverMeterRepository(source),
    ))));
    await tester.pumpAndSettle();
    expect(find.text('運転手のメーター登録'), findsNothing);
    expect(source.calls, 0);
  });
  testWidgets('changing report month or destination hides an old shift entry', (tester) async {
    final source = _Source();
    source.claimRow['clock_in'] = {'site_id': 'site', 'route_assignment_id': null};
    final repository = VehicleDriverMeterRepository(source);
    Future<void> show(String day, String site) async {
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: VehicleDriverMeterEntry(
        sourceClockInId: 'start', expectedWorkDate: day, expectedSiteId: site,
        requireDestinationMatch: true, repository: repository,
      ))));
      await tester.pumpAndSettle();
    }
    await show('2026-10-31', 'site');
    expect(find.text('運転手のメーター登録'), findsOneWidget);
    await show('2026-11-01', 'site');
    expect(find.text('運転手のメーター登録'), findsNothing);
    await show('2026-10-31', 'other-site');
    expect(find.text('運転手のメーター登録'), findsNothing);
    expect(source.calls, 0);
  });
  testWidgets('a group report writer who is not the driver sees no meter entry', (tester) async {
    final source = _Source()..driver = false;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: VehicleDriverMeterEntry(
      sourceClockInId: 'start', repository: VehicleDriverMeterRepository(source),
    ))));
    await tester.pumpAndSettle();
    expect(find.text('運転手のメーター登録'), findsNothing);
    expect(source.calls, 0);
  });
  test('unknown, disabled and wrong-company capability stay OFF', () {
    final valid = {'version': 1, 'company_id': 'company', 'vehicle_usage_enabled': true, 'vehicle_meter_enabled': true};
    expect(vehicleDriverMeterEnabledFor(valid, 'company'), isTrue);
    for (final value in [null, {}, {...valid, 'version': 2}, {...valid, 'company_id': 'other'},
      {...valid, 'vehicle_usage_enabled': false}, {...valid, 'vehicle_meter_enabled': 'true'}]) {
      expect(vehicleDriverMeterEnabledFor(value, 'company'), isFalse);
    }
  });
  test('driver ownership and OFF capabilities hide the entry', () async {
    final source = _Source();
    final repository = VehicleDriverMeterRepository(source);
    source.driver = false;
    expect(await repository.load('start'), isNull);
    source.driver = true; source.enabled = false;
    expect(await repository.load('start'), isNull);
    expect(source.calls, 0);
  });
  test('month boundary preserves work_date and missing baseline blocks save', () async {
    final source = _Source();
    final repository = VehicleDriverMeterRepository(source);
    final value = (await repository.load('start'))!;
    expect(value.workDate, '2026-10-31');
    expect(value.canRecord, isTrue);
    source.claimRow['start_odometer_km'] = null;
    expect((await repository.load('start'))!.canRecord, isFalse);
    source.claimRow['start_odometer_km'] = 1000;
    source.claimRow['ended_at'] = null;
    expect((await repository.load('start'))!.canRecord, isFalse);
  });
  test('a changed target in loaded event is rejected', () async {
    final source = _Source()..existing = {'source_clock_in_id': 'other'};
    await expectLater(VehicleDriverMeterRepository(source).load('start'), throwsStateError);
  });
  test('lost response retry keeps operation UUID and target shift', () async {
    final source = _Source();
    final repository = VehicleDriverMeterRepository(source);
    final value = (await repository.load('start'))!;
    source.failSave = true;
    await expectLater(repository.save(value, const VehicleDriverMeterInput(currentKm: 1100)), throwsStateError);
    source.failSave = false;
    final result = await repository.save(value, const VehicleDriverMeterInput(currentKm: 1100));
    expect(source.ids[0], source.ids[1]);
    expect(source.ids[0], matches(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')));
    expect(result['source_clock_in_id'], 'start');
    expect(result['distance_km'], 100);
  });
  test('ownership is rechecked immediately before save', () async {
    final source = _Source();
    final repository = VehicleDriverMeterRepository(source);
    final value = (await repository.load('start'))!;
    source.driver = false;
    await expectLater(repository.save(value, const VehicleDriverMeterInput(currentKm: 1100)), throwsStateError);
    expect(source.calls, 0);
  });
  test('decimal kilometres use exact tenths when checking SQL distance', () async {
    final source = _Source();
    final repository = VehicleDriverMeterRepository(source);
    final value = (await repository.load('start'))!;
    final result = await repository.save(value, const VehicleDriverMeterInput(currentKm: 1100.1));
    expect(result['distance_km'], 100.1);
  });
  test('decrease requires manual distance and returns the same source', () async {
    final source = _Source();
    final repository = VehicleDriverMeterRepository(source);
    final value = (await repository.load('start'))!;
    await expectLater(repository.save(value, const VehicleDriverMeterInput(currentKm: 50)), throwsStateError);
    expect(source.calls, 0);
    final result = await repository.save(value, const VehicleDriverMeterInput(currentKm: 50, manualDistanceKm: 20));
    expect(result['distance_km'], 20);
    expect(result['baseline_decreased'], isTrue);
  });
  test('save response cannot switch target or report success for another shift', () async {
    final source = _Source()..wrongTarget = true;
    final repository = VehicleDriverMeterRepository(source);
    await expectLater(repository.save((await repository.load('start'))!,
      const VehicleDriverMeterInput(currentKm: 1100)), throwsStateError);
  });
  test('meter parsing rejects NaN, negative, rounding and overflow', () {
    for (final value in ['NaN', 'Infinity', '-1', '1.12', '100000000000.0', '']) {
      expect(VehicleDriverMeterInput.parseKilometres(value), isNull);
    }
    expect(VehicleDriverMeterInput.parseKilometres(' 1000.1 '), 1000.1);
    expect(VehicleDriverMeterInput.parseKilometres('0'), 0);
  });
  test('manual distance is required only after a decrease', () {
    expect(VehicleDriverMeterInput.parse(previousKm: 1000, currentText: '50', manualDistanceText: ''), isNull);
    expect(VehicleDriverMeterInput.parse(previousKm: 1000, currentText: '50', manualDistanceText: '20')!.manualDistanceKm, 20);
    expect(VehicleDriverMeterInput.parse(previousKm: 1000, currentText: '1100', manualDistanceText: '20')!.manualDistanceKm, isNull);
  });
}
