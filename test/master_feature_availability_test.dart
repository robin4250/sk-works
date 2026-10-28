import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/settings/master_feature_availability.dart';

void main() {
  test('QR punches and reader registration share an explicit versioned flag', () {
    for (final version in [null, 0, 2, '1', 1.0, 1]) {
      for (final enabled in [null, 'true', 1, false, true]) {
        final flags = MasterFeatureAvailability.fromJson({
          'qr_attendance_contract_version': version,
          'qr_attendance': enabled,
          'qr_device_registration': true,
        });
        final supported = version is int && version == 1 && enabled is bool;
        expect(flags.qrAttendanceSupported, supported);
        expect(flags.qrAttendance, supported && enabled == true);
        expect(flags.qrDeviceRegistration, flags.qrAttendance);
      }
    }
    final unsupported = MasterFeatureAvailability.fromJson({
      'qr_attendance': true, 'qr_device_registration': true,
    });
    expect(unsupported.qrAttendance, isFalse);
    expect(unsupported.qrDeviceRegistration, isFalse);
    expect(MasterFeatureAvailability.unavailable.qrAttendance, isFalse);
  });

  test('seal tools share one explicit availability gate without changing existing defaults', () {
    for (final value in [null, 'true', 1, false, true]) {
      final flags = MasterFeatureAvailability.fromJson({
        'vehicle_management': true, 'route_assignment': false,
        'traffic_nearest_station': true, 'traffic_train_transfer': false,
        'traffic_bus_stop': true, 'company_seal_image_tools': value,
      });
      expect(flags.companySealImageTools, value == true);
      expect(flags.companySealImageToolsSupported, value is bool);
      expect(flags.vehicleManagement, isTrue); expect(flags.routeAssignment, isFalse);
      expect(flags.trafficNearestStation, isTrue); expect(flags.trafficTrainTransfer, isFalse);
      expect(flags.trafficBusStop, isTrue);
    }
    expect(MasterFeatureAvailability.unavailable.companySealImageTools, isFalse);
  });

  test(
    'independent OFF flags stop only new use of the selected optional feature',
    () {
      for (final vehicle in [false, true]) {
        for (final route in [false, true]) {
          final flags = MasterFeatureAvailability(
            vehicleManagement: vehicle,
            routeAssignment: route,
          );
          expect(flags.permitsClockIn(), isTrue);
          expect(flags.permitsClockIn(routeId: 'route'), route);
          expect(flags.permitsClockIn(vehicleId: 'vehicle'), vehicle);
          expect(
            flags.permitsClockIn(vehicleId: 'vehicle', routeId: 'route'),
            vehicle && route,
          );
        }
      }
    },
  );
  test('missing or malformed flags cannot invent an ON value', () {
    for (final json in <Map<String, dynamic>>[
      {},
      {'vehicle_management': 'true', 'route_assignment': 1},
    ]) {
      final flags = MasterFeatureAvailability.fromJson(json);
      expect(flags.vehicleManagement, isFalse);
      expect(flags.routeAssignment, isFalse);
    }
  });
}

