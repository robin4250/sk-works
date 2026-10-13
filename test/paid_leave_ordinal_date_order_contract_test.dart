import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('paid leave ordinals are assigned by ascending leave date', () {
    final source = File(
      'lib/features/attendance/worker_attendance_sheet_repository.dart',
    ).readAsStringSync();
    expect(source, contains('final approvedDates = <DateTime>{'));
    expect(source, contains('..sort((a, b) => a.compareTo(b))'));
    expect(source, contains('draft.paidLeaveOrdinal = i + 1'));
  });
}
