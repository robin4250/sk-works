import 'package:sk_works/features/expenses/expense_claim.dart';

ExpenseClaim expenseFixture(
  String id, {
  String company = 'company',
  String applicant = 'worker-a',
  String name = '試験 太郎',
  ExpenseApproval status = ExpenseApproval.pending,
  ExpenseAllocation? allocation,
  String description = '現場への交通費',
  int amount = 1200,
}) => ExpenseClaim(
  id: id,
  companyId: company,
  applicantId: applicant,
  applicantName: name,
  incurredOn: DateTime(2026, 10, 1),
  submittedAt: DateTime.utc(2026, 10, 2),
  description: description,
  amountYen: amount,
  approval: status,
  allocation: allocation ?? ExpenseAllocation(ExpenseCategory.unallocated),
);
