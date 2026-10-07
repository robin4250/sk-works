import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
void main(){
 test('screen print and share use the exact same formal invoice PDF bytes',(){
  final s=File('lib/features/invoices/invoice_pdf_service.dart').readAsStringSync();
  expect(s,contains('final pdfBytes = await InvoicePdfService.buildPdf('));
  expect(s,contains('class _ExactInvoiceScreen'));
  expect(s,contains('onLayout: (_) async => pdfBytes'));
  expect(s,contains('bytes: pdfBytes'));
  expect(s,contains('_ScreenDetailTable(rows:rows)'));
  expect(s,isNot(contains('Printing.raster(')));
 });
}
