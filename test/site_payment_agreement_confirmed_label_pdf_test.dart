import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:sk_works/features/payroll/payment_certificate_pdf_service.dart';
import 'package:sk_works/features/payroll/payment_certificate_repository.dart';
import 'package:sk_works/features/payroll/site_payment_agreement_document.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final fontPath = Platform.environment['SKO_PDF_FONT_PATH'];
  test('confirmed agreement origins label v1 v2 v3 while monthly states remain unchanged', () async {
    final output = Directory('build/agreement-label-proof')..createSync(recursive: true);
    final jsonFile = File('${output.path}/snapshots.json');
    final module = Platform.environment['SKO_PAYMENT_PGLITE_PATH'] ??
        '${Platform.environment['RUNNER_TEMP']}/sko-sql-runtime/'
            'node_modules/@electric-sql/pglite/dist/index.js';
    final result = await Process.run('node', [
      'tool/verify_site_payment_agreement.mjs',module,'--seal-snapshots',
    ], environment: {'SKO_SITE_PAYMENT_ALL_VERSIONS_OUTPUT_JSON':jsonFile.path});
    expect(result.exitCode,0,reason:result.stderr.toString());
    final snapshots = jsonDecode(jsonFile.readAsStringSync()) as List;
    expect(snapshots,hasLength(4));
    for (var i=0;i<snapshots.length;i++) {
      final record = SitePaymentAgreementDocument.fromSnapshot(
          Map<String,dynamic>.from(snapshots[i] as Map));
      expect(record.isAgreementSnapshot,true);
      expect(record.status,'draft');
      final font=pw.Font.ttf(ByteData.sublistView(File(fontPath!).readAsBytesSync()));
      final bytes=await PaymentCertificatePdfService.buildPdf(record,
          regularFont:font,boldFont:font);
      File('${output.path}/agreement_v${i<2?i+1:3}_${i==3?'long':'short'}.pdf')
          .writeAsBytesSync(bytes);
    }
    for (final state in ['preview','draft','finalized']) {
      final monthly=PaymentCertificateRecord(id:'monthly',partnerCompanyName:'協力会社',
        periodStart:DateTime(2026,10,1),periodEnd:DateTime(2026,10,31),
        grossAmount:0,deductions:0,netAmount:0,status:state,revision:1,
        payerCompanySealEnabled:false);
      expect(monthly.isAgreementSnapshot,false);
      final font=pw.Font.ttf(ByteData.sublistView(File(fontPath!).readAsBytesSync()));
      final bytes=await PaymentCertificatePdfService.buildPdf(monthly,
          regularFont:font,boldFont:font);
      File('${output.path}/monthly_$state.pdf').writeAsBytesSync(bytes);
    }
  },skip:fontPath==null?'Prepare the adopted regular-font fixture first.':false);
}
