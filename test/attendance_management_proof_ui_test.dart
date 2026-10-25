import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/attendance/attendance_management_page.dart';
import 'package:sk_works/features/attendance/attendance_management_repository.dart';

import 'attendance_unrecorded_punches_test.dart' as fixture;

void main() {
  for (final confirm in [false, true]) {
    testWidgets('management second authentication ${confirm ? 'executes exact save once' : 'cancel writes nothing'}', (tester) async {
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
      expect(find.text('勤怠操作の第二認証'), findsOneWidget);
      expect(f.calls.where((r) => r.url.path.endsWith('/force_manage_attendance')), isEmpty);
      if (confirm) {
        final password = find.byWidgetPredicate((widget) => widget is TextField &&
          widget.decoration?.labelText == '第2パスワード');
        expect(tester.widget<TextField>(password).obscureText, isTrue);
        await tester.enterText(password, 'synthetic-only');
        await tester.tap(find.widgetWithText(FilledButton, '認証して実行'));
      } else {
        await tester.tap(find.widgetWithText(TextButton, 'キャンセル'));
      }
      await tester.pumpAndSettle();
      final writes = f.calls.where((r) => r.url.path.endsWith('/force_manage_attendance_with_proof')).toList();
      expect(writes, hasLength(confirm ? 1 : 0));
      if (confirm) {
        final targetRequest = f.calls.singleWhere((r) => r.url.path.endsWith('/attendance_management_reauthentication_target'));
        final targetPayload = jsonDecode(targetRequest.body) as Map;
        final actual = jsonDecode(writes.single.body) as Map;
        expect(actual['p_items'], targetPayload['p_items']);
        expect(actual['p_action'], 'upsert');
        expect(actual['p_proof'], List.filled(64, 'b').join());
      } else {
        expect(f.calls.where((r) => r.url.path.contains('/functions/v1/')), isEmpty);
        expect(find.textContaining('attendance_reauthentication_cancelled'), findsNothing);
      }
    });
  }
}
