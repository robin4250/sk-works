import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:sk_works/features/invoices/invoice_pdf_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('body fonts preserve successful fetch and fallback to bundled Japanese offline', () async {
    final supplied = pw.Font.helvetica();
    expect(await InvoicePdfService.loadBodyFont(() async => supplied), same(supplied));
    final fallback = await InvoicePdfService.loadBodyFont(() async => throw const SocketException('offline'));
    expect(fallback, isA<pw.Font>());
  });
}
