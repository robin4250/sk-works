import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('paid leave balance errors are localized and prechecked', () {
    final repo = File('lib/features/attendance/paid_leave_repository.dart').readAsStringSync();
    final future = File('lib/features/attendance/paid_leave_page.dart').readAsStringSync();
    final past = File('lib/features/attendance/paid_leave_correction_page.dart').readAsStringSync();

    expect(repo, contains('paid leave balance exceeded'));
    expect(repo, contains('有給残日数が不足しています'));
    expect(future, contains('summary.remainingDays < _selected.length'));
    expect(past, contains('summary.remainingDays < _selected.length'));
    expect(past, contains('個別給与設定の有給付与日数を確認してください'));
  });
}
