import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/attendance/attendance_management_page.dart';
import 'package:sk_works/features/attendance/attendance_management_repository.dart';

import 'attendance_unrecorded_punches_test.dart' as fixture;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final editStart in [false, true]) {
    testWidgets(
      editStart
          ? 'edited time uses the entered minute while untouched end retains precision'
          : 'confirming quantity preserves both original clock timestamps',
      (tester) async {
        final f = fixture.Fixture();
        await tester.runAsync(f.start);
        final repository = fixture.PageFixture(f.client);
        repository.onLoad = (id, date) async => AttendanceManagementCell(
          mode: 'work',
          date: date,
          workerId: id,
          siteId: fixture.site,
          hasUnrecordedPunches: true,
          clockIn: DateTime(2026, 10, 13, 1, 13, 20, 264, 851),
          clockOut: DateTime(2026, 10, 13, 1, 13, 26, 155, 896),
        );
        addTearDown(() async {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.runAsync(f.client.dispose);
        });
        await tester.pumpWidget(
          MaterialApp(home: AttendanceManagementPage(repository: repository)),
        );
        await tester.pumpAndSettle();
        Finder field(String label) => find.byWidgetPredicate(
          (widget) => widget is TextField && widget.decoration?.labelText == label,
        );
        await tester.ensureVisible(field('人工'));
        await tester.enterText(field('人工'), '1');
        if (editStart) {
          await tester.ensureVisible(field('出勤時刻'));
          await tester.enterText(field('出勤時刻'), '02:45');
        }
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pumpAndSettle();
        final save = find.widgetWithText(FilledButton, '登録・編集を直接反映');
        await tester.scrollUntilVisible(
          save,
          300,
          scrollable: find.byWidgetPredicate(
            (widget) =>
                widget is Scrollable &&
                widget.axisDirection == AxisDirection.down,
          ).first,
        );
        await tester.pumpAndSettle();
        await tester.ensureVisible(save);
        await tester.pumpAndSettle();
        expect(save.hitTestable(), findsOneWidget);
        await tester.tap(save);
        await tester.pumpAndSettle();
        final request = f.calls.singleWhere(
          (r) => r.url.path == '/rest/v1/rpc/force_manage_attendance',
        );
        final payload = jsonDecode(request.body) as Map<String, dynamic>;
        final item = (payload['p_items'] as List).single as Map<String, dynamic>;
        expect(item['man_days'], 1);
        expect(item['clock_in'], editStart ? '02:45' : '01:13:20.264851');
        expect(item['clock_out'], '01:13:26.155896');
      },
    );
  }
}
