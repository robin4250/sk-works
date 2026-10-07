import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
void main(){
 test('invoice screen renders every formal section without PDF viewer or raster',(){
  final s=File('lib/features/invoices/invoice_pdf_service.dart').readAsStringSync();
  expect(s,contains('class _ExactInvoiceScreen'));
  expect(s,isNot(contains('Printing.raster(')));
  for(final x in ['御　請　求　書','御請求金額','振込先：','件名 ／ 工期','作業所名','工事内容','請求金額','合計(税込)','お支払約定日','備考：']){
    expect(s,contains(x));
  }
  expect(s,contains('width: 595'));
  expect(s,contains('height: 842'));
  expect(s,contains('onLayout: (_) async => pdfBytes'));
  expect(s,contains('bytes: pdfBytes'));
 });
}
