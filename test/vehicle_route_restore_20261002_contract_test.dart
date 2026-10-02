import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('vehicle registration matches restored specification', () {
    final page = File(
      'lib/features/operations/vehicle_editor_page.dart',
    ).readAsStringSync();
    final repository = File(
      'lib/features/operations/vehicle_route_repository.dart',
    ).readAsStringSync();

    expect(page, contains("'表示名'"));
    expect(page, contains("'車両番号'"));
    expect(page, contains("'走行距離'"));
    expect(page, contains("'車検証'"));
    expect(page, contains("'自賠責保険'"));
    expect(page, contains("'任意保険証書'"));
    expect(page, contains('ImageSource.camera'));
    expect(page, contains("'pdf'"));
    expect(page, contains('書類は車両登録後に追加しても大丈夫です'));
    expect(page, contains('未登録書類は後から追加できます'));
    expect(repository, contains("'vehicle-documents'"));
    expect(repository, contains("'odometer_km'"));
    expect(repository, contains("'notify_missing_vehicle_documents'"));
  });

  test('route editor supports unlimited site or address stops', () {
    final page = File(
      'lib/features/operations/route_editor_page.dart',
    ).readAsStringSync();
    final repository = File(
      'lib/features/operations/vehicle_route_repository.dart',
    ).readAsStringSync();

    expect(page, contains("'ルート名'"));
    expect(page, contains("'登録済み地点から選択'"));
    expect(page, contains("'現場："));
    expect(page, contains("'取引会社："));
    expect(page, contains("'下請け会社："));
    expect(page, contains("'駐車場："));
    expect(page, contains("'住所'"));
    expect(page, contains("'地点を追加'"));
    expect(page, contains("'備考'"));
    expect(repository, contains("from('route_stops')"));
    expect(repository, contains("'stop_order'"));
    expect(repository, contains("'source_kind'"));
    expect(repository, contains("'storage_address'"));
    expect(page, isNot(contains("'運行日（YYYY-MM-DD）'")));
    expect(page, isNot(contains("'運転者'")));
  });

  test('home daily report separates optional vehicle from workplace route', () {
    final home = File(
      'lib/features/home/friendly_home_content.dart',
    ).readAsStringSync();
    final app = File('lib/app_v2.dart').readAsStringSync();
    final selection = File(
      'lib/features/operations/vehicle_route_selection_page.dart',
    ).readAsStringSync();

    expect(home, contains("'現場の選択（1現場／複数現場）'"));
    expect(home, contains("'出勤方法と車両を選択'"));
    expect(home, contains('選択中の車両：'));
    expect(home, contains('選択中のルート：'));
    expect(home, contains("moduleEnabled('vehicle_routes')"));
    expect(selection, contains('VehicleRouteSelectionMode.vehicle'));
    expect(selection, contains('VehicleRouteSelectionMode.route'));
    expect(selection, contains("'車両を使わない'"));
    expect(selection, contains("'ルートを使わない'"));
    expect(app, contains("case 'workplace_select':"));
    expect(app, contains("case 'attendance_method_vehicle':"));
  });

  test('attendance and daily report carry vehicle route and odometer', () {
    final attendance = File(
      'lib/features/attendance/attendance_verification_repository.dart',
    ).readAsStringSync();
    final reportRepo = File(
      'lib/features/daily_reports/daily_report_repository.dart',
    ).readAsStringSync();
    final reportPage = File(
      'lib/features/daily_reports/daily_report_page.dart',
    ).readAsStringSync();
    final pdf = File(
      'lib/features/daily_reports/daily_report_pdf_service.dart',
    ).readAsStringSync();
    final ocr = File(
      'lib/features/operations/odometer_text_recognition_engine.dart',
    ).readAsStringSync();

    expect(attendance, contains("'vehicle_id'"));
    expect(attendance, contains("'route_assignment_id'"));
    expect(reportRepo, contains("'save_daily_report_vehicle_usage'"));
    expect(reportPage, contains("'メーターを撮影して読取'"));
    expect(reportPage, contains("'再撮影'"));
    expect(reportPage, contains("'この数値を登録'"));
    expect(pdf, contains("'車両 ' + worker.vehicleName!"));
    expect(pdf, contains("'ルート ' + worker.routeName!"));
    expect(pdf, contains("'走行 ' + _number(worker.odometerKm!) + 'km'"));
    expect(ocr, contains('TextRecognizer'));
    expect(ocr, contains('TextRecognitionScript.latin'));
  });

  test('vehicle route management is restricted to management roles', () {
    final sql = File(
      'supabase/migrations/'
      '20261001232917_restrict_vehicle_route_management_to_management_roles.sql',
    ).readAsStringSync();
    expect(sql, contains("cm.role::text in ('owner','admin','manager')"));
  });
}
