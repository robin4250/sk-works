import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
void main(){
 test('screen print and share use the exact same formal invoice PDF bytes',(){
  final s=File('lib/features/invoices/invoice_pdf_service.dart').readAsStringSync();
  expect(s,contains('final pdfBytes = await InvoicePdfService.buildPdf('));
  expect(s,contains('Printing.raster('));
  expect(s,contains('onLayout: (_) async => pdfBytes'));
  expect(s,contains('bytes: pdfBytes'));
  expect(s,contains('pages.add(await page.toPng())'));
  expect(s,isNot(contains('class _InvoiceNativePreview')));
 });
}
