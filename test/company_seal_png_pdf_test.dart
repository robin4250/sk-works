import 'dart:io';
import 'dart:convert';
import 'package:sk_works/domain/company_seal_design.dart';
import 'package:sk_works/features/shared/company_seal_pdf.dart';
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final fontPath =
      Platform.environment['SKO_PDF_FONT_PATH'] ??
      'assets/fonts/company-seal/NotoSansJP-Bold.ttf';
  test(
    'PNG metadata and renderer reject another company or changed name',
    () async {
      for (final style in CompanySealDesign.designs.keys) {
        final valid = {
          'version': 1,
          'style': style,
          'name': CompanySealDesign.companyName,
          'company_id': CompanySealDesign.companyId,
        };
        expect(CompanySealSnapshot.fromJson(valid).style, style);
        for (final invalid in [
          {...valid, 'company_id': 'other'},
          {...valid, 'name': '別会社'},
          {...valid}..remove('company_id'),
        ]) {
          expect(() => CompanySealSnapshot.fromJson(invalid), throwsStateError);
        }
        final font = await CompanySealPdf.loadStyleFont(style);
        expect(
          () => CompanySealPdf.build(
            CompanySealDesign.companyName,
            style: style,
            font: font,
            companyId: 'other',
          ),
          throwsStateError,
        );
        expect(
          () => CompanySealPdf.build(
            '別会社',
            style: style,
            font: font,
            companyId: CompanySealDesign.companyId,
          ),
          throwsStateError,
        );
      }
    },
  );
  test(
    'missing historical metadata remains legacy; corrupt metadata is rejected',
    () {
      expect(CompanySealSnapshot.fromJson(null).style, 'legacy');
      expect(CompanySealSnapshot.fromJson(null).registeredName('旧会社'), '旧会社');
      for (final value in [
        {'version': 2, 'style': 'aoyagi_reisho', 'name': '株式会社テスト'},
        {'version': 1, 'style': 'tensho', 'name': '株式会社テスト'},
        {'version': 1, 'style': 'aoyagi_reisho', 'name': ''},
      ]) {
        expect(() => CompanySealSnapshot.fromJson(value), throwsStateError);
      }
    },
  );

  test(
    'all three PNG styles render in all three actual reports with transparency',
    () async {
      final fontData = ByteData.sublistView(File(fontPath).readAsBytesSync());
      final output = Directory('build/company-seal-proof')
        ..createSync(recursive: true);
      for (final style in CompanySealDesign.designs.keys) {
        const name = CompanySealDesign.companyName;
        final sealJson = {
          'version': 1,
          'style': style,
          'name': name,
          'company_id': CompanySealDesign.companyId,
        };
        final seal = CompanySealSnapshot.fromJson(sealJson);
        final suffix = style;
        final invoiceFont = pw.Font.ttf(fontData);
        final invoice = InvoiceCalculationResult(
          customerId: '取引会社',
          billingPeriod: '2026年10月',
          detailMode: InvoiceDetailMode.consolidatedOnly,
          siteCalculations: const [],
          taxRateBps: 1000,
          subtotalYenOverride: 12000,
          companySealSnapshot: seal,
        );
        final invoiceBytes = await InvoicePdfService.buildPdf(
          [invoice],
          settings: const InvoiceSettingsData(
            companyName: '株式会社変更後',
            taxRate: 10,
            welfareRate: 0,
            templateTitle: '請求書',
            footerNote: '',
            bankName: '',
            bankBranch: '',
            bankAccountType: '',
            bankAccountNumber: '',
            bankAccountHolder: '',
          ),
          regularFont: invoiceFont,
          boldFont: invoiceFont,
        );
        File(
          '${output.path}/invoice_png_$suffix.pdf',
        ).writeAsBytesSync(invoiceBytes);
        final payrollFont = pw.Font.ttf(fontData);
        final payroll = PayrollStatementRecord(
          id: 'saved-payroll',
          companyName: '株式会社変更後',
          workerName: '試験 太郎',
          periodStart: DateTime(2026, 10, 1),
          periodEnd: DateTime(2026, 10, 31),
          grossPay: 12000,
          deductions: 0,
          netPay: 12000,
          detail: {
            '基本給': 12000,
            'pay_type': 'daily',
            'company_seal_enabled': true,
            'company_seal_snapshot': sealJson,
          },
        );
        final payrollBytes = await PayrollPdfService.buildPdf(
          payroll,
          regularFont: payrollFont,
          boldFont: payrollFont,
        );
        File(
          '${output.path}/payroll_png_$suffix.pdf',
        ).writeAsBytesSync(payrollBytes);
        final paymentFont = pw.Font.ttf(fontData);
        final payment = PaymentCertificateRecord(
          id: 'saved-payment',
          partnerCompanyName: '協力会社',
          payerCompanyName: '株式会社変更後',
          periodStart: DateTime(2026, 10, 1),
          periodEnd: DateTime(2026, 10, 31),
          grossAmount: 12000,
          deductions: 0,
          netAmount: 12000,
          status: 'finalized',
          revision: 1,
          companySealSnapshot: seal,
          lines: const [
            PaymentCertificateLine(
              siteName: '試験現場',
              workContent: '請け負い',
              quantityLabel: '一式',
              unitPriceYen: 12000,
              amountYen: 12000,
            ),
          ],
        );
        final paymentBytes = await PaymentCertificatePdfService.buildPdf(
          payment,
          regularFont: paymentFont,
          boldFont: paymentFont,
        );
        File(
          '${output.path}/payment_png_$suffix.pdf',
        ).writeAsBytesSync(paymentBytes);
        payroll.detail['company_seal_enabled'] = false;
        final offFont = pw.Font.ttf(fontData);
        final off = await PayrollPdfService.buildPdf(
          payroll,
          regularFont: offFont,
          boldFont: offFont,
        );
        expect(
          latin1.decode(off),
          isNot(contains('/SMask')),
          reason: 'OFF must omit PNG',
        );
        expect(seal.registeredName('株式会社変更後'), name);
        for (final bytes in [invoiceBytes, payrollBytes, paymentBytes]) {
          expect(
            latin1.decode(bytes),
            contains('/SMask'),
            reason: 'PNG transparency must survive PDF embedding',
          );
        }
      }
    },
  );
}
