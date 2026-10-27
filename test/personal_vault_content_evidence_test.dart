import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:sk_works/features/personal_vault/own_payroll_archive_pdf.dart';
import 'package:sk_works/features/payroll/payroll_statement_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('own finalized payroll renderer omits foreign free text and attachments', () async {
    final source = PayrollStatementRecord(id:'synthetic-statement',
      companyName:'Fixture Company',workerName:'Only Owner',
      periodStart:DateTime(2026,9,1),periodEnd:DateTime(2026,9,30),
      grossPay:100000,deductions:10000,netPay:90000,
      workflowState:'finalized',revision:1,
      detail:{'基本給':100000,'所得税':10000,'出勤日数':5,
        'remarks':'OTHER_WORKER_PRIVATE_SENTINEL',
        'manager_notes':{'internal':'COMPANY_INTERNAL_SENTINEL'},
        'company_seal_snapshot':{'url':'https://invalid.invalid/SEAL_SECRET_SENTINEL'},
        'custom_earnings':<Object>[],'custom_deductions':<Object>[]});
    final before=jsonEncode(source.detail);
    final font=pw.Font.ttf(ByteData.sublistView(await File(
      'assets/fonts/company-seal/NotoSansJP-Bold.ttf').readAsBytes()));
    final bytes=await OwnPayrollArchivePdf.build(source:source,
      verifiedPersonId:'fixture-owner',snapshotPersonId:'fixture-owner',
      sourceCompanyId:'fixture-company',regularFont:font,boldFont:font);
    expect(jsonEncode(source.detail),before);
    final dir=await Directory.systemTemp.createTemp('sko-vault-content-');
    addTearDown(() async => dir.delete(recursive:true));
    final file=File('${dir.path}/fixture.pdf');await file.writeAsBytes(bytes);
    final extract=await Process.run('python3',['-c',r'''
import fitz,json,sys
p=fitz.open(sys.argv[1]); print(json.dumps({'text':' '.join(page.get_text() for page in p),'embedded':p.embfile_count(),'pages':len(p)},ensure_ascii=False))
''',file.path]);
    expect(extract.exitCode,0,reason:extract.stderr.toString());
    final out=jsonDecode(extract.stdout.toString()) as Map;
    expect(out['pages'],greaterThan(0));
    expect(out['embedded'],0);
    expect(out['text'],contains('Only Owner'));
    for(final secret in ['OTHER_WORKER_PRIVATE_SENTINEL','COMPANY_INTERNAL_SENTINEL','SEAL_SECRET_SENTINEL']) {
      expect(out['text'],isNot(contains(secret)));
    }
  });
}
