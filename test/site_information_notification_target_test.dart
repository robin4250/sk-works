import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/sites/site_information_approvals_page.dart';

const target = '11111111-1111-4111-8111-111111111111';
const other = '22222222-2222-4222-8222-222222222222';
const unavailable = '対象の申請は完了済み、または閲覧できません。';

Map<String, dynamic> row(String id, String name, String status) => {
  'id': id, 'site_name': name, 'status': status,
  'can_review': true, 'before_values': <String, dynamic>{},
  'proposed_values': <String, dynamic>{},
};

Future<void> show(WidgetTester tester, String? id,
    Future<List<Map<String, dynamic>>> Function() load) => tester.pumpWidget(
  MaterialApp(home: SiteInformationApprovalsPage(
    initialRequestId: id, loadRequests: load,
  )),
);

void main() {
  testWidgets('normal inbox keeps pending requests and hides completed rows', (tester) async {
    await show(tester, null, () async => [
      row(target, 'Pending site', 'pending'), row(other, 'Approved site', 'approved'),
    ]);
    await tester.pumpAndSettle();
    expect(find.text('Pending site'), findsOneWidget);
    expect(find.text('Approved site'), findsNothing);
    expect(find.text('承認'), findsOneWidget);
  });

  for (final status in ['pending', 'approved', 'rejected']) {
    testWidgets('target shows only exact $status request', (tester) async {
      await show(tester, target, () async => [
        row(other, 'Other pending site', 'pending'), row(target, 'Target site', status),
      ]);
      await tester.pumpAndSettle();
      expect(find.text('Target site'), findsOneWidget);
      expect(find.text('Other pending site'), findsNothing);
      expect(find.text('承認'), status == 'pending' ? findsOneWidget : findsNothing);
      if (status != 'pending') {
        expect(find.text(status == 'approved' ? '承認済み' : '差し戻し済み'), findsOneWidget);
      }
    });
  }

  for (final id in [target, '', 'invalid', '$target ']) {
    testWidgets('absent or invalid target $id never shows another request', (tester) async {
      await show(tester, id, () async => [row(other, 'Other site', 'pending')]);
      await tester.pumpAndSettle();
      expect(find.text('Other site'), findsNothing);
      expect(find.text(unavailable), findsOneWidget);
      expect(find.text('承認'), findsNothing);
    });
  }

  for (final fail in [false, true]) {
    testWidgets('target change rejects late old ${fail ? 'error' : 'success'}', (tester) async {
      final old = Completer<List<Map<String, dynamic>>>();
      final current = Completer<List<Map<String, dynamic>>>();
      var calls = 0;
      Future<List<Map<String, dynamic>>> load() => calls++ == 0 ? old.future : current.future;
      await show(tester, target, load);
      final state = tester.state(find.byType(SiteInformationApprovalsPage));
      await show(tester, other, load);
      expect(tester.state(find.byType(SiteInformationApprovalsPage)), same(state));
      current.complete([row(other, 'Current site', 'approved')]);
      await tester.pumpAndSettle();
      if (fail) {
        old.completeError(StateError('stale failure'));
      } else {
        old.complete([row(target, 'Old site', 'pending')]);
      }
      await tester.pumpAndSettle();
      expect(find.text('Current site'), findsOneWidget);
      expect(find.text('Old site'), findsNothing);
      expect(find.textContaining('stale failure'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('target change immediately clears previously visible request', (tester) async {
    final next = Completer<List<Map<String, dynamic>>>();
    var calls = 0;
    Future<List<Map<String, dynamic>>> load() => calls++ == 0
        ? Future.value([row(target, 'Old visible site', 'pending')]) : next.future;
    await show(tester, target, load);
    await tester.pumpAndSettle();
    expect(find.text('Old visible site'), findsOneWidget);
    await show(tester, other, load);
    expect(find.text('Old visible site'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    next.complete([]);
    await tester.pumpAndSettle();
    expect(find.text(unavailable), findsOneWidget);
  });

  for (final fail in [false, true]) {
    testWidgets('disposed load ignores late ${fail ? 'error' : 'success'}', (tester) async {
      final result = Completer<List<Map<String, dynamic>>>();
      await show(tester, target, () => result.future);
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      if (fail) {
        result.completeError(StateError('disposed failure'));
      } else {
        result.complete([row(target, 'Disposed site', 'pending')]);
      }
      await tester.pumpAndSettle();
      expect(find.text('Disposed site'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}
