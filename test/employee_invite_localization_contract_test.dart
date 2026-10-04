import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('employee registration supports Japanese and English without changing auth', () {
    final page =
        File('lib/features/people/employee_invite_page.dart').readAsStringSync();

    expect(page, contains("SkoLanguageController.isEnglish"));
    expect(page, contains("'Employee Registration'"));
    expect(page, contains("'Create Employee Registration'"));
    expect(page, contains("'Share the Temporary Password'"));
    expect(page, contains("'Share by QR Code'"));
    expect(page, contains("'Register Another Employee'"));
    expect(page, contains("'Role & Approval Access'"));
    expect(page, contains("'Make sub-administrator'"));
    expect(page, contains("'Make approval assignee'"));
    expect(page, contains('repository.createInvite('));
    expect(page, contains("requestedRole: _makeSubAdmin ? 'manager' : 'viewer'"));
    expect(page, contains('requestedApprovalAssignee: _makeApprovalAssignee'));
  });
}
