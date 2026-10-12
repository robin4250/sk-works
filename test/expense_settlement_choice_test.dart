import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sk_works/features/expenses/expense_claim.dart';
import 'package:sk_works/features/expenses/expense_management_repository.dart';
import 'package:sk_works/features/expenses/expense_settlement_choice.dart';
import 'package:sk_works/features/expenses/expense_settlement_dialog.dart';

ExpenseClaim claim() => ExpenseClaim(id: 'claim', companyId: 'company', applicantId: 'worker',
  applicantName: '本人', incurredOn: DateTime(2026, 10, 1), submittedAt: DateTime.utc(2026, 10, 2),
  description: '交通費', amountYen: 1234, approval: ExpenseApproval.pending,
  allocation: ExpenseAllocation(ExpenseCategory.unallocated));

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('civil month and method reject malformed receipts and preserve old pending commands', () {
    final choice = ExpenseSettlementChoice.decode('payroll', '2026-10-01');
    expect(choice.month, DateTime.utc(2026, 10));
    for (final month in ['2026-13-01', '2026-10-02', '2026-1-01']) {
      expect(() => ExpenseSettlementChoice.decode('cash', month), throwsA(isA<StateError>()));
    }
    final old = ExpenseReviewCommand.create('actor', 'company', 'claim', 1, 'approve', null);
    expect(ExpenseReviewCommand.decode(old.encoded).encoded, old.encoded);
    expect(ExpenseReviewCommand.decode(old.encoded).settlement, isNull);
  });
  test('explicit approval sends method/month with the fixed command and validates the receipt', () async {
    String? name;
    Map<String, dynamic>? sent;
    final repository = ExpenseManagementRepository(actor: () => 'actor', rpc: (n, p) async {
      name = n; sent = Map<String, dynamic>.from(p);
      return {'id': 'claim', 'company_id': 'company', 'revision': 2,
        'settlement_method': 'payroll', 'settlement_month': '2026-11-01'};
    });
    final c = ExpenseReviewCommand.create('actor', 'company', 'claim', 1, 'approve', null,
      settlement: ExpenseSettlementChoice(ExpenseSettlementMethod.payroll, DateTime.utc(2026, 11)));
    await repository.execute(c);
    expect(name, 'expense_approve_with_settlement');
    expect(sent, {'p_command_id': c.id, 'p_claim': 'claim', 'p_revision': 1,
      'p_method': 'payroll', 'p_settlement_month': '2026-11-01'});
    expect(await repository.pending('company'), isNull);
  });
  test('a mismatched settlement receipt retains the exact pending command', () async {
    final repository = ExpenseManagementRepository(actor: () => 'actor', rpc: (n, p) async => {
      'id': 'claim', 'company_id': 'company', 'revision': 2,
      'settlement_method': 'cash', 'settlement_month': '2026-11-01'});
    final c = ExpenseReviewCommand.create('actor', 'company', 'claim', 1, 'approve', null,
      settlement: ExpenseSettlementChoice(ExpenseSettlementMethod.payroll, DateTime.utc(2026, 11)));
    await expectLater(repository.execute(c), throwsA(isA<StateError>()));
    expect((await repository.pending('company'))!.encoded, c.encoded);
  });
  testWidgets('320px and enlarged text require explicit method/month and cancel without approval', (tester) async {
    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    ExpenseSettlementChoice? result;
    await tester.pumpWidget(MaterialApp(builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(1.3)), child: child!),
      home: Builder(builder: (context) => Scaffold(body: TextButton(onPressed: () async {
        result = await showDialog<ExpenseSettlementChoice>(context: context,
          builder: (_) => ExpenseSettlementDialog(claim: claim()));
      }, child: const Text('開く'))))));
    await tester.tap(find.text('開く')); await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, '承認して保存')).onPressed, isNull);
    await tester.tap(find.text('給料精算')); await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, '承認して保存')).onPressed, isNull);
    await tester.ensureVisible(find.byType(DropdownButtonFormField<int>).first);
    await tester.tap(find.byType(DropdownButtonFormField<int>).first); await tester.pumpAndSettle();
    await tester.tap(find.text('2026年').last); await tester.pumpAndSettle();
    await tester.ensureVisible(find.byType(DropdownButtonFormField<int>).last);
    await tester.tap(find.byType(DropdownButtonFormField<int>).last); await tester.pumpAndSettle();
    await tester.tap(find.text('2月').last); await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('承認して保存')); await tester.pumpAndSettle();
    expect(result!.method, ExpenseSettlementMethod.payroll); expect(result!.monthKey, '2026-02-01');
    result = null;
    await tester.tap(find.text('開く')); await tester.pumpAndSettle();
    await tester.tap(find.text('戻る')); await tester.pumpAndSettle();
    expect(result, isNull); expect(tester.takeException(), isNull);
  });
}
