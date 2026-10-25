import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/attendance/paid_work_hours_input_card.dart';
import 'package:sk_works/features/attendance/paid_work_hours_repository.dart';
import 'package:sk_works/features/attendance/paid_work_hours_report_section.dart';

const actor = '00000000-0000-0000-0000-000000000001';
const company = '00000000-0000-0000-0000-000000000002';
const worker = '00000000-0000-0000-0000-000000000003';
const report = '00000000-0000-0000-0000-000000000004';

Map<String, dynamic> payload() => {
  'schema': 1, 'actor_id': actor, 'company_id': company, 'worker_id': worker,
  'report_id': report, 'work_date': '2026-10-10', 'revision': 1,
  'scope_fingerprint': List.filled(64, 'a').join(), 'required': true,
  'editable': true, 'source_blocked': false, 'input_scope_current': true,
  'source_reasons': <String>[], 'hours': null,
};
PaidWorkHoursSnapshot parse(Map<String, dynamic> raw) => PaidWorkHoursSnapshot.parse(raw,
  actorId: actor, companyId: company, workerId: worker, reportId: report);

Map<String, dynamic> sharedPayload() => payload()..addAll({
  'contract_version': 2, 'work_report_frozen': true,
  'first_reporter_covers_work_only': true,
  'work_basis_sha256': List.filled(64, 'b').join(), 'report_status': 'draft',
});

void main() {
  test('unknown quantity and explicit zero stay distinct', () {
    expect(parse(payload()).hours, isNull);
    expect(parse(payload()..['hours'] = 0).hours, 0);
  });
  test('actor, company, worker and report scope are not interchangeable', () {
    for (final key in ['actor_id', 'company_id', 'worker_id', 'report_id']) {
      expect(() => parse(payload()..[key] = '00000000-0000-0000-0000-000000000099'), throwsStateError);
    }
  });
  test('unknown revisions, normalized invalid dates and missing source fail closed', () {
    for (final changed in [
      payload()..['revision'] = -1,
      payload()..['work_date'] = '2026-02-31',
      payload()..['scope_fingerprint'] = '',
      payload()..remove('editable'),
      payload()..['source_blocked'] = true,
    ]) {
      expect(() => parse(changed), throwsStateError);
    }
  });
  test('out of range, nonfinite and excessive precision hours fail closed', () {
    for (final hours in [-1, 24.1, double.nan, double.infinity, 7.12345]) {
      expect(() => parse(payload()..['hours'] = hours), throwsStateError);
    }
  });
  test('final report needs an explicit saved quantity, and zero is valid', () {
    expect(paidWorkHoursSignatureProblem([parse(payload())]), isNotNull);
    expect(paidWorkHoursSignatureProblem([parse(payload()..['hours'] = 0)]), isNull);
  });
  test('intermediate reports can sign but source conflicts are not ignored', () {
    final earlier = payload()..['editable'] = false..['source_blocked'] = true
      ..['source_reasons'] = ['report_is_not_final_closed_shift'];
    expect(paidWorkHoursSignatureProblem([parse(earlier)]), isNull);
    earlier['source_reasons'] = ['report_is_not_final_closed_shift', 'overlapping_shift_evidence'];
    expect(paidWorkHoursSignatureProblem([parse(earlier)]), isNotNull);
  });
  test('v2 first work signature does not approve unknown personal hours', () {
    final state = parse(sharedPayload()..addAll({
      'editable': false, 'source_blocked': true, 'source_reasons': ['open_shift'],
    }));
    expect(paidWorkHoursSignatureProblem([state]), isNull);
    expect(paidWorkHoursSignatureProblem([state], forSupervisor: true), isNotNull);
    expect(paidWorkHoursSignatureProblem([parse(sharedPayload()..['hours'] = 0)],
      forSupervisor: true), isNull);
  });
  test('unknown work-consent versions cannot relax signature validation', () {
    for (final changed in [
      sharedPayload()..['contract_version'] = 3,
      sharedPayload()..['contract_version'] = 2.0,
      sharedPayload()..remove('first_reporter_covers_work_only'),
      sharedPayload()..['work_basis_sha256'] = '',
      sharedPayload()..['report_status'] = 'unknown',
    ]) {
      expect(() => parse(changed), throwsStateError);
    }
  });
  testWidgets('blank input is not submitted as zero', (tester) async {
    var calls = 0;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: PaidWorkHoursInputCard(
      snapshot: parse(payload()), onSave: (_) async { calls++; return parse(payload()); }, onSaved: (_) {},
    ))));
    await tester.tap(find.text('実勤務時間を保存'));
    await tester.pump();
    expect(calls, 0);
    expect(find.textContaining('空欄は0時間になりません'), findsOneWidget);
  });
  testWidgets('explicit zero is sent once and successful readback is delivered', (tester) async {
    final calls = <String>[];
    PaidWorkHoursSnapshot? delivered;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: PaidWorkHoursInputCard(
      snapshot: parse(payload()), onSave: (text) async { calls.add(text); return parse(payload()..['hours'] = 0); },
      onSaved: (value) => delivered = value,
    ))));
    await tester.enterText(find.byKey(const ValueKey('paid-work-hours-input')), '0');
    await tester.tap(find.text('実勤務時間を保存'));
    await tester.pumpAndSettle();
    expect(calls, ['0']);
    expect(delivered?.hours, 0);
  });
  testWidgets('v2 personal confirmation does not ask to erase the work signature', (tester) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: PaidWorkHoursInputCard(
      snapshot: parse(sharedPayload()),
      onSave: (_) async => parse(sharedPayload()..['hours'] = 7.25), onSaved: (_) {},
    ))));
    await tester.enterText(find.byKey(const ValueKey('paid-work-hours-input')), '7.25');
    await tester.tap(find.text('実勤務時間を確認して保存'));
    await tester.pumpAndSettle();
    expect(find.textContaining('報告者サインは変更していません'), findsOneWidget);
    expect(find.textContaining('署名を取り直してください'), findsNothing);
  });
  testWidgets('stale input source starts blank rather than reusing previous quantity', (tester) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: PaidWorkHoursInputCard(
      snapshot: parse(payload()..['hours'] = 7.5..['input_scope_current'] = false),
      onSave: (_) async => parse(payload()), onSaved: (_) {},
    ))));
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, '');
    expect(find.textContaining('勤務記録が変わりました'), findsOneWidget);
  });
  testWidgets('blocked or signed source cannot submit', (tester) async {
    for (final source in [
      payload()..['editable'] = false..['source_blocked'] = true..['source_reasons'] = ['open_shift'],
      payload()..['editable'] = false,
    ]) {
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: PaidWorkHoursInputCard(
        snapshot: parse(source), onSave: (_) async => parse(payload()), onSaved: (_) {},
      ))));
      expect(tester.widget<TextField>(find.byType(TextField)).enabled, false);
      expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNull);
    }
  });
  testWidgets('ordinary reports with no selected hour item do not add a card', (tester) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: PaidWorkHoursInputCard(
      snapshot: parse(payload()..['required'] = false),
      onSave: (_) async => parse(payload()), onSaved: (_) {},
    ))));
    expect(find.byType(TextField), findsNothing);
  });
  testWidgets('late save response cannot update a different report scope', (tester) async {
    final result = Completer<PaidWorkHoursSnapshot>();
    var delivered = 0;
    Widget page(PaidWorkHoursSnapshot state) => MaterialApp(home: Scaffold(body: PaidWorkHoursInputCard(
      snapshot: state, onSave: (_) => result.future, onSaved: (_) { delivered++; },
    )));
    await tester.pumpWidget(page(parse(payload())));
    await tester.enterText(find.byKey(const ValueKey('paid-work-hours-input')), '7.5');
    await tester.tap(find.text('実勤務時間を保存'));
    await tester.pump();
    await tester.pumpWidget(page(parse(payload()..['revision'] = 2)));
    result.complete(parse(payload()..['hours'] = 7.5));
    await tester.pumpAndSettle();
    expect(delivered, 0);
    expect(tester.takeException(), isNull);
  });
}
