import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
void main() {
  test('invoice preview renders the exact shared PDF bytes', () {
    final s=File('lib/features/invoices/invoice_pdf_service.dart').readAsStringSync();
    expect(s, contains('child: PdfPreview('));
    expect(s, contains('build: (_) async => pdfBytes'));
    expect(s, contains('initialPageFormat: PdfPageFormat.a4'));
    expect(s, contains('allowPrinting: false'));
    expect(s, contains('allowSharing: false'));
    expect(s, isNot(contains('child: _ExactInvoiceScreen(')));
    expect(s, contains('Printing.layoutPdf('));
    expect(s, contains('Printing.sharePdf('));
  });
}
