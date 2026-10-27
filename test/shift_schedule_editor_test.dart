import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/shifts/shift_day_editor.dart';
import 'package:sk_works/features/shifts/shift_draft_request.dart';
import 'package:sk_works/features/shifts/shift_people_picker.dart';
import 'package:sk_works/features/shifts/shift_schedule_editor.dart';

void main() {
  testWidgets('publish is enabled only for the saved revision', (tester) async {
    List<ShiftDraftRequest> published = [];
    await tester.pumpWidget(MaterialApp(home: ShiftScheduleEditor(
      companyId: 'c', date: DateTime(2026, 10, 26),
      people: const [ShiftPersonOption(id: 'w', name: '従業員')],
      sites: const [ShiftSiteOption(id: 's', name: '現場')],
      initial: const ShiftDayDraft(holiday: false, night: false, siteId: 's',
        start: TimeOfDay(hour: 8, minute: 0), end: TimeOfDay(hour: 17, minute: 0),
        checkLate: true, checkEarly: true), revisions: const {'w': 2},
      save: (_) async {}, publish: (rows) async { published = rows; },
    )));
    await tester.tap(find.text('従業員'));
    await tester.pump();
    await tester.ensureVisible(find.text('下書きを保存'));
    await tester.tap(find.text('下書きを保存'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('保存したシフトを確定'));
    await tester.tap(find.text('保存したシフトを確定'));
    await tester.pumpAndSettle();
    expect(published.single.revision, 3);
    expect(find.text('シフトを確定しました。'), findsOneWidget);
  });
  testWidgets('failed save preserves selection and can be retried', (tester) async {
    var calls = 0;
    List<ShiftDraftRequest> received = [];
    await tester.pumpWidget(MaterialApp(home: ShiftScheduleEditor(
      companyId: 'c', date: DateTime(2026, 10, 26),
      people: const [ShiftPersonOption(id: 'w', name: '従業員')],
      sites: const [ShiftSiteOption(id: 's', name: '現場')],
      initial: const ShiftDayDraft(holiday: false, night: false, siteId: 's',
        start: TimeOfDay(hour: 8, minute: 0), end: TimeOfDay(hour: 17, minute: 0),
        checkLate: true, checkEarly: true), revisions: const {'w': 2},
      save: (rows) async { calls++; received = rows; if (calls == 1) throw StateError('offline'); },
    )));
    await tester.tap(find.text('従業員'));
    await tester.pump();
    await tester.ensureVisible(find.text('下書きを保存'));
    await tester.tap(find.text('下書きを保存'));
    await tester.pumpAndSettle();
    expect(find.text('保存結果を確認できません。再読み込みして確認してください。'), findsOneWidget);
    expect(received.single.workerId, 'w');
    expect(received.single.revision, 2);
    await tester.ensureVisible(find.text('下書きを保存'));
    await tester.tap(find.text('下書きを保存'));
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(find.text('下書きを保存しました。'), findsOneWidget);
    await tester.ensureVisible(find.text('下書きを保存'));
    await tester.tap(find.text('下書きを保存'));
    await tester.pumpAndSettle();
    expect(calls, 3);
    expect(received.single.revision, 3);
    expect(find.text('下書きを保存しました。'), findsOneWidget);
  });
}
