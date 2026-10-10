import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/expenses/expense_claim.dart';
import 'package:sk_works/features/expenses/expense_personal_page.dart';
import 'package:sk_works/features/expenses/expense_submission_repository.dart';

class _Access implements ExpenseSubmissionAccess {
  @override
  String? actor = 'actor';
  ExpenseSubmission? draft;
  Completer<void>? response;
  int writes = 0;
  final ids = <String>[];
  final months = <DateTime>[];
  @override
  Future<List<Map<String, dynamic>>> scopes() async => [
    {
      'company_id': 'company',
      'company_name': 'Company',
      'worker_id': 'worker',
      'worker_name': '本人',
    },
  ];
  @override
  Future<List<ExpenseClaim>> history(
    String company,
    String worker,
    DateTime month,
  ) async {
    months.add(month);
    return [
      ExpenseClaim(
        id: 'old',
        companyId: company,
        applicantId: worker,
        applicantName: '本人',
        incurredOn: DateTime(2026, 9, 30),
        submittedAt: DateTime(2026, 10, 1),
        description: '却下された交通費',
        amountYen: 500,
        approval: ExpenseApproval.rejected,
        allocation: ExpenseAllocation(ExpenseCategory.unallocated),
      ),
    ];
  }

  @override
  Future<ExpenseSubmission?> pending(String company, String worker) async =>
      draft;
  @override
  Future<void> submit(ExpenseSubmission input) async {
    writes++;
    draft = input;
    ids.add(input.id);
    if (response != null) await response!.future;
    throw StateError('response lost');
  }
}

Future<void> _open(WidgetTester tester, _Access access) async {
  await tester.binding.setSurfaceSize(const Size(650, 1400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(home: ExpensePersonalPage(access: access)),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('actor change during send hides previous personal data', (
    tester,
  ) async {
    final access = _Access()..response = Completer<void>();
    await _open(tester, access);
    await tester.enterText(find.byType(TextField).at(0), 'expense');
    await tester.enterText(find.byType(TextField).at(1), '100');
    await tester.tap(find.text('申請する'));
    await tester.pump();
    access.actor = 'different';
    access.response!.complete();
    await tester.pumpAndSettle();
    expect(find.textContaining('ログイン情報が変わりました'), findsOneWidget);
    expect(find.text('却下された交通費'), findsNothing);
    expect(access.writes, 1);
  });
  test('stored draft rejects corrupt date and amount', () {
    expect(() => ExpenseSubmission.decode('{}'), throwsStateError);
    final draft = ExpenseSubmission.create(
      'actor',
      'company',
      'worker',
      DateTime(2026, 9, 30),
      '電車',
      '100',
    );
    expect(ExpenseSubmission.decode(draft.encoded).encoded, draft.encoded);
    expect(
      () => ExpenseSubmission.decode(
        draft.encoded.replaceFirst('2026-09-30', '2026-02-31'),
      ),
      throwsStateError,
    );
  });

  testWidgets(
    'pending failure retries same identity and disables double send',
    (tester) async {
      final access = _Access()..response = Completer<void>();
      await _open(tester, access);
      await tester.enterText(find.byType(TextField).at(0), '電車代');
      await tester.enterText(find.byType(TextField).at(1), '1234');
      await tester.tap(find.text('申請する'));
      await tester.pump();
      expect(access.writes, 1);
      expect(find.text('同じ申請を再確認'), findsOneWidget);
      await tester.tap(find.text('同じ申請を再確認'));
      await tester.pump();
      expect(access.writes, 1);
      access.response!.complete();
      await tester.pumpAndSettle();
      expect(find.textContaining('保存結果を確認できません'), findsOneWidget);
      access.response = null;
      await tester.tap(find.text('同じ申請を再確認'));
      await tester.pumpAndSettle();
      expect(access.writes, 2);
      expect(access.ids.toSet().length, 1);
      expect(find.byType(TextField), findsNothing);
    },
  );
  testWidgets('calendar input and rejected personal history remain visible', (
    tester,
  ) async {
    final access = _Access();
    await _open(tester, access);
    expect(find.text('却下された交通費'), findsOneWidget);
    await tester.tap(find.textContaining('利用日　'));
    await tester.pumpAndSettle();
    expect(find.byType(DatePickerDialog), findsOneWidget);
    expect(access.writes, 0);
  });
  test(
    'month follows incurred civil date, not later submission or timezone',
    () {
      final claim = ExpenseClaim(
        id: 'c',
        companyId: 'company',
        applicantId: 'worker',
        applicantName: '本人',
        incurredOn: DateTime(2026, 9, 30, 23),
        submittedAt: DateTime.utc(2026, 10, 1),
        description: 'expense',
        amountYen: 1,
        approval: ExpenseApproval.pending,
        allocation: ExpenseAllocation(ExpenseCategory.unallocated),
      );
      final claims = ExpenseClaims(companyId: 'company', claims: [claim]);
      expect(claims.forMonth(DateTime(2026, 9)).entries.length, 1);
      expect(claims.forMonth(DateTime(2026, 10)).entries, isEmpty);
    },
  );
}
