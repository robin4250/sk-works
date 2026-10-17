import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/daily_reports/daily_report_approvals_page.dart';
import 'package:sk_works/features/daily_reports/daily_report_repository.dart';

class _Repository implements DailyReportRepository {
  final decisions = <(String, bool)>[];
  final queries = <String?>[];
  Completer<String> response = Completer<String>();
  bool pending = true;
  Completer<List<Map<String, dynamic>>>? nextRead;

  @override
  Future<List<Map<String, dynamic>>> loadPendingApprovals({String? requestId}) async {
    queries.add(requestId);
    final delayed = nextRead;
    nextRead = null;
    if (delayed != null) return delayed.future;
    return pending ? [{
      'id': 'request-one', 'reason': '修正', 'status': 'pending',
      'daily_reports': {'report_date': '2026-10-17', 'sites': {'name': '確認現場'}},
    }] : [];
  }

  @override
  Future<String> decideEdit({required String requestId, required bool approve}) async {
    decisions.add((requestId, approve));
    final result = await response.future;
    if (result == 'approved' || result == 'rejected') pending = false;
    return result;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _open(WidgetTester tester, _Repository repository) async {
  await tester.pumpWidget(MaterialApp(home: DailyReportApprovalsPage(
    initialRequestId: 'request-one', repositoryForTesting: repository)));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('retained approve and reject callbacks cannot submit competing decisions', (tester) async {
    final repository = _Repository();
    await _open(tester, repository);
    final approve = tester.widget<FilledButton>(find.widgetWithText(FilledButton, '承認')).onPressed!;
    final reject = tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, '却下')).onPressed!;
    approve();
    approve();
    reject();
    expect(repository.decisions, [('request-one', true)]);
    await tester.pump();
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, '承認')).onPressed, isNull);
    expect(tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, '却下')).onPressed, isNull);
    repository.response.complete('approved');
    await tester.pumpAndSettle();
    expect(repository.queries, ['request-one', 'request-one']);
    expect(find.text('設定された承認担当者の承認が完了し、編集可能になりました'), findsOneWidget);
    expect(find.text('承認'), findsNothing);
  });

  testWidgets('failure preserves request and releases both controls for explicit retry', (tester) async {
    final repository = _Repository();
    await _open(tester, repository);
    await tester.tap(find.widgetWithText(FilledButton, '承認'));
    repository.response.completeError(StateError('fixture failure'));
    await tester.pumpAndSettle();
    expect(find.textContaining('処理できませんでした'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, '承認')).onPressed, isNotNull);
    expect(tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, '却下')).onPressed, isNotNull);
    repository.response = Completer<String>();
    await tester.tap(find.widgetWithText(OutlinedButton, '却下'));
    expect(repository.decisions, [('request-one', true), ('request-one', false)]);
    repository.response.complete('rejected');
    await tester.pumpAndSettle();
    expect(find.text('修正申請を却下しました'), findsOneWidget);
  });

  testWidgets('partial approval retains pending request and existing next-step feedback', (tester) async {
    final repository = _Repository();
    await _open(tester, repository);
    await tester.tap(find.widgetWithText(FilledButton, '承認'));
    repository.response.complete('pending');
    await tester.pumpAndSettle();
    expect(find.text('承認しました。必要な承認が完了するまでお待ちください'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, '承認')).onPressed, isNotNull);
  });

  testWidgets('retained refresh during approval cannot resurrect a pending row', (tester) async {
    final repository = _Repository();
    await _open(tester, repository);
    final refresh = tester.widget<RefreshIndicator>(find.byType(RefreshIndicator)).onRefresh;
    await tester.tap(find.widgetWithText(FilledButton, '承認'));
    await refresh();
    expect(repository.queries, ['request-one']);
    repository.response.complete('approved');
    await tester.pumpAndSettle();
    expect(repository.queries, ['request-one', 'request-one']);
    expect(find.text('承認'), findsNothing);
    expect(find.text('確認現場'), findsNothing);
  });

  testWidgets('delayed refresh rejects stale approval and coalesces further UI refreshes', (tester) async {
    final repository = _Repository();
    await _open(tester, repository);
    final approve = tester.widget<FilledButton>(find.widgetWithText(FilledButton, '承認')).onPressed!;
    final refresh = tester.widget<RefreshIndicator>(find.byType(RefreshIndicator)).onRefresh;
    final delayed = Completer<List<Map<String, dynamic>>>();
    repository.nextRead = delayed;
    final reading = refresh();
    approve();
    await refresh();
    await tester.pump();
    expect(repository.decisions, isEmpty);
    expect(repository.queries, ['request-one', 'request-one']);
    delayed.complete([{'id': 'request-one', 'status': 'pending'}]);
    await reading;
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '承認'));
    await refresh();
    expect(repository.decisions, [('request-one', true)]);
    expect(repository.queries.length, 2);
    repository.response.complete('approved');
    await tester.pumpAndSettle();
    expect(repository.queries.length, 3);
    expect(find.text('承認'), findsNothing);
  });

  testWidgets('closing page during decision does not setState after disposal', (tester) async {
    final repository = _Repository();
    await _open(tester, repository);
    await tester.tap(find.widgetWithText(FilledButton, '承認'));
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    repository.response.complete('approved');
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(repository.queries, ['request-one']);
  });
}
