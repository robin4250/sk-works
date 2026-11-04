import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:sk_works/features/payroll/payroll_pdf_service.dart';
import 'package:sk_works/features/payroll/payroll_statement_repository.dart';
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final fontPath = Platform.environment['SKO_PDF_FONT_PATH'];
  for (final type in ['monthly', 'daily', 'hourly']) {
    test('$type PDF reallocation preserves 300000 gross and 250000 net', () async {
      final font = pw.Font.ttf(ByteData.sublistView(await File(fontPath!).readAsBytes()));
      final target = type == 'hourly' ? '有給支給額' : '役職手当';
      final detail = <String,dynamic>{
        '基本給':300000,'pay_type':type,'company_seal_enabled':false,
        'attendance_unit_evidence':{'contract_version':1,'items':[
          {'name':'基本給','section':'earning','category':'monthly','unit':'month','quantity':1,'rate_yen':300000,'amount_yen':300000}]},
        'position_transfer_snapshot':{'version':2,'enabled':true,'pay_type':type,
          'items':[{'name':target,'amount_yen':100000}]},
      };
      final before=jsonEncode(detail);
      final statement=PayrollStatementRecord(id:'synthetic-transfer-v2',companyName:'合成会社',
        workerName:'合成社員',periodStart:DateTime(2026,11,1),periodEnd:DateTime(2026,11,30),
        grossPay:300000,deductions:50000,netPay:250000,detail:detail);
      final bytes=await PayrollPdfService.buildPdf(statement,regularFont:font,boldFont:font);
      expect(jsonEncode(detail),before);
      final folder=Platform.environment['SKO_PDF_OUTPUT_DIR'] ?? (await Directory.systemTemp.createTemp('transfer-v2-pdf-')).path;
      final file=File('$folder/transfer-v2-$type.pdf');
      await file.parent.create(recursive:true);await file.writeAsBytes(bytes);
      final result=await Process.run(Platform.environment['SKO_PDF_PYTHON'] ?? 'python3',['-c',
        'import sys\ntry:\n import fitz\n print("".join(p.get_text() for p in fitz.open(sys.argv[1])))\nexcept ImportError:\n from pypdf import PdfReader\n print("".join(p.extract_text() for p in PdfReader(sys.argv[1]).pages))',file.path]);
      expect(result.exitCode,0,reason:result.stderr.toString());
      final text=result.stdout.toString();
      for(final value in [target,'200,000','100,000','300,000','250,000']) {expect(text,contains(value));}
      expect(text,isNot(contains('振替の設定・支給額を確認してください')));
      expect(text,contains('振替後の基本給'));
      expect(text,contains('基本給から振替'));
      expect(text.replaceAll(RegExp(r'\s+'),''),isNot(contains('300,000円×1月')));
    }, skip: fontPath == null ? 'Requires PDF/font proof environment' : false);
  }
}
