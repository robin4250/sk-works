import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:sk_works/features/expenses/expense_claim.dart';
import 'package:sk_works/features/expenses/expense_detail_pdf.dart';
import 'expense_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'three independent expense supplements start on page two and span without dropping rows',
    () async {
      final data = await rootBundle.load(
        'assets/fonts/company-seal/NotoSansJP-Bold.ttf',
      );
      final output = Directory('build/expense-proof')
        ..createSync(recursive: true);
      final claims = ExpenseClaims(
        companyId: 'company',
        claims: [
          for (var i = 0; i < 85; i++)
            expenseFixture(
              'EXP-${i.toString().padLeft(3, '0')}',
              description: i == 0 ? '長文の経費説明です。\n' * 60 : '電車代・資材運搬 ${i + 1}',
              status: ExpenseApproval.values[i % 3],
              allocation: ExpenseAllocation(
                i % 2 == 0
                    ? ExpenseCategory.customer
                    : ExpenseCategory.subcontractor,
                counterpartyId: 'partner',
                counterpartyName: '試験取引会社',
              ),
            ),
          expenseFixture(
            'OTHER-WORKER',
            applicant: 'other',
            name: '他の社員',
            description: '本人明細には載せない',
          ),
        ],
      );
      for (final kind in ExpenseDocument.values) {
        final font = pw.Font.ttf(data);
        final document = pw.Document(theme: pw.ThemeData.withFont(base: font));
        document.addPage(
          pw.Page(build: (_) => pw.Text('既存１ページ・金額変更なし 10000円')),
        );
        ExpenseDetailPdf.append(
          document,
          claims: claims,
          kind: kind,
          subjectId: kind == ExpenseDocument.payroll ? 'worker-a' : 'partner',
          regularFont: font,
          boldFont: font,
        );
        final bytes = await document.save();
        expect(document.document.pdfPageList.pages.length, greaterThan(2));
        expect(bytes.length, greaterThan(1000));
        File('${output.path}/${kind.name}.pdf').writeAsBytesSync(bytes);
      }
    },
  );
  test('no matching external expenses adds no unwanted second page', () async {
    final font = pw.Font.helvetica();
    final document = pw.Document()
      ..addPage(pw.Page(build: (_) => pw.Text('Original')));
    ExpenseDetailPdf.append(
      document,
      claims: ExpenseClaims(companyId: 'company', claims: []),
      kind: ExpenseDocument.invoice,
      subjectId: 'absent',
      regularFont: font,
      boldFont: font,
    );
    await document.save();
    expect(document.document.pdfPageList.pages, hasLength(1));
  });
}
