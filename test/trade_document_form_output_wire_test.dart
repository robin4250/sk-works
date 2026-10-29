import 'dart:io';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/domain/trade_document_editor_payload.dart';
import 'package:sk_works/domain/trade_document_form_draft.dart';
import 'package:sk_works/features/shared/trade_document_form_renderer.dart';
import 'package:sk_works/features/shared/trade_document_output_layout.dart';
import 'trade_document_form_draft_test.dart' show formBody;
void main(){
 TestWidgetsFlutterBinding.ensureInitialized();
 for(final kind in ['invoice','payment_certificate']){
  for(final modern in [false,true]){
   test('$kind source revision cannot infer original partner from a same-name current party ($modern)',(){
    final saved=formBody();if(!modern)saved.remove('contract_terms');
    final before=jsonEncode(saved);
    expect(()=>preserveSavedTradeDocumentFields(payload:formBody(),workspace:{'source_changed':true,'attachment':{'payload':saved},'canonical_parent_binding':{'parent_id':'subject','company_id':'company','partner_company_id':'new-id'}},subjectKind:kind,subjectId:'subject'),throwsStateError);
    expect(jsonEncode(saved),before);
   });
  }
 }
 test('unchanged saved absence remains absent and manual fields are deep-copied',(){
  final saved=formBody()..remove('contract_terms');saved['form_fields']=TradeDocumentFormFields.empty().toJson();
  final value=preserveSavedTradeDocumentFields(payload:formBody(),workspace:{'source_changed':false,'attachment':{'payload':saved}},subjectKind:'invoice',subjectId:'subject');
  expect(value.containsKey('contract_terms'),false);expect(value.containsKey('counterparty_bank'),false);
  value['form_fields']['rows'][0]['item']='new';expect(saved['form_fields']['rows'][0]['item'],'');
 });
 test('actual typed Japanese front and full terms compose all formats without changing canonical bytes or body',()async{
  final payload=formBody(),fields=TradeDocumentFormFields.empty().toJson();
  payload['issuer']['representative_name']='自社代表';payload['counterparty']['representative_name']='相手代表';
  fields['work_content']='入力した工事内容';fields['supplies']='支給品入力';fields['payment_day']=25;fields['payment_month_offset']=1;
  fields['payments']['advance']={'choice':'yes','date':'2026-10-05','amount_yen':15000};
  fields['rows'][0]={'item':'第一明細入力','quantity':'1.250','unit':'m2','unit_price_yen':800,'amount_yen':999,'note':'計算しない備考'};
  fields['rows'][8]={'item':'第九明細入力','quantity':'2','unit':'式','unit_price_yen':300,'amount_yen':500,'note':'最終明細保持'};
  payload['form_fields']=fields;final before=jsonEncode(payload),canonical=await TradeDocumentFormRenderer.canonical(payload);
  final directory=Platform.environment['TRADE_TYPED_PDF_OUTPUT_DIR'];
  for(final layout in TradeDocumentOutputLayout.values){
   final bytes=await TradeDocumentFormRenderer.output(payload,layout:layout,canonicalBytes:canonical);
   if(layout==TradeDocumentOutputLayout.a4TwoPages)expect(identical(bytes,canonical),true);
   expect(jsonEncode(payload),before);
   if(directory!=null){Directory(directory).createSync(recursive:true);File('$directory/${layout.name}.pdf').writeAsBytesSync(bytes);}
  }
  final legacy=Map<String,dynamic>.from(payload)..remove('contract_terms');
  expect(identical(await TradeDocumentFormRenderer.output(legacy,layout:TradeDocumentOutputLayout.a4TwoPages,canonicalBytes:canonical),canonical),true);
  await expectLater(TradeDocumentFormRenderer.output(legacy,layout:TradeDocumentOutputLayout.a3Landscape,canonicalBytes:canonical),throwsFormatException);
 });
}
