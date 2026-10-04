import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('invoice cloud pages support English display', () {
    final source =
        File('lib/features/invoices/invoice_cloud_page.dart').readAsStringSync();

    expect(source, contains("SkoLanguageController.isEnglish ? 'Invoices'"));
    expect(source, contains("'Invoice Settings'"));
    expect(source, contains("'By Company'"));
    expect(source, contains("'All Companies'"));
    expect(source, contains("'Annual Preview'"));
    expect(source, contains("'Invoice Preview'"));
    expect(source, contains("'INVOICE'"));
    expect(source, contains("'Subtotal'"));
    expect(source, contains("'Tax'"));
    expect(source, contains("'Total'"));
    expect(source, contains("'Retry'"));
  });
}
