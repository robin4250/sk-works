import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sk_works/domain/company_seal_snapshot.dart';
import 'package:sk_works/domain/invoice_engine.dart';
import 'package:sk_works/features/invoices/invoice_settings_repository.dart';
import 'package:sk_works/features/invoices/invoice_pdf_service.dart';
import 'package:sk_works/features/payroll/payment_certificate_repository.dart';
import 'package:sk_works/features/payroll/payment_certificate_pdf_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('document hydration uses current company names, ignoring old device name and preserving saved issuer', () async {
    SharedPreferences.setMockInitialValues({
      'settings_company_name': '旧端末だけの会社名',
    });
    var companyName = '株式会社青空工業';
    final requests = <String>[];
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      await request.drain<void>();
      requests.add(request.uri.path);
      expect(request.uri.path, '/rest/v1/rpc/invoice_document_settings');
      request.response.headers.contentType = ContentType.json;
      // Same RPC response contract as invoice_document_settings: company_name
      // is the current companies.name; no device preference enters this API.
      request.response.write(
        jsonEncode({
          'company_name': companyName,
          'company_seal_enabled': false,
          'tax_rate': 10,
        }),
      );
      await request.response.close();
    });
    final client = SupabaseClient(
      'http://127.0.0.1:${server.port}',
      'synthetic-anon-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    addTearDown(() async {
      await client.dispose();
      await server.close(force: true);
    });
    final repository = InvoiceSettingsRepository.forTesting(client);
    final fontPath = Platform.environment['SKO_PDF_FONT_PATH'];
    final output = Directory(
      Platform.environment['SKO_PDF_OUTPUT_DIR'] ??
          Directory.systemTemp.createTempSync('sko-name-authority-').path,
    )..createSync(recursive: true);
    final font = fontPath == null
        ? null
        : pw.Font.ttf(ByteData.sublistView(await File(fontPath).readAsBytes()));
    Future<String> text(Uint8List bytes, String name) async {
      final file = File('${output.path}/$name.pdf')..writeAsBytesSync(bytes);
      final result = await Process.run('python', [
        '-c',
        'import fitz,sys; d=fitz.open(sys.argv[1]); print("".join(p.get_text() for p in d))',
        file.path,
      ]);
      expect(result.exitCode, 0, reason: result.stderr.toString());
      return result.stdout.toString().replaceAll(RegExp(r'\s+'), '');
    }

    InvoiceCalculationResult invoice({
      CompanySealSnapshot snapshot = CompanySealSnapshot.legacy,
    }) => InvoiceCalculationResult(
      invoiceId: 'name-fixture',
      customerId: '検証用取引先',
      billingPeriod: '2026年10月',
      detailMode: InvoiceDetailMode.siteBreakdownOnInvoice,
      invoiceNumber: '202610-001',
      issueDate: DateTime(2026, 10, 31),
      periodStart: DateTime(2026, 10, 1),
      periodEnd: DateTime(2026, 10, 31),
      siteCalculations: [],
      taxRateBps: 1000,
      subtotalYenOverride: 10000,
      taxYenOverride: 1000,
      grandTotalYenOverride: 11000,
      companySealSnapshot: snapshot,
    );
    final savedInvoice = invoice(
      snapshot: CompanySealSnapshot.fromJson({
        'version': 1,
        'style': 'legacy',
        'name': '確定時の登録会社',
      }),
    );
    final savedPayment = PaymentCertificateRecord(
      id: 'saved',
      partnerCompanyId: 'saved-partner',
      partnerCompanyName: '保存取引先',
      payerCompanyName: '確定時の登録会社',
      periodStart: DateTime(2026, 10),
      periodEnd: DateTime(2026, 10, 31),
      grossAmount: 1000,
      deductions: 0,
      netAmount: 1000,
      status: 'confirmed',
      revision: 1,
    );
    for (final name in ['株式会社青空工業', '横川建設株式会社']) {
      companyName = name;
      final settings = await repository.loadForDocument();
      expect(settings.companyName, name);
      final records =
          PaymentCertificateRepository.withRegisteredCompanyPreviews(
            [savedPayment],
            [
              const PartnerPaymentSetting(
                partnerCompanyId: 'new-partner',
                partnerCompanyName: '新取引先',
                dailyRateYen: 25000,
                overtimeHourRateYen: 0,
                earlyHourRateYen: 0,
                nightHourRateYen: 0,
                allowances: [],
              ),
            ],
            company: {'name': name, 'company_seal_enabled': false},
            month: DateTime(2026, 10),
          );
      final preview = records.singleWhere((r) => r.isPreview);
      expect(preview.payerCompanyName, name);
      expect(records.singleWhere((r) => !r.isPreview), same(savedPayment));
      expect(savedPayment.payerCompanyName, '確定時の登録会社');
      expect(
        savedInvoice.companySealSnapshot.registeredName(settings.companyName),
        '確定時の登録会社',
      );
      if (font != null) {
        final currentText = await text(
          await InvoicePdfService.buildPdf(
            [invoice()],
            settings: settings,
            regularFont: font,
            boldFont: font,
          ),
          'settings_company_name_invoice_${requests.length}',
        );
        expect(currentText, contains(name));
        expect(currentText, isNot(contains('旧端末だけの会社名')));
        final savedText = await text(
          await InvoicePdfService.buildPdf(
            [savedInvoice],
            settings: settings,
            regularFont: font,
            boldFont: font,
          ),
          'settings_company_name_saved_invoice_${requests.length}',
        );
        expect(savedText, contains('確定時の登録会社'));
        expect(savedText, isNot(contains(name)));
        final paymentText = await text(
          await PaymentCertificatePdfService.buildPdf(
            preview,
            regularFont: font,
            boldFont: font,
          ),
          'settings_company_name_payment_${requests.length}',
        );
        expect(paymentText, contains(name));
        expect(paymentText, isNot(contains('旧端末だけの会社名')));
      }
    }
    expect(requests, hasLength(2));
    expect(
      (await SharedPreferences.getInstance()).getString(
        'settings_company_name',
      ),
      '旧端末だけの会社名',
    );
  });
}
