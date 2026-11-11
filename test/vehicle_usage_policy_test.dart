import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/operations/vehicle_usage_policy.dart';

void main() {
  test('a vehicle stays unavailable to every new start until checkout', () {
    expect(VehicleUsagePolicy.canStart(workerId: 'driver'), isTrue);
    expect(VehicleUsagePolicy.canStart(workerId: ''), isFalse);
    for (final worker in ['driver', 'other']) {
      expect(VehicleUsagePolicy.canStart(
        workerId: worker, activeDriverId: 'driver'), isFalse);
    }
  });

  test('a group report writer cannot enter another driver meter', () {
    expect(VehicleUsagePolicy.canRecordMeter(
      workerId: 'writer', driverId: 'driver'), isFalse);
    expect(VehicleUsagePolicy.canRecordMeter(
      workerId: 'driver', driverId: 'driver'), isTrue);
    expect(VehicleUsagePolicy.canRecordMeter(
      workerId: '', driverId: ''), isFalse);
  });

  test('daily distance is a snapshot delta, including a valid zero', () {
    final reading = VehicleUsagePolicy.distance(
      previousKm: 12000.5, currentKm: 12125.7);
    expect(reading.distanceKm, closeTo(125.2, 0.000001));
    expect(reading.nextBaselineKm, 12125.7);
    expect(reading.notifyBaselineChange, isFalse);
    expect(VehicleUsagePolicy.distance(
      previousKm: 100, currentKm: 100).distanceKm, 0);
  });

  test('decrease resets baseline without inventing a distance', () {
    final reading = VehicleUsagePolicy.distance(
      previousKm: 12000, currentKm: 200);
    expect(reading.nextBaselineKm, 200);
    expect(reading.distanceKm, isNull);
    expect(reading.requiresManualDistance, isTrue);
    expect(reading.notifyBaselineChange, isTrue);
    final corrected = VehicleUsagePolicy.distance(
      previousKm: 12000, currentKm: 200, manualDistanceKm: 80);
    expect(corrected.previousKm, 12000);
    expect(corrected.distanceKm, 80);
    expect(corrected.requiresManualDistance, isFalse);
    expect(corrected.notifyBaselineChange, isTrue);
  });

  test('invalid OCR/manual numbers do not become registered values', () {
    for (final value in [-1.0, double.nan, double.infinity]) {
      expect(() => VehicleUsagePolicy.distance(
        previousKm: 100, currentKm: value), throwsArgumentError);
      expect(() => VehicleUsagePolicy.distance(
        previousKm: 100, currentKm: 10, manualDistanceKm: value),
        throwsArgumentError);
    }
    expect(() => VehicleUsagePolicy.distance(
      previousKm: 100, currentKm: 110, manualDistanceKm: 5),
      throwsArgumentError);
  });

  List<VehicleMaintenanceCrossing> crossings(double previous, double current,
      {String epoch = 'epoch-1'}) => VehicleUsagePolicy.maintenanceCrossings(
    vehicleId: 'vehicle', ruleId: 'oil', epochId: epoch,
    originKm: 10000, previousKm: previous, currentKm: current,
    intervalKm: 3000);

  test('repeat intervals cross once at the boundary and not on re-save', () {
    expect(crossings(12999, 12999), isEmpty);
    expect(crossings(12999, 13000).single.thresholdKm, 13000);
    expect(crossings(13000, 13000), isEmpty);
    expect(crossings(13000, 13001), isEmpty);
    expect(crossings(13001, 16000).single.thresholdKm, 16000);
  });

  test('crossed intervals have stable deduplication keys across retries', () {
    final first = crossings(12000, 19500);
    expect(first.map((event) => event.thresholdKm), [13000, 16000, 19000]);
    expect(first.map((event) => event.eventKey),
      crossings(12000, 19500).map((event) => event.eventKey));
    expect(first.map((event) => event.eventKey).toSet().length, 3);
    expect(crossings(12000, 13000, epoch: 'epoch-2').single.eventKey,
      isNot(first.first.eventKey));
  });

  test('decreases never emit a false maintenance crossing', () {
    expect(crossings(16000, 12000), isEmpty);
    expect(() => VehicleUsagePolicy.maintenanceCrossings(
      vehicleId: 'vehicle', ruleId: 'oil', epochId: 'epoch',
      originKm: 0, previousKm: 1, currentKm: 2, intervalKm: 0),
      throwsArgumentError);
  });
}
