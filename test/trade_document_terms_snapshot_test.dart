import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:sk_works/domain/company_seal_snapshot.dart';
import 'package:sk_works/domain/trade_document_terms_snapshot.dart';
import 'package:sk_works/domain/trade_document_terms_source.dart';
import 'package:sk_works/features/shared/trade_document_attachment.dart';
import 'package:sk_works/features/shared/company_seal_pdf.dart';
import 'package:sk_works/features/shared/trade_document_form_geometry.dart';
import 'package:sk_works/features/shared/standalone_trade_document.dart';
import 'package:sk_works/features/payroll/payment_order_pdf.dart';
import 'package:sk_works/features/payroll/payment_order_resolver.dart';
import 'package:sk_works/features/invoices/invoice_acceptance_resolver.dart';
import 'package:sk_works/features/invoices/invoice_order_acceptance_pdf.dart';

Map<String,dynamic> body(String kind)=>{
 'version':1,'kind':kind,'month':'2026-10','issue_date':'2026-09-30','order_date':'2026-09-15',
 'work_name':'検証工事','work_address':'東京都1-2-3','period_start':'2026-10-01','period_end':'2026-10-31',
 'total_amount_yen':110000,'tax_amount_yen':10000,'intro_text':'工事を発注します。','acceptance_text':'2026-09-15付の注文を承諾します。','payment_conditions':'完了後支払い。','notes':'既存の特記事項',
 'issuer':{'name':'株式会社自社','address':'東京都','representative_name':'甲代表','corporate_number':'1234567890123'},
 'counterparty':{'name':'株式会社相手','address':'大阪府','representative_name':'乙代表','corporate_number':'9876543210987'},
 'company_seal_enabled':false,'company_seal_snapshot':{'version':1,'style':'legacy','name':'株式会社自社'},
};
Map<String,dynamic> workspace(String kind,{bool locked=false,Map<String,dynamic>? saved})=>{
 'source_changed':false,'source_blocked':false,'source_locked':locked,'attachment':saved==null?null:{'version':3,'payload':saved},'defaults':body(kind),'template':<String,dynamic>{},
};
void main(){
 TestWidgetsFlutterBinding.ensureInitialized();
 test('exact immutable JSON bytes and all 22 original titles/paragraphs match the content address',(){
  final bytes=File('docs/fixtures/trade-document-terms/user-confirmed-20261029-v1.json').readAsBytesSync();
  expect(utf8.encode(tradeDocumentTermsV1Json),bytes);expect(sha256.convert(bytes).toString(),TradeDocumentTermsSnapshot.sourceSha256);
  final snapshot=TradeDocumentTermsSnapshot.fromJson(TradeDocumentTermsSnapshot.reference),raw=jsonDecode(utf8.decode(bytes)) as List;
  expect(snapshot.articles.length,22);for(var i=0;i<22;i++){expect(snapshot.articles[i].$1,raw[i][0]);expect(snapshot.articles[i].$2,raw[i][1]);}
  expect(utf8.encode(jsonEncode(TradeDocumentTermsSnapshot.reference)).length,lessThan(512));
 });
 test('approved front geometry source is preserved exactly without sample company names',(){
  final expected=jsonDecode(File('docs/fixtures/trade-document-design/original-design-20261029.json').readAsStringSync());expect(tradeDocumentFormGeometry,expected);
 });
 test('unknown version/hash/title/null/additional fields fail closed and existing reference is never silently replaced',(){
  for(final value in [null,{...TradeDocumentTermsSnapshot.reference,'version':2},{...TradeDocumentTermsSnapshot.reference,'schema':1.0},{...TradeDocumentTermsSnapshot.reference,'design_sha256':'0'*64},{...TradeDocumentTermsSnapshot.reference,'renderer_contract':'unknown'},{...TradeDocumentTermsSnapshot.reference,'source_sha256':'0'*64},{...TradeDocumentTermsSnapshot.reference,'title':'別の題名'},{...TradeDocumentTermsSnapshot.reference,'extra':true}]){
   expect(()=>TradeDocumentTermsSnapshot.fromJson(value),throwsFormatException);
   expect(()=>TradeDocumentTermsSnapshot.initialize({...body('order'),'contract_terms':value}),throwsFormatException);
  }
 });
 test('new unlocked monthly drafts receive terms; saved and locked originals never acquire terms',(){
  expect(PaymentOrderResolver.resolve(workspace('order'))!.payload['contract_terms'],TradeDocumentTermsSnapshot.reference);
  expect(InvoiceAcceptanceResolver.resolve(workspace('acceptance'),issueDate:DateTime(2026,10,31))!.payload['contract_terms'],TradeDocumentTermsSnapshot.reference);
  for(final kind in ['order','acceptance']){
   final saved=body(kind),w=workspace(kind,locked:true,saved:saved);
   final actual=kind=='order'?PaymentOrderResolver.resolve(w):InvoiceAcceptanceResolver.resolve(w,issueDate:null);
   expect(actual!.payload,saved);expect(actual.version,3);expect(actual.payload.containsKey('contract_terms'),false);
  }
  final locked=InvoiceAcceptanceResolver.resolve(workspace('acceptance',locked:true),issueDate:DateTime(2026,10,31),parentSealSnapshot:CompanySealSnapshot.fromJson(body('acceptance')['company_seal_snapshot']),parentSealEnabled:false)!;
  expect(locked.payload.containsKey('contract_terms'),false);
 });
 test('new standalone order and acceptance bind the same exact terms reference, ignoring editable fake terms',(){
  for(final kind in ['order','acceptance']){
   final source=body(kind);final context={...source,'acceptance':kind=='acceptance'};
   final fields=<String,String>{for(final key in ['issue_date','order_date','work_name','work_address','period_start','period_end','total_amount_yen','tax_amount_yen','intro_text','acceptance_text','payment_conditions','notes'])key:source[key].toString(),'contract_terms.source_sha256':'forged'};
   final value=standaloneTradeDocument(context:context,fields:fields);expect(value.payload['contract_terms'],TradeDocumentTermsSnapshot.reference);
  }
 });
 test('actual PDFs render the adopted front and exact terms while legacy stays historical',()async{
  final font=await CompanySealPdf.loadFont(),output=Platform.environment['TRADE_TERMS_PDF_OUTPUT_DIR'];
  for(final kind in ['order','acceptance']){
   for(final modern in [false,true]){
    final payload=modern?TradeDocumentTermsSnapshot.initialize(body(kind)):body(kind);
    final attachment=TradeDocumentAttachment.fromJson({'version':1,'payload':payload}),document=pw.Document();
    if(kind=='order'){await PaymentOrderPdf.append(document,attachment,regularFont:font,boldFont:font);}
    else{await InvoiceOrderAcceptancePdf.append(document,attachment,regularFont:font,boldFont:font);}
    final bytes=await document.save();expect(bytes.length,greaterThan(1000));
    if(output!=null){Directory(output).createSync(recursive:true);File('$output/$kind-${modern?'terms':'legacy'}.pdf').writeAsBytesSync(bytes);}
   }
   final empty=TradeDocumentAttachment.fromJson({'version':1,'payload':TradeDocumentTermsSnapshot.initialize({...body(kind),'company_seal_enabled':true,'company_seal_snapshot':null})}),unsigned=pw.Document();
   if(kind=='order'){await PaymentOrderPdf.append(unsigned,empty,regularFont:font,boldFont:font);}else{await InvoiceOrderAcceptancePdf.append(unsigned,empty,regularFont:font,boldFont:font);}
   final unsignedBytes=await unsigned.save();if(output!=null)File('$output/$kind-unregistered.pdf').writeAsBytesSync(unsignedBytes);
  }
 });
 test('new form refuses impossible dates and another company seal instead of generating a substitute',()async{
  final font=await CompanySealPdf.loadFont();
  for(final kind in ['order','acceptance']){
   for(final patch in [<String,dynamic>{'issue_date':'2026-02-30'},<String,dynamic>{'company_seal_enabled':true,'company_seal_snapshot':{'version':1,'style':'legacy','name':'別会社'}}]){
    final value=TradeDocumentAttachment.fromJson({'version':1,'payload':TradeDocumentTermsSnapshot.initialize({...body(kind),...patch})}),doc=pw.Document();
    await expectLater(kind=='order'?PaymentOrderPdf.append(doc,value,regularFont:font,boldFont:font):InvoiceOrderAcceptancePdf.append(doc,value,regularFont:font,boldFont:font),throwsStateError);
   }
  }
 });
 test('registered own seal follows the actual short or long company-name right edge in both new forms',()async{
  final font=await CompanySealPdf.loadFont(),output=Platform.environment['TRADE_TERMS_PDF_OUTPUT_DIR'];
  final cases=['株式会社短','株式会社正式登録建設工事','株式会社正式登録建設工事サービス株式会社本社'];
  final manifest=<Map<String,dynamic>>[];
  for(final kind in ['order','acceptance']){
   for(var index=0;index<cases.length;index++){
    final name=cases[index],p=body(kind);p['issuer']={...(p['issuer'] as Map),'name':name};p['company_seal_enabled']=true;p['company_seal_snapshot']={'version':1,'style':'legacy','name':name};
    final value=TradeDocumentAttachment.fromJson({'version':1,'payload':TradeDocumentTermsSnapshot.initialize(p)}),doc=pw.Document();
    if(kind=='order'){await PaymentOrderPdf.append(doc,value,regularFont:font,boldFont:font);}else{await InvoiceOrderAcceptancePdf.append(doc,value,regularFont:font,boldFont:font);}
    final bytes=await doc.save();expect(bytes.length,greaterThan(1000));final file='$kind-seal-$index.pdf';manifest.add({'file':file,'kind':kind,'name':name});
    if(output!=null){Directory(output).createSync(recursive:true);File('$output/$file').writeAsBytesSync(bytes);}
   }
  }
  if(output!=null)File('$output/seals.json').writeAsStringSync(jsonEncode(manifest));
 });

}
