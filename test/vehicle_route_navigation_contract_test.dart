import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('vehicle and route page is a management home shortcut', () {
    final app = File('lib/app_v2.dart').readAsStringSync();
    final home =
        File('lib/features/home/friendly_home_content.dart').readAsStringSync();

    expect(app, contains("case 'vehicle_routes':"));
    expect(app, contains('page = const VehicleRoutePage();'));
    expect(app, contains("key: 'vehicle_routes'"));
    expect(app, contains("if (_identity.isManagement && _moduleEnabled('vehicle_routes'))"));
    expect(app, contains("SkoLanguageController.tr('車両ルート')"));
    expect(app, contains('icon: Icons.route_outlined'));
    expect(app, contains('HomeShortcut('));
    expect(home, contains('for (final shortcut in shortcuts)'));
  });
}
