import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'screen print and share use the exact same formal invoice PDF bytes',
    () {
      final s = File('lib/features/invoices/invoice_pdf_service.dart')
          .readAsStringSync();
      expect(s, contains('final pdfBytes = await InvoicePdfService.buildPdf('));
      expect(s, contains('child: PdfPreview('));
      expect(s, contains('build: (_) async => pdfBytes'));
      expect(s, isNot(contains('child: _ExactInvoiceScreen(')));
      expect(s, contains('onLayout: (_) async => pdfBytes'));
      expect(s, contains('bytes: pdfBytes'));
      expect(s, contains('while (rows.length < 35)'));
      expect(s, contains('pageIndex * 35'));
      expect(s, isNot(contains('Printing.raster(')));
    },
  );
}
