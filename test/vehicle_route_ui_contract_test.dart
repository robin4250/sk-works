import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('vehicle and route UI matches restored registration specification', () {
    final page =
        File('lib/features/operations/vehicle_route_page.dart').readAsStringSync();
    final vehicleEditor =
        File('lib/features/operations/vehicle_editor_page.dart').readAsStringSync();
    final routeEditor =
        File('lib/features/operations/route_editor_page.dart').readAsStringSync();
    final repository = File(
      'lib/features/operations/vehicle_route_repository.dart',
    ).readAsStringSync();
    final app = File('lib/app_v2.dart').readAsStringSync();

    expect(page, contains("'車両を登録'"));
    expect(page, contains("'ルートを登録'"));
    expect(page, contains("'休止する'"));
    expect(vehicleEditor, contains("'表示名'"));
    expect(vehicleEditor, contains("'車両番号'"));
    expect(vehicleEditor, contains("'走行距離'"));
    expect(vehicleEditor, contains("'車検証'"));
    expect(vehicleEditor, contains("'自賠責保険'"));
    expect(vehicleEditor, contains("'任意保険証書'"));
    expect(routeEditor, contains("'ルート名'"));
    expect(routeEditor, contains("'現場名'"));
    expect(routeEditor, contains("'住所'"));
    expect(routeEditor, contains("'地点を追加'"));
    expect(routeEditor, contains("'備考'"));
    expect(routeEditor, isNot(contains("'運転者'")));
    expect(routeEditor, isNot(contains("'運行日（YYYY-MM-DD）'")));

    expect(repository, contains("from('sites')"));
    expect(repository, contains("from('route_stops')"));
    expect(repository, contains('setVehicleActive'));
    expect(repository, contains('setRouteActive'));
    expect(repository, contains("from('route_assignments').update"));
    expect(repository, contains("from('route_stops').delete"));
    expect(app, contains("key: 'vehicle_routes'"));
    expect(app, contains("page = const VehicleRoutePage()"));
  });
}
