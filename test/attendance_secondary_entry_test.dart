import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/attendance/attendance_protected_routes.dart';
import 'package:sk_works/features/attendance/attendance_management_page.dart';
import 'package:sk_works/features/attendance/attendance_management_repository.dart';
import 'package:sk_works/features/attendance/attendance_worker_list_page.dart';

class _NeverReadManagement implements AttendanceManagementRepository {
  int reads = 0;
  @override dynamic noSuchMethod(Invocation invocation) {
    reads++;
    throw StateError('Protected attendance must not load before authentication');
  }
}

void main() {
  testWidgets('secondary authentication blocks list and management mounting and reads', (tester) async {
    final repository = _NeverReadManagement();
    for (final route in [attendanceWorkerListDestination(),
      attendanceManagementDestination(repository: repository, initialWorkerId: 'synthetic-worker',
        initialDate: DateTime(2026, 10, 25), restrictedRecovery: true)]) {
      await tester.pumpWidget(MaterialApp(home: route));
      await tester.pumpAndSettle();
      expect(find.byType(AttendanceWorkerListPage), findsNothing);
      expect(find.byType(AttendanceManagementPage), findsNothing);
      expect(find.textContaining('ログイン状態を確認できません'), findsOneWidget);
      expect(repository.reads, 0);
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  test('all production attendance list and management entrances use the protected route boundary', () {
    final allowed = {
      'lib/features/attendance/attendance_protected_routes.dart',
      'lib/features/attendance/attendance_management_page.dart',
      'lib/features/attendance/attendance_worker_list_page.dart',
    };
    final rawEntry = RegExp(r'\b(?:AttendanceManagementPage|AttendanceWorkerListPage)\s*\(');
    final unguarded = Directory('lib').listSync(recursive: true).whereType<File>()
      .where((file) => file.path.endsWith('.dart') && !allowed.contains(file.path.replaceAll('\\', '/')))
      .where((file) => rawEntry.hasMatch(file.readAsStringSync())).map((file) => file.path).toList();
    expect(unguarded, isEmpty, reason: 'Direct routes must not bypass secondary authentication');
  });
}
