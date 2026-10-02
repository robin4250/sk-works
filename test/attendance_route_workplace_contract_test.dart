import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('attendance workplace is mutually exclusive site or route', () {
    final home =
        File('lib/features/home/friendly_home_content.dart').readAsStringSync();
    final selection =
        File('lib/features/attendance/attendance_selection_page.dart').readAsStringSync();
    final attendanceRepo = File(
      'lib/features/attendance/attendance_verification_repository.dart',
    ).readAsStringSync();
    final vehicleRepo = File(
      'lib/features/operations/vehicle_route_repository.dart',
    ).readAsStringSync();

    expect(selection, contains("child: Text('未登録')"));
    expect(home, contains("status.siteName?.trim().isNotEmpty == true"));
    expect(home, contains("'選択中の現場："));
    expect(home, contains("'選択中のルート："));
    expect(attendanceRepo, contains("'route_assignment_id': null"));
    expect(vehicleRepo, contains("'site_id': null"));
    expect(attendanceRepo, contains("'save_my_route_attendance_selection'"));
  });

  test('route gps auto attendance uses registered route stop coordinates', () {
    final routeEditor =
        File('lib/features/operations/route_editor_page.dart').readAsStringSync();
    final routeRepo = File(
      'lib/features/operations/vehicle_route_repository.dart',
    ).readAsStringSync();
    final migration = File(
      'supabase/migrations/'
      '20261002125010_enable_route_gps_auto_attendance.sql',
    ).readAsStringSync();

    expect(routeEditor, contains("'GPS基準位置 登録済み'"));
    expect(routeEditor, contains("'現在地を登録'"));
    expect(routeRepo, contains("'latitude': stops[i]['latitude']"));
    expect(routeRepo, contains("'longitude': stops[i]['longitude']"));
    expect(migration, contains("'route_location_missing'"));
    expect(migration, contains('from public.route_stops rs'));
    expect(migration, contains('order by ('));
    expect(migration, contains("'GPS自動出勤：'"));
  });
}
