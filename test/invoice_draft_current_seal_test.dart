import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:sk_works/domain/company_seal_design.dart';
import 'package:sk_works/domain/invoice_document_seal.dart';
import 'package:sk_works/domain/invoice_engine.dart';
import 'package:sk_works/features/invoices/invoice_pdf_service.dart';
import 'package:sk_works/features/invoices/invoice_settings_repository.dart';

Map<String, dynamic> company(String style) => {
  'id': CompanySealDesign.companyId,
  'name': CompanySealDesign.companyName,
  'company_seal_style': style,
};

Map<String, dynamic> document(Object? status) => {
  'status': status,
  'finalized_at': null,
  'approval_finalized_at': null,
  'invoice_seal_frozen': false,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final saved = {
    'version': 1,
    'style': 'legacy',
    'name': CompanySealDesign.companyName,
  };

  test(
    'new and saved drafts use current selection without mutating history',
    () {
      for (final old in [null, saved]) {
        for (final style in CompanySealDesign.designs.keys) {
          final seal = invoiceDocumentSeal(
            document: document('draft'),
            saved: old,
            currentCompany: company(style),
            companyId: CompanySealDesign.companyId,
          );
          expect(seal.style, style);
          expect(seal.companyId, CompanySealDesign.companyId);
        }
      }
      expect(saved['style'], 'legacy');
      expect(saved.containsKey('company_id'), isFalse);
    },
  );

  test(
    'final and unknown states keep snapshots without current company access',
    () {
      for (final status in [
        'finalized',
        'issued',
        'approved',
        null,
        '',
        'DRAFT',
      ]) {
        final seal = invoiceDocumentSeal(
          document: document(status),
          saved: saved,
          currentCompany: null,
          companyId: CompanySealDesign.companyId,
        );
        expect(seal.style, 'legacy');
        expect(
          invoiceDocumentSeal(
            document: document(status),
            saved: null,
            currentCompany: company('png_sumida_v1_standard'),
            companyId: CompanySealDesign.companyId,
          ).style,
          'legacy',
        );
      }
    },
  );

  test('finalized PNG remains fixed when current selection changes', () {
    final original = {
      'version': 1,
      'style': 'png_sumida_v1_worn',
      'name': CompanySealDesign.companyName,
      'company_id': CompanySealDesign.companyId,
    };
    final seal = invoiceDocumentSeal(
      document: document('finalized'),
      saved: original,
      currentCompany: company('png_sumida_v1_standard'),
      companyId: CompanySealDesign.companyId,
    );
    expect(seal.style, 'png_sumida_v1_worn');
    expect(original['style'], 'png_sumida_v1_worn');
  });

  test(
    'approved drafts, reopened history and old payloads never use current seal',
    () {
      for (final row in [
        {...document('draft'), 'approval_finalized_at': '2026-10-11T00:00:00Z'},
        {...document('draft'), 'finalized_at': '2026-10-11T00:00:00Z'},
        {...document('draft'), 'invoice_seal_frozen': true},
        {'status': 'draft'},
        {...document('draft')}..remove('finalized_at'),
        {...document('draft')}..remove('approval_finalized_at'),
        {...document('draft')}..remove('invoice_seal_frozen'),
      ]) {
        expect(
          invoiceDocumentSeal(
            document: row,
            saved: saved,
            currentCompany: company('png_sumida_v1_standard'),
            companyId: CompanySealDesign.companyId,
          ).style,
          'legacy',
        );
      }
    },
  );

  test('draft rejects unavailable or foreign company settings', () {
    for (final current in [
      null,
      {...company('legacy'), 'id': 'foreign'},
    ]) {
      expect(
        () => invoiceDocumentSeal(
          document: document('draft'),
          saved: saved,
          currentCompany: current,
          companyId: CompanySealDesign.companyId,
        ),
        throwsStateError,
      );
    }
  });

  final fontPath = Platform.environment['SKO_PDF_FONT_PATH'];
  test(
    'draft output embeds selected PNG after changing saved selection',
    () async {
      final fonts = ByteData.sublistView(File(fontPath!).readAsBytesSync());
      final outputs = <String>[];
      for (final style in ['png_sumida_v1_standard', 'png_sumida_v1_light']) {
        final invoice = InvoiceEngine.calculate(
          customerId: '取引先',
          billingPeriod: '2026年10月',
          detailMode: InvoiceDetailMode.consolidatedOnly,
          sites: const [],
          companySealSnapshot: invoiceDocumentSeal(
            document: document('draft'),
            saved: saved,
            currentCompany: company(style),
            companyId: CompanySealDesign.companyId,
          ),
        );
        final font = pw.Font.ttf(fonts);
        final bytes = await InvoicePdfService.buildPdf(
          [invoice],
          settings: const InvoiceSettingsData(
            companyName: CompanySealDesign.companyName,
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
          regularFont: font,
          boldFont: font,
          approvalsByInvoice: const {'': []},
        );
        final pdf = latin1.decode(bytes);
        expect(pdf, contains('/SMask'));
        outputs.add(pdf);
      }
      expect(outputs[0], isNot(outputs[1]));
      expect(saved['style'], 'legacy');
    },
    skip: fontPath == null,
  );
}
