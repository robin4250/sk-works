import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:sk_works/features/shared/company_seal_pdf.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'bundled licensed seal data gives each PDF an independent font wrapper',
    () async {
      final first = CompanySealPdf.loadFont();
      expect(identical(first, CompanySealPdf.loadFont()), isTrue);
      final font = await first;
      final pdf = pw.Document();
      pdf.addPage(
        pw.Page(build: (_) => CompanySealPdf.build('すみだ建設株式会社', font: font)),
      );
      final bytes = await pdf.save();
      expect(bytes.length, greaterThan(1000));
      for (final name in [
        'original-use-instructions.txt',
        'original-font-description.pdf',
        'original-font-description.doc',
      ]) {
        expect(
          File('assets/fonts/company-seal/$name').existsSync(),
          isTrue,
          reason: 'Original redistribution documentation must accompany font',
        );
      }
    },
  );
  test('seal uses registered company name and never a fixed bitmap', () {
    expect(CompanySealPdf.verticalColumns(''), isEmpty);
    expect(CompanySealPdf.verticalColumns('株式会社テスト'), isNotEmpty);
    expect(
      CompanySealPdf.verticalColumns('株式会社テスト'),
      isNot(CompanySealPdf.verticalColumns('別会社')),
    );
  });

  test('company seal uses three vertical columns for long company names', () {
    final columns = CompanySealPdf.verticalColumns('東京都建設工業株式会社');
    expect(columns.length, 3);
    expect(columns.last, '株式会社');
    expect(columns.join(), '東京都建設工業株式会社');
  });

  test('all three document generators use shared company seal', () {
    final sources = [
      'lib/features/invoices/invoice_pdf_service.dart',
      'lib/features/payroll/payroll_pdf_service.dart',
      'lib/features/payroll/payment_certificate_pdf_service.dart',
    ];
    for (final path in sources) {
      expect(File(path).readAsStringSync(), contains('CompanySealPdf.build('));
    }
    expect(File(sources.last).readAsStringSync(), isNot(contains("'会社印'")));
  });
}
