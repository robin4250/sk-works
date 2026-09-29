import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('vehicle and route UI supports safe disable and route assignments', () {
    final page =
        File('lib/features/operations/vehicle_route_page.dart').readAsStringSync();
    final repository = File(
      'lib/features/operations/vehicle_route_repository.dart',
    ).readAsStringSync();

    expect(page, contains('車両休止の確認'));
    expect(page, contains('ルート休止の確認'));
    expect(page, contains('過去のルート履歴は削除されません'));
    expect(page, contains('過去の運行履歴は削除されません'));
    expect(page, contains("labelText: '車両'"));
    expect(page, contains("labelText: '現場'"));
    expect(page, contains("labelText: '運転者'"));
    expect(page, contains('vehicleId: result.vehicleId'));
    expect(page, contains('siteId: result.siteId'));
    expect(page, contains('driverUserId: result.driverUserId'));

    expect(repository, contains("from('sites')"));
    expect(repository, contains("from('workers')"));
    expect(repository, contains('setVehicleActive'));
    expect(repository, contains('setRouteActive'));
    expect(repository, isNot(contains(".delete()")));
  });
}
