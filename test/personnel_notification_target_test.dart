import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/people/worker_personnel_change_approvals_page.dart';

const _target = '11111111-1111-4111-8111-111111111111';
const _other = '22222222-2222-4222-8222-222222222222';
const _missingMessage = '対象の申請は完了済み、または閲覧できません。';
Map<String, dynamic> _row(String id, String name) => {
  'id': id, 'worker_name': name, 'approval_count': 0, 'required_approvals': 1,
  'proposed': <String, dynamic>{},
};

Future<void> _show(WidgetTester tester, String? target,
    Future<List<Map<String, dynamic>>> Function() load) async {
  await tester.pumpWidget(MaterialApp(home: WorkerPersonnelChangeApprovalsPage(
    initialRequestId: target, loadRequests: load,
  )));
  await tester.pump();
}

void main() {
  final rows = [_row(_target, 'Target worker'), _row(_other, 'Other worker')];

  testWidgets('normal null inbox retains every pending row', (tester) async {
    await _show(tester, null, () async => rows);
    expect(find.text('Target worker'), findsOneWidget);
    expect(find.text('Other worker'), findsOneWidget);
    expect(find.text(_missingMessage), findsNothing);
  });

  testWidgets('exact UUID displays only the requested pending row', (tester) async {
    await _show(tester, _target, () async => rows);
    expect(find.text('Target worker'), findsOneWidget);
    expect(find.text('Other worker'), findsNothing);
  });

  for (final target in ['', 'invalid', ' $_target ', '33333333-3333-4333-8333-333333333333']) {
    testWidgets('absent/invalid target $target never shows another request', (tester) async {
      await _show(tester, target, () async => rows);
      expect(find.text('Target worker'), findsNothing);
      expect(find.text('Other worker'), findsNothing);
      expect(find.text(_missingMessage), findsOneWidget);
    });
  }

  testWidgets('empty ordinary inbox keeps its existing empty message', (tester) async {
    await _show(tester, null, () async => []);
    expect(find.text('変更承認待ちはありません'), findsOneWidget);
    expect(find.text(_missingMessage), findsNothing);
  });

  for (final oldFails in [false, true]) {
    testWidgets('target change clears previous rows and rejects late success/error=$oldFails', (tester) async {
      await _show(tester, _target, () async => rows);
      expect(find.text('Target worker'), findsOneWidget);
      final old = Completer<List<Map<String, dynamic>>>();
      // A new target starts a new generation while an earlier read is still pending.
      await _show(tester, _other, () => old.future);
      expect(find.text('Target worker'), findsNothing);
      final current = Completer<List<Map<String, dynamic>>>();
      await _show(tester, _target, () => current.future);
      current.complete(rows);
      await tester.pumpAndSettle();
      expect(find.text('Target worker'), findsOneWidget);
      if (oldFails) {
        old.completeError(StateError('obsolete request failed'));
      } else {
        old.complete([_row(_other, 'Late other worker')]);
      }
      await tester.pumpAndSettle();
      expect(find.text('Target worker'), findsOneWidget);
      expect(find.text('Late other worker'), findsNothing);
      expect(find.textContaining('obsolete request failed'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('late response after dispose does not publish or throw', (tester) async {
    final pending = Completer<List<Map<String, dynamic>>>();
    await _show(tester, _target, () => pending.future);
    await tester.pumpWidget(const SizedBox());
    pending.complete(rows);
    await tester.pumpAndSettle();
    expect(find.text('Target worker'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
