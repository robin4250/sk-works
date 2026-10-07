import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
void main(){
 test('native preview mirrors adopted formal invoice template',(){
  final s=File('lib/features/invoices/invoice_pdf_service.dart').readAsStringSync();
  for(final label in ['御　請　求　書','御請求金額','御中','振込先：','件名 ／ 工期','作業所名','工事内容','合計(税込)','お支払約定日','備考：']){
    expect(s,contains(label));
  }
  expect(s,contains('class _NativeCompanySeal'));
  expect(s,contains('class _NativeApprovalBoxes'));
  expect(s,contains('approvals: approvals'));
  expect(s,contains('Color(0xff8199b5)'));
  expect(s,contains('width: 595'));
  expect(s,contains('height: 842'));
 });
}
