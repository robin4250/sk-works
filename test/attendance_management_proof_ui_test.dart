import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/attendance/attendance_management_page.dart';
import 'package:sk_works/features/attendance/attendance_management_repository.dart';

import 'attendance_unrecorded_punches_test.dart' as fixture;

void main() {
  {
    testWidgets('management saves inside authorized visit without a per-operation password dialog', (tester) async {
      final f = fixture.Fixture()..managementProof = true;
      await tester.runAsync(f.start);
      final repository = fixture.PageFixture(f.client);
      repository.onLoad = (worker, date) async => AttendanceManagementCell(
        mode: 'work', date: date, workerId: worker, siteId: fixture.site,
        manDays: 1, clockIn: DateTime(2026, 10, 25, 8),
        clockOut: DateTime(2026, 10, 25, 17));
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.runAsync(f.client.dispose);
      });
      await tester.pumpWidget(MaterialApp(home: AttendanceManagementPage(repository: repository)));
      await tester.pumpAndSettle();
      final save = find.widgetWithText(FilledButton, '登録・編集を直接反映');
      await tester.scrollUntilVisible(save, 250,
        scrollable: find.descendant(of: find.byType(ListView).first,
          matching: find.byType(Scrollable)).first);
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(find.text('勤怠操作の第二認証'), findsNothing);
      expect(f.calls.where((r) => r.url.path.contains('/functions/v1/')), isEmpty);
      expect(f.calls.where((r) => r.url.path.endsWith('/force_manage_attendance_with_proof')), isEmpty);
      expect(f.calls.where((r) => r.url.path.endsWith('/force_manage_attendance')), hasLength(1));
    });
  }
}
