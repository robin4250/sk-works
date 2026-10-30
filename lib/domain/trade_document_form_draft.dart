import 'dart:convert';
import '../features/shared/trade_document_attachment.dart';
import 'trade_document_terms_snapshot.dart';

Map<String,dynamic> _copy(Map value)=>Map<String,dynamic>.from(jsonDecode(jsonEncode(value)) as Map);
void _invalid()=>throw const FormatException('入力内容・日付・文字数を確認してください。');
void _keys(Map value,Set<String> allowed){if(value.length!=allowed.length||value.keys.any((key)=>!allowed.contains(key)))_invalid();}
String _text(Object? value,int max,{bool multiline=false}){
 if(value is! String||value.runes.length>max||RegExp(multiline?r'[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]':r'[\x00-\x1f\x7f]').hasMatch(value))_invalid();return value as String;
}
int? _integer(Object? value,int min,int max){if(value==null)return null;if(value is! int||value<min||value>max)_invalid();return value as int;}
String? _date(Object? value){if(value==null)return null;if(value is! String)_invalid();final text=value as String,d=DateTime.tryParse(text);if(!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(text)||d==null||d.toIso8601String().substring(0,10)!=text)_invalid();return text;}

/// Explicit printable contract entries. No totals/rates are inferred or written
/// to any invoice/payment/payroll row. Empty money/date remains null, not zero.
class TradeDocumentFormFields {
 TradeDocumentFormFields._(this._value);
 final Map<String,dynamic> _value;
 static const keys={'schema','work_content','issuer_phone','issuer_fax','payments','progress_cutoff_day','invoice_cutoff_day','payment_day','payment_month_offset','cash_ratio_percent','bill_ratio_percent','bill_months','supplies','rows'};
 factory TradeDocumentFormFields.empty()=>TradeDocumentFormFields.fromJson({
  'schema':1,'work_content':'','issuer_phone':'','issuer_fax':'',
  'payments':{for(final key in ['advance','partial','completion'])key:{'choice':'unspecified','date':null,'amount_yen':null}},
  'progress_cutoff_day':null,'invoice_cutoff_day':null,'payment_day':null,'payment_month_offset':null,
  'cash_ratio_percent':null,'bill_ratio_percent':null,'bill_months':null,'supplies':'',
  'rows':[for(var i=0;i<9;i++){'item':'','quantity':'','unit':'','unit_price_yen':null,'amount_yen':null,'note':''}],
 });
 factory TradeDocumentFormFields.fromJson(Object? raw){
  if(raw is! Map)_invalid();final value=_copy(raw as Map);final schema=value['schema'];if(schema is! int||!const [1,2].contains(schema))_invalid();
  _keys(value,schema==2?{...keys,'issuer_representative_title','amount_description'}:keys);
  if(schema==2){_text(value['issuer_representative_title'],32);_text(value['amount_description'],240);}
  _text(value['work_content'],240,multiline:true);_text(value['issuer_phone'],40);_text(value['issuer_fax'],40);_text(value['supplies'],400,multiline:true);
  final payments=value['payments'];if(payments is! Map)_invalid();_keys(payments as Map,{'advance','partial','completion'});
  for(final key in ['advance','partial','completion']){
   final row=payments[key];if(row is! Map)_invalid();_keys(row as Map,{'choice','date','amount_yen'});
   if(!const ['unspecified','yes','no'].contains(row['choice']))_invalid();_date(row['date']);_integer(row['amount_yen'],0,2147483647);
   if(row['choice']=='no'&&(row['date']!=null||row['amount_yen']!=null))_invalid();
  }
  for(final key in ['progress_cutoff_day','invoice_cutoff_day','payment_day']){
   if(schema==2&&key=='progress_cutoff_day'&&value[key]=='month_end')continue;
   _integer(value[key],1,31);
  }
  _integer(value['payment_month_offset'],0,2);_integer(value['bill_months'],0,120);
  for(final key in ['cash_ratio_percent','bill_ratio_percent']){
   final ratio=value[key];if(ratio!=null&&(ratio is! String||!RegExp(r'^\d{1,3}(?:\.\d{1,2})?$').hasMatch(ratio)||double.parse(ratio)>100))_invalid();
  }
  final rows=value['rows'];if(rows is! List||rows.length!=9)_invalid();
  for(final row in rows as List){
   if(row is! Map)_invalid();_keys(row as Map,{'item','quantity','unit','unit_price_yen','amount_yen','note'});
   _text(row['item'],120,multiline:true);_text(row['unit'],16);_text(row['note'],80,multiline:true);
   final quantity=_text(row['quantity'],16);if(quantity.isNotEmpty&&!RegExp(r'^\d+(?:\.\d{1,3})?$').hasMatch(quantity))_invalid();
   _integer(row['unit_price_yen'],0,2147483647);_integer(row['amount_yen'],0,2147483647);
  }
  return TradeDocumentFormFields._(value);
 }
 Map<String,dynamic> toJson()=>_copy(_value);
}

const tradeDocumentDefaultNotes='[特記事項]　（右記工事請負契約条項に記載されてない事項を記入）';

String tradeDocumentClosingDay(Object? value)=>value=='month_end'?'末日':value?.toString()??'';

/// Immutable working copy for the touch editor. Company identity, parties,
/// bank, terms and seal never enter its editable patch namespace.
class TradeDocumentFormDraft {
 TradeDocumentFormDraft._(this._payload,this.allowAmountEditing);
 final Map<String,dynamic> _payload;
 final bool allowAmountEditing;
 bool get isOrder=>_payload['kind']=='order';
 static const _textLimits={'issue_date':10,'order_date':10,'work_name':240,'work_address':240,'period_start':10,'period_end':10,'payment_conditions':400,'notes':600,'intro_text':400,'acceptance_text':400};
 factory TradeDocumentFormDraft.fromPayload(Map<String,dynamic> payload,{required bool allowAmountEditing, bool initializeExtendedFields=false, bool initializeDefaults=false}){
  TradeDocumentAttachment.fromJson({'version':1,'payload':payload});
  // A historical unmarked document must keep its original editor/renderer.
  TradeDocumentTermsSnapshot.fromJson(payload['contract_terms']);
  final value=_copy(payload);
  value['form_fields']=(value.containsKey('form_fields')?TradeDocumentFormFields.fromJson(value['form_fields']):TradeDocumentFormFields.empty()).toJson();
  if(initializeDefaults&&!payload.containsKey('form_fields')) {
    if((value['notes']?.toString()??'').isEmpty)value['notes']=tradeDocumentDefaultNotes;
    final fields=Map<String,dynamic>.from(value['form_fields'] as Map);
    fields.addAll({'work_content':'とび工事','invoice_cutoff_day':10,'payment_month_offset':2,'payment_day':5,'cash_ratio_percent':'100','supplies':'仮設材他',
      'payments':{for(final k in ['advance','partial','completion'])k:{'choice':'no','date':null,'amount_yen':null}},
      'rows':[
        {'item':'とび工　安全施設・足場組立解体作業（一般作業員）','quantity':'1','unit':'人日','unit_price_yen':null,'amount_yen':null,'note':''},
        for(var i=1;i<9;i++){'item':'','quantity':'','unit':'','unit_price_yen':null,'amount_yen':null,'note':''},
      ]});
    value['form_fields']=fields;
  }
  if(initializeDefaults&&initializeExtendedFields&&!payload.containsKey('form_fields')) {
    value['form_fields']={...value['form_fields'] as Map,'schema':2,'progress_cutoff_day':'month_end','amount_description':'下記「施工単価内訳書」による','issuer_representative_title':(value['issuer'] as Map)['representative_name']?.toString().trim().isNotEmpty==true?'代表取締役':''};
  }
  return TradeDocumentFormDraft._(value,allowAmountEditing);
 }
 Map<String,dynamic> get payload=>_copy(_payload);
 TradeDocumentFormDraft withChanges(Map<String,Object?> changes){
  final next=payload;
  for(final entry in changes.entries){
   if(entry.key=='form_fields'){
    final fields=TradeDocumentFormFields.fromJson(entry.value).toJson(),previous=_payload['form_fields'] as Map;
    // Registered-company contact data is edited at its normal source screen.
    if(fields['issuer_phone']!=previous['issuer_phone']||fields['issuer_fax']!=previous['issuer_fax'])_invalid();
    next[entry.key]=fields;
   }else if(_textLimits.containsKey(entry.key)){
    next[entry.key]=_text(entry.value,_textLimits[entry.key]!,multiline:!entry.key.endsWith('_date')&&!entry.key.startsWith('period_'));
    if((entry.key.endsWith('_date')||entry.key.startsWith('period_'))&&(entry.value as String).isNotEmpty)_date(entry.value);
   }else if(const ['total_amount_yen','tax_amount_yen'].contains(entry.key)&&allowAmountEditing){
    var money=entry.value;if(money is String&&RegExp(r'^\d{1,10}$').hasMatch(money))money=int.tryParse(money);
    if(money==null)_invalid();next[entry.key]=_integer(money,0,2147483647);
   }else{throw const FormatException('登録会社・角印・元帳票の金額はこの入力欄で変更できません。');}
  }
  return TradeDocumentFormDraft._(next,allowAmountEditing);
 }
 void validateForSave(){
  TradeDocumentAttachment.fromJson({'version':1,'payload':_payload});TradeDocumentFormFields.fromJson(_payload['form_fields']);
  for(final entry in _textLimits.entries){if(_payload[entry.key]!=null)_text(_payload[entry.key],entry.value,multiline:!entry.key.endsWith('_date')&&!entry.key.startsWith('period_'));}
  for(final key in ['work_name','work_address']){if((_payload[key] as String? ?? '').trim().isEmpty)_invalid();}
  _date(_payload['issue_date']);if(_payload['issue_date']==null||_payload['issue_date']=='')_invalid();
  if(isOrder){
   for(final key in ['period_start','period_end']){if(_payload[key]==null||_payload[key]=='')_invalid();_date(_payload[key]);}
   if((_payload['period_start'] as String).compareTo(_payload['period_end'] as String)>0)_invalid();
   final total=_integer(_payload['total_amount_yen'],0,2147483647),tax=_integer(_payload['tax_amount_yen'],0,2147483647);if(total==null||tax==null||tax>total)_invalid();
   if((_payload['payment_conditions'] as String? ?? '').trim().isEmpty)_invalid();
  }else{
   if(_payload['order_date']==null||_payload['order_date']=='')_invalid();_date(_payload['order_date']);
   if((_payload['acceptance_text'] as String? ?? '').trim().isEmpty)_invalid();
  }
  if(utf8.encode(jsonEncode(_payload)).length>16384)throw const FormatException('入力内容が保存できる容量を超えています。明細や特記事項の文字数を確認してください。');
 }
}
