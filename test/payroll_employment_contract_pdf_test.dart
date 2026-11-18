import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:sk_works/features/expenses/expense_claim.dart';
import 'package:sk_works/features/expenses/expense_detail_pdf.dart';
import 'package:sk_works/features/expenses/expense_document_repository.dart';
import 'package:sk_works/features/payroll/payroll_pdf_service.dart';
import 'package:sk_works/features/payroll/payroll_statement_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final month = DateTime(2026, 11);
  PayrollStatementRecord statement({
    int revision = 3,
    String state = 'finalized',
  }) => PayrollStatementRecord(
    id: 'test-payroll',
    companyName: 'テスト会社',
    workerName: 'テスト従業員',
    periodStart: month,
    periodEnd: DateTime(2026, 11, 30),
    issuedAt: DateTime(2026, 12, 25),
    grossPay: 20000,
    deductions: 0,
    netPay: 20000,
    workflowState: state,
    revision: revision,
    detail: {'基本給': 20000, 'company_seal_enabled': false},
  );

  final contract = PayrollEmploymentContractPage(
    statementId: 'test-payroll',
    statementRevision: 3,
    imageBytes: base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADElEQVR4nGP4//8/AAX+Av4N70a4AAAAAElFTkSuQmCC',
    ),
  );

  test('only the matching finalized statement accepts the contract', () async {
    await expectLater(
      PayrollPdfService.buildPdf(
        statement(revision: 4),
        employmentContract: contract,
      ),
      throwsStateError,
    );
    await expectLater(
      PayrollPdfService.buildPdf(
        statement(state: 'draft'),
        employmentContract: contract,
      ),
      throwsStateError,
    );
  });

  test(
    'renders an optional second page and preserves the payroll-only export',
    () async {
      final font = pw.Font.ttf(
        ByteData.sublistView(
          await File(
            'assets/fonts/company-seal/NotoSansJP-Bold.ttf',
          ).readAsBytes(),
        ),
      );
      final expenses = ExpenseDocumentDetails(
        kind: ExpenseDocument.payroll,
        documentId: 'test-payroll',
        subjectId: 'test-worker',
        month: month,
        claims: ExpenseClaims(companyId: 'test-company', claims: const []),
      );
      final linkedContract = await PayrollEmploymentContractPage.fromDocument({
        'layout': 'a4_typeset',
        'workplace': '東京都墨田区の工事現場',
        'duties': '足場の組立・解体',
        'values': {
          'name': '給与PDF検証 従業員',
          'signedOn': '2026年11月9日',
          'period': '2026-11-09～2027-10-31',
        },
        'positions': {
          'name': [.21, .128],
          'signedOn': [.69, .106],
          'period': [.365, .224],
        },
        'issuer': {
          'name': '給与PDF検証 発行元（架空）',
          'representative_name': '検証 太郎',
          'postal_code': '000-0000',
          'address': '検証用住所',
          'phone': '00-0000-0000',
        },
      }, statementId: 'test-payroll', statementRevision: 3);
      for (final includeContract in [false, true]) {
        final bytes = await PayrollPdfService.buildPdf(
          statement(),
          expenseDetails: expenses,
          regularFont: font,
          boldFont: font,
          employmentContract: includeContract ? linkedContract : null,
        );
        final pageCount = RegExp(
          r'/Type\s*/Page\b',
        ).allMatches(latin1.decode(bytes)).length;
        expect(pageCount, includeContract ? 2 : 1);
        final output = Platform.environment['SKO_CONTRACT_PDF_TEST_DIR'];
        if (output != null && includeContract) {
          await File('$output/payroll-contract.pdf').writeAsBytes(bytes);
        }
      }
    },
  );
}
