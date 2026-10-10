import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sk_works/features/expenses/expense_management_repository.dart';
import 'package:sk_works/features/expenses/expense_management_page.dart';

Map<String, dynamic> row({
  String status = 'pending',
  String allocation = 'unallocated',
  int revision = 1,
}) => {
  'id': 'claim',
  'company_id': 'company',
  'applicant_id': 'worker',
  'applicant_name': '社員A',
  'created_by': 'applicant',
  'incurred_on': '2026-10-01',
  'submitted_at': '2026-11-01T00:00:00Z',
  'description': '交通費',
  'amount_yen': 100,
  'approval': status,
  'allocation': allocation,
  'counterparty_id': null,
  'counterparty_name': null,
  'revision': revision,
};
ExpenseReviewWorkspace workspace({
  String actor = 'reviewer',
  String status = 'pending',
  String allocation = 'unallocated',
  int revision = 1,
}) => ExpenseReviewWorkspace(
  {
    'company_id': 'company',
    'can_review': true,
    'can_configure': true,
    'settings_revision': 1,
    'approver_ids': ['reviewer', 'applicant'],
    'candidates': [
      {'user_id': 'reviewer', 'name': '承認者'},
      {'user_id': 'applicant', 'name': '社員A'},
    ],
    'claims': [row(status: status, allocation: allocation, revision: revision)],
    'destinations': [
      {'category': 'ownCompany', 'id': null, 'name': null},
    ],
  },
  'company',
  DateTime(2026, 10),
);

class Access implements ExpenseManagementAccess {
  @override
  String? actor = 'reviewer';
  ExpenseReviewCommand? command;
  ExpenseReviewWorkspace data = workspace();
  Completer<void>? response;
  bool fail = false;
  int calls = 0;
  final ids = <String>[];
  @override
  Future<List<Map<String, dynamic>>> companies() async => [
    {'company_id': 'company', 'company_name': '会社'},
  ];
  @override
  Future<ExpenseReviewWorkspace> load(String company, DateTime month) async =>
      data;
  @override
  Future<ExpenseReviewCommand?> pending(String company) async => command;
  @override
  Future<void> execute(ExpenseReviewCommand c) async {
    calls++;
    ids.add(c.id);
    command = c;
    if (response != null) await response!.future;
    if (fail) throw StateError('lost');
    data = workspace(
      status: c.action == 'reject' ? 'rejected' : 'approved',
      allocation: c.action == 'reject' ? 'unallocated' : 'ownCompany',
      revision: 2,
    );
    command = null;
  }

  @override
  Future<void> configure(
    String company,
    List<String> users,
    int revision,
  ) async {}
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test(
    'lost response persists identical command through repository restart',
    () async {
      final sent = <Map<String, dynamic>>[];
      var fail = true;
      Future<dynamic> rpc(String n, Map<String, dynamic> p) async {
        sent.add(Map.from(p));
        if (fail) throw StateError('network');
        return row(status: 'approved', allocation: 'ownCompany', revision: 2);
      }

      final c = ExpenseReviewCommand.create(
        'reviewer',
        'company',
        'claim',
        1,
        'approve',
        null,
      );
      final repository = ExpenseManagementRepository(
        actor: () => 'reviewer',
        rpc: rpc,
      );
      await expectLater(repository.execute(c), throwsStateError);
      final restarted = ExpenseManagementRepository(
        actor: () => 'reviewer',
        rpc: rpc,
      );
      final restored = await restarted.pending('company');
      expect(restored!.encoded, c.encoded);
      final different = ExpenseReviewCommand.create(
        'reviewer',
        'company',
        'claim',
        1,
        'reject',
        null,
      );
      await expectLater(restarted.execute(different), throwsStateError);
      expect(sent.length, 1);
      fail = false;
      await restarted.execute(restored);
      expect(sent[0], sent[1]);
      expect(await restarted.pending('company'), isNull);
    },
  );
  test(
    'foreign response remains pending, stale SQL revision releases for reload',
    () async {
      var stale = false;
      final r = ExpenseManagementRepository(
        actor: () => 'reviewer',
        rpc: (n, p) async {
          if (stale) {
            throw const PostgrestException(message: 'reload', code: '40001');
          }
          return {...row(), 'company_id': 'other'};
        },
      );
      final c = ExpenseReviewCommand.create(
        'reviewer',
        'company',
        'claim',
        1,
        'approve',
        null,
      );
      await expectLater(r.execute(c), throwsStateError);
      expect(await r.pending('company'), isNotNull);
      stale = true;
      await expectLater(r.execute(c), throwsA(isA<PostgrestException>()));
      expect(await r.pending('company'), isNull);
    },
  );
  test(
    'workspace refuses another month and company; rejects self decision with several approvers',
    () {
      final d = workspace();
      expect(d.canDecide(d.claims.entries.single, 'applicant'), false);
      expect(d.canDecide(d.claims.entries.single, 'reviewer'), true);
      expect(
        () => ExpenseReviewWorkspace(
          {'company_id': 'other'},
          'company',
          DateTime(2026, 10),
        ),
        throwsStateError,
      );
    },
  );
  testWidgets(
    'approve refreshes authoritative own-company status; reject remains visible',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(650, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final access = Access();
      await tester.pumpWidget(
        MaterialApp(home: ExpenseManagementPage(access: access)),
      );
      await tester.pumpAndSettle();
      expect(find.text('交通費'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, '承認'));
      await tester.pumpAndSettle();
      expect(find.text('承認済み / 自社'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, '却下'));
      await tester.pumpAndSettle();
      expect(find.textContaining('却下 /'), findsOneWidget);
      expect(access.calls, 2);
    },
  );
  testWidgets(
    'uncertain response disables other changes and retries original command',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(650, 1100));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final access = Access()
        ..fail = true
        ..response = Completer<void>();
      await tester.pumpWidget(
        MaterialApp(home: ExpenseManagementPage(access: access)),
      );
      await tester.pumpAndSettle();
      final button = tester.widget<TextButton>(
        find.widgetWithText(TextButton, '承認'),
      );
      button.onPressed!();
      button.onPressed!();
      await tester.pump();
      expect(access.calls, 1);
      access.response!.complete();
      await tester.pumpAndSettle();
      expect(find.text('同じ操作を再確認'), findsOneWidget);
      expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, '却下'))
            .onPressed,
        isNull,
      );
      access.response = null;
      access.fail = false;
      await tester.tap(find.text('同じ操作を再確認'));
      await tester.pumpAndSettle();
      expect(access.ids[0], access.ids[1]);
    },
  );
  testWidgets('actor switch hides all-company data on operation completion', (
    tester,
  ) async {
    final access = Access()..response = Completer<void>();
    await tester.pumpWidget(
      MaterialApp(home: ExpenseManagementPage(access: access)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, '承認'));
    await tester.pump();
    access.actor = 'other';
    access.response!.complete();
    await tester.pumpAndSettle();
    expect(find.text('交通費'), findsNothing);
    expect(find.textContaining('ログイン情報が変わりました'), findsOneWidget);
  });
  testWidgets('320 pixel management view has no horizontal overflow', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(home: ExpenseManagementPage(access: Access())),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
