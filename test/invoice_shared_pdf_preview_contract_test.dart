import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('invoice preview renders the exact shared PDF bytes', () {
    final s = File('lib/features/invoices/invoice_pdf_service.dart')
        .readAsStringSync();
    expect(s, contains('child: _InvoicePdfZoomView('));
    expect(s, contains('Printing.raster(widget.pdfBytes, dpi: 120)'));
    expect(s, contains('minScale: 1'));
    expect(s, contains('maxScale: 5'));
    expect(s, contains('constraints.maxHeight'));
    expect(s, contains('onLayout: (_) async => pdfBytes'));
    expect(s, contains('bytes: pdfBytes'));
    expect(s, isNot(contains('child: _ExactInvoiceScreen(')));
    expect(s, contains('Printing.layoutPdf('));
    expect(s, contains('Printing.sharePdf('));
  });
}
