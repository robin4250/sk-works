import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('vehicle and route foundations remain company scoped', () {
    final vehicle = File('lib/domain/vehicle.dart').readAsStringSync();
    final route = File('lib/domain/route_assignment.dart').readAsStringSync();

    expect(vehicle, contains('companyId'));
    expect(vehicle, contains('registrationNumber'));
    expect(vehicle, contains('capacity'));
    expect(route, contains('companyId'));
    expect(route, contains('vehicleId'));
    expect(route, contains('siteId'));
    expect(route, contains('driverUserId'));
    expect(route, contains('serviceDate'));
  });
}
