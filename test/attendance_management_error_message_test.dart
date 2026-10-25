import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/attendance/attendance_management_page.dart';

void main() {
  test('signed report deletion identifies the prerequisite without exposing PostgREST details', () {
    final message = attendanceManagementActionErrorMessage(
      Exception('PostgrestException(message: shared_report_roster_requires_approved_edit, code: 55000, details: Internal Server Error)'));
    expect(message, contains('サイン済み日報'));
    expect(message, contains('手直し'));
    expect(message, isNot(contains('PostgrestException')));
    expect(message, isNot(contains('55000')));
  });
  test('unknown backend errors do not expose response internals', () {
    expect(attendanceManagementActionErrorMessage(Exception('private database context')),
      '処理結果を確認できませんでした。通信状態を確認して再読み込みしてください。');
  });
}
