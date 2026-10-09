import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:sk_works/domain/company_seal_snapshot.dart';
import 'package:sk_works/domain/invoice_engine.dart';
import 'package:sk_works/features/invoices/invoice_pdf_service.dart';
import 'package:sk_works/features/invoices/invoice_settings_repository.dart';
import 'package:sk_works/features/payroll/payment_certificate_pdf_service.dart';
import 'package:sk_works/features/payroll/payment_certificate_repository.dart';
import 'package:sk_works/features/payroll/payroll_pdf_service.dart';
import 'package:sk_works/features/payroll/payroll_statement_repository.dart';
import 'package:sk_works/features/payroll/site_payment_agreement_document.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final fontPath = Platform.environment['SKO_PDF_FONT_PATH'];
  test('missing historical metadata remains legacy; corrupt metadata is rejected', () {
    expect(CompanySealSnapshot.fromJson(null).style, 'legacy');
    expect(CompanySealSnapshot.fromJson(null).registeredName('旧会社'), '旧会社');
    for (final value in [
      {'version': 2, 'style': 'aoyagi_reisho', 'name': '株式会社テスト'},
      {'version': 1, 'style': 'tensho', 'name': '株式会社テスト'},
      {'version': 1, 'style': 'aoyagi_reisho', 'name': ''},
    ]) {
      expect(() => CompanySealSnapshot.fromJson(value), throwsStateError);
    }
  });

  test('three production PDF generators use the saved genuine seal and registered name', () async {
    final fontData = ByteData.sublistView(File(fontPath!).readAsBytesSync());
    final output = Directory('build/company-seal-proof')..createSync(recursive: true);
    for (final name in ['株式会社テスト建設', '株式会社長い会社名建設工業']) {
      final sealJson = {'version': 1, 'style': 'aoyagi_reisho', 'name': name};
      final seal = CompanySealSnapshot.fromJson(sealJson);
      final suffix = name == '株式会社テスト建設' ? 'short' : 'long';
      final invoiceFont = pw.Font.ttf(fontData);
      final invoice = InvoiceCalculationResult(
        customerId: '取引会社', billingPeriod: '2026年10月',
        detailMode: InvoiceDetailMode.consolidatedOnly, siteCalculations: const [],
        taxRateBps: 1000, subtotalYenOverride: 12000,
        companySealSnapshot: seal,
      );
      final invoiceBytes = await InvoicePdfService.buildPdf([invoice],
        settings: const InvoiceSettingsData(companyName: '株式会社変更後',
          taxRate: 10, welfareRate: 0, templateTitle: '請求書', footerNote: '',
          bankName: '', bankBranch: '', bankAccountType: '',
          bankAccountNumber: '', bankAccountHolder: ''),
        regularFont: invoiceFont, boldFont: invoiceFont,
      );
      File('${output.path}/invoice_reisho_$suffix.pdf').writeAsBytesSync(invoiceBytes);
      final payrollFont = pw.Font.ttf(fontData);
      final payroll = PayrollStatementRecord(id: 'saved-payroll',
        companyName: '株式会社変更後', workerName: '試験 太郎',
        periodStart: DateTime(2026,10,1), periodEnd: DateTime(2026,10,31),
        grossPay: 12000, deductions: 0, netPay: 12000,
        detail: {'基本給':12000, 'pay_type':'daily', 'company_seal_enabled':true,
          'company_seal_snapshot':sealJson});
      final payrollBytes = await PayrollPdfService.buildPdf(payroll,
        regularFont: payrollFont, boldFont: payrollFont);
      File('${output.path}/payroll_reisho_$suffix.pdf').writeAsBytesSync(payrollBytes);
      final paymentFont = pw.Font.ttf(fontData);
      final payment = PaymentCertificateRecord(id: 'saved-payment',
        partnerCompanyName: '協力会社', payerCompanyName: '株式会社変更後',
        periodStart: DateTime(2026,10,1), periodEnd: DateTime(2026,10,31),
        grossAmount: 12000, deductions: 0, netAmount: 12000,
        status: 'finalized', revision: 1, companySealSnapshot: seal,
        lines: const [PaymentCertificateLine(siteName: '試験現場',
          workContent:'請け負い', quantityLabel:'一式', unitPriceYen:12000,
          amountYen:12000)]);
      final paymentBytes = await PaymentCertificatePdfService.buildPdf(payment,
        regularFont: paymentFont, boldFont: paymentFont);
      File('${output.path}/payment_reisho_$suffix.pdf').writeAsBytesSync(paymentBytes);
      expect(seal.registeredName('株式会社変更後'), name);
    }
  }, skip: fontPath == null ? 'Prepare the adopted regular-font fixture first.' : false);
  test('mutually confirmed v3 server snapshots generate genuine short and long agreement seals', () async {
    final output = Directory('build/company-seal-proof')..createSync(recursive: true);
    final jsonFile = File('${output.path}/agreement_reisho_snapshots.json');
    final module = Platform.environment['SKO_PAYMENT_PGLITE_PATH'] ??
        '${Platform.environment['RUNNER_TEMP']}/sko-sql-runtime/'
            'node_modules/@electric-sql/pglite/dist/index.js';
    final result = await Process.run('node', [
      'tool/verify_site_payment_agreement.mjs', module, '--seal-snapshots',
    ], environment: {'SKO_SITE_PAYMENT_SEAL_OUTPUT_JSON':jsonFile.path});
    expect(result.exitCode, 0, reason: result.stderr.toString());
    final snapshots = jsonDecode(jsonFile.readAsStringSync()) as List;
    expect(snapshots, hasLength(2));
    for (var i = 0; i < snapshots.length; i++) {
      final snapshot = Map<String,dynamic>.from(snapshots[i] as Map);
      expect(snapshot['snapshot_version'], 3);
      final record = SitePaymentAgreementDocument.fromSnapshot(snapshot);
      expect(record.companySealSnapshot.style, 'aoyagi_reisho');
      expect(record.companySealSnapshot.name, record.payerCompanyName);
      final font = pw.Font.ttf(ByteData.sublistView(File(fontPath!).readAsBytesSync()));
      final bytes = await PaymentCertificatePdfService.buildPdf(record,
          regularFont:font, boldFont:font);
      final suffix = i == 0 ? 'short' : 'long';
      File('${output.path}/agreement_reisho_$suffix.pdf').writeAsBytesSync(bytes);
    }
  }, skip: fontPath == null ? 'Prepare the adopted regular-font fixture first.' : false);
}
