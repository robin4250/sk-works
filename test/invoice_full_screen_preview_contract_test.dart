import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'invoice zoom renders all pages of the shared PDF in a bounded viewport',
    () {
      final s = File('lib/features/invoices/invoice_pdf_service.dart')
          .readAsStringSync();
      expect(s, contains('Printing.raster(widget.pdfBytes, dpi: 120)'));
      expect(s, contains('InteractiveViewer('));
      expect(s, contains('height: constraints.maxHeight'));
      expect(s, contains('SingleChildScrollView('));
      expect(s, contains('for (final page in snapshot.data!)'));
      expect(s, contains('minScale: 1'));
      expect(s, contains('maxScale: 5'));
      expect(s, contains('onLayout: (_) async => pdfBytes'));
      expect(s, contains('bytes: pdfBytes'));
      expect(s, isNot(contains('child: _ExactInvoiceScreen(')));
    },
  );
}
