import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sk_works/features/attendance/attendance_correction_repository.dart';
import 'package:sk_works/features/attendance/bulk_attendance_correction_page.dart';
import 'package:sk_works/features/attendance/attendance_correction_allowance_notice.dart';

const entry = AttendanceCorrectionEntry(id: 'synthetic-entry', date: '2026/10/28',
  workerName: 'テストメンバー', siteName: 'テスト現場', workCategory: 'day',
  manDays: 1, overtimeHours: 3, earlyHours: 0, nightHours: 0,
  allowanceYen: 1234, allowanceNames: ['PC'], notes: 'PC');

Future<Map<String, dynamic>> editHours(WidgetTester tester,
    {Map<String, dynamic>? proposed}) async {
  Map<String, dynamic>? saved;
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: Builder(builder: (context) =>
    TextButton(onPressed: () async {
      saved = await Navigator.of(context).push<Map<String, dynamic>>(MaterialPageRoute(
        builder: (_) => attendanceCorrectionEditorForTesting(entry: entry,
          proposed: proposed ?? entry.snapshot())));
    }, child: const Text('編集'))))));
  await tester.tap(find.text('編集')); await tester.pumpAndSettle();
  final hours = find.byWidgetPredicate((widget) => widget is TextField && widget.decoration?.labelText == '残業');
  await tester.enterText(hours, '0');
  await tester.tap(find.text('修正内容を保存')); await tester.pumpAndSettle();
  return saved!;
}

void main() {
  testWidgets('hours-only correction preserves unedited amount names and notes', (tester) async {
    final saved = await editHours(tester);
    expect(saved['overtimeHours'], 0);
    expect(saved['allowanceYen'], 1234);
    expect(saved['allowanceNames'], ['PC']);
    expect(saved['notes'], 'PC');
    expect(saved['workCategory'], 'day');
  });
  testWidgets('reopening a draft preserves its captured legacy amount', (tester) async {
    final saved = await editHours(tester, proposed: {...entry.snapshot(), 'allowanceYen': 5678});
    expect(saved['allowanceYen'], 5678);
    expect(saved['allowanceNames'], ['PC']);
  });
  test('only explicitly removed allowance names produce the warning', () {
    expect(removedAttendanceAllowanceNames(entry.snapshot(), entry.snapshot()), isEmpty);
    expect(removedAttendanceAllowanceNames(entry.snapshot(), {...entry.snapshot(), 'allowanceNames': <String>[]}), ['PC']);
    expect(removedAttendanceAllowanceNames(entry.snapshot(), {...entry.snapshot(), 'allowanceNames': ['PC', '鉄骨']}), isEmpty);
    expect(removedAttendanceAllowanceNames(entry.snapshot(), {'overtimeHours': 0}), isEmpty);
  });
  test('exact protected server rejection gives instructions without bypassing it', () {
    const protected = PostgrestException(code: '22023', message:
      '署名済みの会社共通手当は、この勤怠修正では削除できません。日報の修正承認後に手当を変更し、再署名してください。');
    final message = protectedAttendanceAllowanceMessage(protected)!;
    expect(message, contains('元の手当を残して'));
    expect(message, contains('日報で手当を変更して再署名'));
    expect(message, contains('この申請は承認せず、却下'));
    expect(message, contains('以前の申請を再承認しないで'));
    expect(message, isNot(contains('PostgrestException')));
    expect(protectedAttendanceAllowanceMessage(const PostgrestException(code: '22023', message: 'Different invalid argument')), isNull);
    expect(protectedAttendanceAllowanceMessage(StateError('unrelated')), isNull);
  });
}
