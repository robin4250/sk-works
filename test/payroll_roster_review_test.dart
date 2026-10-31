import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sk_works/features/payroll/payroll_review_page.dart';
import 'package:sk_works/features/payroll/payroll_review_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

String workerId(int i) =>
    '00000000-0000-4000-8000-${i.toString().padLeft(12, '0')}';

Map<String, dynamic> payload({String role = 'owner', bool missingId = false}) =>
    {
      'role': role,
      'company_name': 'Synthetic company',
      'is_admin': true,
      'can_confirm': false,
      'period_start': '2026-10-01',
      'workers': [
        for (var i = 0; i < 9; i++)
          <String, dynamic>{
            'id': workerId(i),
            'name': i == 8 ? 'Same name' : 'Employee $i',
            'visible_to_manager': false,
          },
      ],
      'statements': [
        for (var i = 0; i < 6; i++)
          {
            'id': 'statement-$i',
            if (!missingId || i != 0) 'worker_id': workerId(i),
            // A matching name must never substitute for worker identity.
            'worker_name': i == 0 ? 'Same name' : 'Employee $i',
            'period_start': '2026-10-01', 'period_end': '2026-10-31',
            'gross_pay': 0, 'deductions': 0, 'net_pay': 0,
            'revision': 1, 'workflow_state': i == 0 ? 'finalized' : 'draft',
            'detail': <String, dynamic>{},
          },
      ],
    };

class _CachedRepository implements PayrollReviewRepository {
  _CachedRepository(this.workspace);
  PayrollReviewWorkspace workspace;
  int reads = 0;
  @override
  Future<PayrollReviewWorkspace> loadWorkspace(DateTime month) async {
    reads++;
    return workspace;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected payroll write');
}

class _DelayedRepository implements PayrollReviewRepository {
  final requests = <DateTime, Completer<PayrollReviewWorkspace>>{};
  @override
  Future<PayrollReviewWorkspace> loadWorkspace(DateTime month) =>
      (requests[month] = Completer<PayrollReviewWorkspace>()).future;
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected payroll write');
}

Future<PayrollReviewWorkspace> readRpc(Map<String, dynamic> body) async {
  final client = SupabaseClient(
    'https://synthetic.invalid',
    'synthetic-public',
    authOptions: const AuthClientOptions(autoRefreshToken: false),
    httpClient: MockClient((request) async {
      expect(request.url.path, '/rest/v1/rpc/payroll_review_workspace');
      expect(jsonDecode(request.body), {'p_period_start': '2026-10-01'});
      return http.Response(
        jsonEncode(body),
        200,
        headers: {'content-type': 'application/json'},
        request: request,
      );
    }),
  );
  try {
    return await PayrollReviewRepository.forTesting(client)
        .loadWorkspace(DateTime(2026, 10));
  } finally {
    await client.dispose();
  }
}

void main() {
  testWidgets(
    'RPC identities survive projection and show real absence without creating zero slips',
    (tester) async {
      final workspace = (await tester.runAsync(() => readRpc(payload())))!;
      expect(
        workspace.items.map((item) => item.workerId),
        List.generate(6, (i) => workerId(i)),
      );
      expect(workspace.items.length, 6);
      // Existing finalized and zero-value records are preserved.
      expect(workspace.items.first.statement.workflowState, 'finalized');
      expect(
        workspace.items.every((item) => item.statement.netPay == 0),
        isTrue,
      );
      final repository = _CachedRepository(workspace);
      await tester.pumpWidget(
        MaterialApp(home: PayrollReviewPage(repository: repository)),
      );
      await tester.pumpAndSettle();
      expect(find.text('在籍社員 9名 ／ 当月明細 6件'), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey('payroll-roster-without-statements')),
      );
      await tester.pumpAndSettle();
      expect(find.text('この月の給与明細がありません'), findsNWidgets(3));
      expect(find.text('Employee 6'), findsOneWidget);
      expect(find.text('Employee 7'), findsOneWidget);
      expect(find.text('Same name'), findsWidgets);
      expect(repository.workspace.items.length, 6);
      expect(repository.reads, 1);
      expect(tester.takeException(), isNull);
    },
  );

  for (final role in ['manager', 'viewer']) {
    testWidgets('$role does not gain access to hidden roster names', (
      tester,
    ) async {
      final workspace = (await tester.runAsync(
        () => readRpc(payload(role: role)),
      ))!;
      await tester.pumpWidget(
        MaterialApp(
          home: PayrollReviewPage(repository: _CachedRepository(workspace)),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('payroll-roster-counts')), findsNothing);
      expect(
        find.byKey(const ValueKey('payroll-roster-without-statements')),
        findsNothing,
      );
      expect(find.text('Employee 6'), findsNothing);
      expect(find.text('Employee 7'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  test(
    'historical employee statements remain separate from the active roster',
    () async {
      final body = payload();
      (body['statements'] as List).add({
        'id': 'historical-statement',
        'worker_id': workerId(99),
        'worker_name': 'Former employee',
        'period_start': '2026-10-01',
        'period_end': '2026-10-31',
        'gross_pay': 1200,
        'net_pay': 1200,
        'deductions': 0,
        'detail': <String, dynamic>{},
        'revision': 2,
        'workflow_state': 'finalized',
      });
      final workspace = await readRpc(body);
      expect(workspace.workers.length, 9);
      expect(workspace.items.length, 7);
      expect(workspace.items.last.workerId, workerId(99));
      expect(workspace.items.last.statement.netPay, 1200);
    },
  );

  testWidgets(
    'unknown statement identity suppresses inferred missing-worker names',
    (tester) async {
      final workspace = (await tester.runAsync(
        () => readRpc(payload(missingId: true)),
      ))!;
      await tester.pumpWidget(
        MaterialApp(
          home: PayrollReviewPage(repository: _CachedRepository(workspace)),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('在籍社員 9名 ／ 当月明細 6件'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('payroll-roster-without-statements')),
        findsNothing,
      );
    },
  );

  for (final invalid in [
    null,
    42,
    ' ',
    'malformed',
    '00000000-0000-4000-8000-000000000000 ',
  ]) {
    test(
      'invalid roster identity disables absence inference: $invalid',
      () async {
        final body = payload();
        ((body['workers'] as List).last as Map)['id'] = invalid;
        expect((await readRpc(body)).canCompareRoster, isFalse);
      },
    );
  }

  test(
    'duplicate roster or statement identity disables absence inference',
    () async {
      final body = payload();
      ((body['workers'] as List).last as Map)['id'] = workerId(0);
      expect((await readRpc(body)).canCompareRoster, isFalse);
      final statements = payload();
      ((statements['statements'] as List).last as Map)['worker_id'] = workerId(
        0,
      );
      expect((await readRpc(statements)).canCompareRoster, isFalse);
    },
  );

  testWidgets(
    'late response from an earlier month cannot replace the selected month',
    (tester) async {
      final workspace = (await tester.runAsync(() => readRpc(payload())))!;
      final repository = _DelayedRepository();
      await tester.pumpWidget(
        MaterialApp(
          home: PayrollReviewPage(
            initialMonth: DateTime(2026, 10),
            repository: repository,
          ),
        ),
      );
      repository.requests[DateTime(2026, 10)]!.complete(workspace);
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.chevron_right));
      await tester.tap(find.byIcon(Icons.chevron_right));
      repository.requests[DateTime(2026, 12)]!.complete(
        PayrollReviewWorkspace(
          role: 'owner',
          companyName: 'Synthetic company',
          isAdmin: true,
          canConfirm: false,
          periodStart: DateTime(2026, 12),
          items: const [],
          workers: workspace.workers,
          rosterIdentitiesComplete: true,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('在籍社員 9名 ／ 当月明細 0件'), findsOneWidget);
      repository.requests[DateTime(2026, 11)]!.complete(workspace);
      await tester.pumpAndSettle();
      expect(find.text('2026年12月'), findsOneWidget);
      expect(find.text('在籍社員 9名 ／ 当月明細 0件'), findsOneWidget);
      expect(find.text('在籍社員 9名 ／ 当月明細 6件'), findsNothing);
    },
  );

  testWidgets(
    'settings return refreshes once, only after the editor completes',
    (tester) async {
      final workspace = (await tester.runAsync(() => readRpc(payload())))!;
      final repository = _CachedRepository(workspace);
      final editor = Completer<void>();
      await tester.pumpWidget(
        MaterialApp(
          home: PayrollReviewPage(
            repository: repository,
            onOpenSettings: () => editor.future,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final entry = find.byKey(
        const ValueKey('payroll-individual-settings-entry'),
      );
      await tester.tap(entry);
      await tester.pump();
      await tester.tap(entry);
      await tester.pump();
      expect(repository.reads, 1);
      editor.complete();
      await tester.pumpAndSettle();
      expect(repository.reads, 2);
      expect(tester.takeException(), isNull);
    },
  );
}
