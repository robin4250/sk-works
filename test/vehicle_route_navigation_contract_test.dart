import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('vehicle and route page is reachable by every employee from SKO navigation', () {
    final app = File('lib/app_v2.dart').readAsStringSync();
    final home =
        File('lib/features/home/friendly_home_content.dart').readAsStringSync();

    expect(app, contains("import 'features/operations/vehicle_route_page.dart';"));
    expect(app, contains("case 'vehicle_routes':"));
    expect(app, contains('page = const VehicleRoutePage();'));
    expect(app, contains("key: 'vehicle_routes'"));
    expect(home, contains("'vehicle_routes'"));
    expect(home, contains("'車両・ルート'"));
    expect(home, contains('Icons.route_outlined'));
  });
}
