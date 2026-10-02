import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('device review fixes stay wired for TestFlight candidate', () {
    final employeePreview = File(
      'lib/features/people/employee_personnel_print_page.dart',
    ).readAsStringSync();
    final attendance = File(
      'lib/features/attendance/worker_attendance_sheet_page.dart',
    ).readAsStringSync();
    final attendancePdf = File(
      'lib/features/attendance/attendance_pdf_service.dart',
    ).readAsStringSync();
    final chat = File(
      'lib/features/chat/chat_cloud_page.dart',
    ).readAsStringSync();
    final map = File(
      'lib/features/sites/site_map_page.dart',
    ).readAsStringSync();
    final prepareIos = File('tool/prepare_ios.sh').readAsStringSync();
    final sitesPage = File(
      'lib/features/sites/site_cloud_page.dart',
    ).readAsStringSync();
    final app = File(
      'lib/app_v2.dart',
    ).readAsStringSync();
    final attendanceRepository = File(
      'lib/features/attendance/worker_attendance_sheet_repository.dart',
    ).readAsStringSync();
    final report = File(
      'lib/features/daily_reports/daily_report_page.dart',
    ).readAsStringSync();
    final reportRepository = File(
      'lib/features/daily_reports/daily_report_repository.dart',
    ).readAsStringSync();
    final companyData = File(
      'lib/features/people/company_submitted_documents_page.dart',
    ).readAsStringSync();
    final profile = File(
      'lib/features/profile/profile_page.dart',
    ).readAsStringSync();
    final profileRepository = File(
      'lib/features/profile/profile_repository.dart',
    ).readAsStringSync();
    final home = File(
      'lib/features/home/friendly_home_content.dart',
    ).readAsStringSync();

    expect(employeePreview, contains('InteractiveViewer'));
    expect(employeePreview, contains('maxScale: 5'));

    expect(attendance, contains("allowanceUnits[name] ?? '回'"));
    expect(attendance, contains('if (data.overtimeHours > 0)'));
    expect(attendancePdf, contains('_hoursCell'));
    expect(attendancePdf, contains('_summaryText'));
    expect(attendanceRepository, contains("rpc('my_attendance_allowance_units')"));

    expect(chat, contains('reverse: true'));
    expect(chat, contains('_chatTabButton'));
    expect(chat, contains('backgroundColor: Colors.transparent'));
    expect(chat, contains('surfaceTintColor: Colors.transparent'));
    expect(chat, isNot(contains('SingleChildScrollView(\n        scrollDirection: Axis.horizontal')));

    expect(map, contains("MethodChannel('sko.multi_pin_map')"));
    expect(map, contains('allowEmployeeHomes'));
    expect(map, contains("Only other employees' homes are restricted by allowEmployeeHomes"));
    expect(map, contains("if (_layers.contains(_MapLayer.home) && data.home != null)"));
    expect(map, contains("if (data.home != null) ...["));
    expect(map, contains('選択地点を複数ピンで地図表示'));
    expect(sitesPage, contains('const SiteMapPage()'));
    expect(sitesPage, contains("title: const Text('現場データ')"));
    expect(sitesPage, contains("label: const Text('現場登録')"));
    expect(sitesPage, contains("label: const Text('現場マップ')"));
    expect(sitesPage, contains("heroTag: 'site_map'"));
    expect(sitesPage, contains("heroTag: 'site_register'"));
    expect(sitesPage, contains('floatingActionButton: Row('));
    expect(map, contains('title: Text(widget.title)'));
    expect(app, contains("title: '管理者用現場マップ'"));
    expect(prepareIos, contains('import MapKit'));
    expect(prepareIos, contains('MKMarkerAnnotationView'));
    expect(prepareIos, contains('showAnnotations'));
    expect(prepareIos, contains('let fallbackLat = number(raw["latitude"])'));
    expect(prepareIos, contains('if !address.isEmpty'));
    expect(prepareIos, contains('geocodeAddressString(address)'));
    expect(prepareIos, contains('registrar(forPlugin: "SkoMultiPinMap")'));
    expect(prepareIos, contains('connectedScenes'));
    expect(prepareIos, contains('isKeyWindow'));
    expect(prepareIos, isNot(contains('if let controller = window?.rootViewController')));
    expect(map, contains('on MissingPluginException'));

    expect(report, contains("'報告者サイン'"));
    expect(report, contains("'責任者サイン'"));
    expect(report, contains("if (totalNight > 0) MapEntry('夜間'"));
    expect(report, contains('allowanceCounts[label] ='));
    expect(report, contains('MapEntry(entry.key, entry.value.toString())'));
    expect(report, contains("'現場／ルート'"));
    expect(report, contains('initialRouteAssignmentId'));
    expect(reportRepository, contains("rpc(\n      'daily_report_clocked_in_destinations'"));
    expect(reportRepository, contains("'save_daily_report_destination_draft'"));
    expect(reportRepository, contains("'save_daily_report_signature'"));
    expect(reportRepository, contains('route_assignment_id'));

    expect(companyData, contains("title: const Text('会社データ')"));
    expect(companyData, contains("'法人番号（13桁）'"));
    expect(companyData, contains("'会社FAX番号'"));
    expect(companyData, contains("'銀行名'"));
    expect(companyData, contains("'支店名'"));
    expect(companyData, contains("'口座番号'"));
    expect(companyData, contains("'口座名義'"));
    expect(companyData, contains("'カメラで撮影'"));
    expect(companyData, contains("'写真ライブラリから選択'"));

    expect(profile, contains("'個人SKO ID'"));
    expect(profileRepository, contains("'change_personal_sko_id'"));
    expect(home, contains("'本日の出勤'"));
    expect(home, contains('LongPressDraggable<String>'));
    expect(home, contains('DragTarget<String>'));
    expect(home, contains('onReorderAction'));
    final todayIndex = home.indexOf("'本日の出勤'");
    expect(
      home.substring(todayIndex, todayIndex + 280),
      contains('titleMedium'),
    );
  });
}
