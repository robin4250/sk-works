import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:sk_works/features/expenses/expense_claim.dart';
import 'package:sk_works/features/expenses/expense_document_repository.dart';
import 'package:sk_works/features/expenses/expense_detail_pdf.dart';
import 'package:sk_works/features/payroll/payroll_pdf_service.dart';
import 'package:sk_works/features/payroll/payroll_statement_repository.dart';
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final fontPath=Platform.environment['SKO_PDF_FONT_PATH'];
  for(final includeNovember in [true,false]) {
    test('payroll expense PDF monthly filter november=$includeNovember',() async {
      final font=pw.Font.ttf(ByteData.sublistView(await File(fontPath!).readAsBytes()));
      ExpenseClaim claim(String id,DateTime day,String description)=>ExpenseClaim(
        id:id,companyId:'company',applicantId:'worker',applicantName:'合成社員',
        incurredOn:day,submittedAt:DateTime(2026,11,3),description:description,
        amountYen:1000,approval:ExpenseApproval.approved,
        allocation:ExpenseAllocation(ExpenseCategory.ownCompany));
      final claims=ExpenseClaims(companyId:'company',claims:[
        claim('october',DateTime(2026,10,31),'OCTOBER_ONLY'),
        if(includeNovember) claim('november',DateTime(2026,11,1),'NOVEMBER_ONLY'),
        claim('december',DateTime(2026,12,1),'DECEMBER_ONLY'),
        claim('previous-year',DateTime(2025,11,1),'PREVIOUS_YEAR_ONLY'),
      ]);
      final expenses=ExpenseDocumentDetails(kind:ExpenseDocument.payroll,
        documentId:'synthetic-payroll',subjectId:'worker',month:DateTime(2026,11),claims:claims);
      final statement=PayrollStatementRecord(id:'synthetic-payroll',companyName:'合成会社',workerName:'合成社員',
        periodStart:DateTime(2026,11,1),periodEnd:DateTime(2026,11,30),grossPay:300000,
        deductions:50000,netPay:250000,detail:{'基本給':300000,'pay_type':'monthly','company_seal_enabled':false});
      final bytes=await PayrollPdfService.buildPdf(statement,expenseDetails:expenses,regularFont:font,boldFont:font);
      final folder=Platform.environment['SKO_PDF_OUTPUT_DIR']??(await Directory.systemTemp.createTemp('expense-month-pdf-')).path;
      final file=File('$folder/payroll-expense-november-$includeNovember.pdf');await file.parent.create(recursive:true);await file.writeAsBytes(bytes);
      final result=await Process.run(Platform.environment['SKO_PDF_PYTHON']??'python3',['-c',
        'import sys\ntry:\n import fitz\n d=fitz.open(sys.argv[1]);print(len(d));print("".join(p.get_text() for p in d))\nexcept ImportError:\n from pypdf import PdfReader\n d=PdfReader(sys.argv[1]);print(len(d.pages));print("".join(p.extract_text() for p in d.pages))',file.path]);
      expect(result.exitCode,0,reason:result.stderr.toString());
      final text=result.stdout.toString();
      expect(text.split('\n').first,includeNovember?'2':'1');
      for(final absent in ['OCTOBER_ONLY','DECEMBER_ONLY','PREVIOUS_YEAR_ONLY']) {expect(text,isNot(contains(absent)));}
      expect(text.contains('NOVEMBER_ONLY'),includeNovember);
      expect(claims.entries.length,includeNovember?4:3);
      expect(text,contains('300,000'));expect(text,contains('250,000'));
    },skip:fontPath==null?'Requires PDF/font proof environment':false);
  }
}
