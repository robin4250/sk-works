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
  testWidgets('unknown save result blocks further writes until authoritative reload', (tester) async {
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
    expect(find.text('保存結果を確認できません。画面を閉じて再読み込みしてください。'), findsOneWidget);
    expect(received.single.workerId, 'w');
    expect(received.single.revision, 2);
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, '下書きを保存')).onPressed, isNull);
    // A server commit followed by a lost response must not be resent using
    // the old revision, even if a user taps the disabled button again.
    await tester.ensureVisible(find.text('下書きを保存'));
    await tester.tap(find.text('下書きを保存'));
    await tester.pumpAndSettle();
    expect(calls, 1);
  });

  testWidgets('unknown publication result blocks both save and publication', (tester) async {
    var saves = 0, publications = 0;
    await tester.pumpWidget(MaterialApp(home: ShiftScheduleEditor(
      companyId: 'c', date: DateTime(2026, 10, 26),
      people: const [ShiftPersonOption(id: 'w', name: '従業員')],
      sites: const [ShiftSiteOption(id: 's', name: '現場')],
      initial: const ShiftDayDraft(holiday: false, night: false, siteId: 's',
        start: TimeOfDay(hour: 8, minute: 0), end: TimeOfDay(hour: 17, minute: 0),
        checkLate: true, checkEarly: true), revisions: const {'w': 2},
      save: (_) async { saves++; },
      publish: (_) async { publications++; throw StateError('response lost'); },
    )));
    await tester.tap(find.text('従業員'));
    await tester.pump();
    await tester.ensureVisible(find.text('下書きを保存'));
    await tester.tap(find.text('下書きを保存'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('保存したシフトを確定'));
    await tester.tap(find.text('保存したシフトを確定'));
    await tester.pumpAndSettle();
    expect(find.text('確定結果を確認できません。画面を閉じて再読み込みしてください。'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, '下書きを保存')).onPressed, isNull);
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, '保存したシフトを確定')).onPressed, isNull);
    expect(saves, 1);
    expect(publications, 1);
  });
}
