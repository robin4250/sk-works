import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/settings/master_feature_availability.dart';

void main() {
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
