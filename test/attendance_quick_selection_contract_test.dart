import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('attendance quick selection preserves permission and preferred site behavior', () {
    final selection =
        File('lib/features/attendance/attendance_quick_selection_page.dart')
            .readAsStringSync();
    final verification =
        File('lib/features/attendance/attendance_verification_page.dart')
            .readAsStringSync();
    final repository =
        File('lib/features/attendance/attendance_verification_repository.dart')
            .readAsStringSync();

    expect(selection, contains('canManageAttendance()'));
    expect(selection, contains('_canManage && !_saving'));
    expect(selection, contains('saveSettings('));
    expect(selection, contains('savePreferredSiteId(_siteId)'));
    expect(selection, contains("'出勤方法と現場'"));
    expect(selection, contains("'現場を選択'"));

    expect(verification, contains('loadPreferredSiteId()'));
    expect(verification, contains('preferredExists'));
    expect(verification, contains('savePreferredSiteId(value)'));

    expect(repository, contains('SharedPreferences.getInstance()'));
    expect(repository, contains('loadPreferredSiteId()'));
    expect(repository, contains('savePreferredSiteId(String? siteId)'));
  });
}
