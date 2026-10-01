import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('attendance site selection persists for home display before clock in', () {
    final page = File(
      'lib/features/attendance/attendance_verification_page.dart',
    ).readAsStringSync();
    final app = File('lib/app_v2.dart').readAsStringSync();

    expect(page, contains("'sko_attendance_selected_site_id'"));
    expect(page, contains("'sko_attendance_selected_site_name'"));
    expect(page, contains('_saveSelectedSite(value)'));
    expect(page, contains('_loadSavedSiteId()'));

    expect(app, contains("'sko_attendance_selected_site_name'"));
    expect(app, contains("if (siteLabel == '未選択')"));
  });
}
