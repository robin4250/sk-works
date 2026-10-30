import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/domain/trade_document_form_draft.dart';
import 'package:sk_works/features/shared/trade_document_form_renderer.dart';
import 'trade_document_form_draft_test.dart' show formBody;

void main(){
 TestWidgetsFlutterBinding.ensureInitialized();
 for(final kind in ['order','acceptance']){
  for(final withFields in [false,true]){
   test('historical adopted $kind keeps exact v1 rendering ($withFields)',()async{
    final p=formBody()..['kind']=kind;
    p['issuer']={'name':'保存済み会社','address':'保存済み住所','representative_name':'保存済み代表','phone':'03-1111-2222','fax':'03-3333-4444'};
    p['acceptance_text']='保存した承諾文';p['notes']=tradeDocumentDefaultNotes;
    p['company_seal_enabled']=true;p['company_seal_snapshot']={'version':1,'style':'legacy','name':'保存済み会社'};
    if(withFields){
     final f=TradeDocumentFormFields.empty().toJson();
     f['progress_cutoff_day']=31;f['rows'][0]={'item':'保存済み明細','quantity':'7','unit':'人日','unit_price_yen':32800,'amount_yen':229600,'note':'保存済み備考'};
     p['form_fields']=f;
    }
    final before=jsonEncode(p);final bytes=await TradeDocumentFormRenderer.canonical(p);
    expect(jsonEncode(p),before);expect(bytes.length,greaterThan(1000));
    final out=Platform.environment['TRADE_HISTORY_PDF_OUTPUT_DIR'];
    if(out!=null){Directory(out).createSync(recursive:true);File('$out/$kind-${withFields?'schema1':'absent'}.pdf').writeAsBytesSync(bytes);}
   });
  }
 }
}
