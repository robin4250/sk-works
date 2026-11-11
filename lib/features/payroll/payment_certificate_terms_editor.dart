import 'package:flutter/material.dart';
import '../../domain/rate_formula_settings.dart';
import 'payment_certificate_terms_draft.dart';

const _basisLabels={CertificatePayBasis.hourly:'時給',CertificatePayBasis.daily:'日給',
  CertificatePayBasis.monthly:'月給',CertificatePayBasis.contract:'請負'};
const _unitLabels={CertificateItemUnit.hour:'時間単位',CertificateItemUnit.day:'日単位',
  CertificateItemUnit.month:'月単位'};
const _formulaLabels={'hours_per_day':'1日の時間','overtime_multiplier':'残業倍率',
  'early_multiplier':'早出倍率','night_multiplier':'夜勤倍率',
  'night_overtime_multiplier':'夜勤残業倍率','holiday_multiplier':'休日出勤倍率',
  'holiday_overtime_multiplier':'休日残業倍率','holiday_night_multiplier':'休日夜勤倍率',
  'holiday_night_overtime_multiplier':'休日夜勤残業倍率'};

/// Storage must be explicitly connected; this editor never writes new units
/// through the legacy amount-only RPC and never changes employee payroll.
class PaymentCertificateTermsEditor extends StatefulWidget {
  const PaymentCertificateTermsEditor({super.key,required this.initialValue,
    required this.canEdit,this.onSave});
  final CertificateTermsDraft initialValue;
  final bool canEdit;
  final Future<void> Function(CertificateTermsDraft)? onSave;
  @override
  State<PaymentCertificateTermsEditor> createState()=>_TermsState();
}
class _TermsState extends State<PaymentCertificateTermsEditor> {
  late CertificatePayBasis _basis;
  var _direction=CertificateItemDirection.payment;
  var _unit=CertificateItemUnit.hour;
  late final Map<CertificatePayBasis,_BasisDraft> _bases;
  late final List<_ItemDraft> _items;
  final _retired=<_ItemDraft>[];
  late final TextEditingController _welfare,_tax;
  var _nextId=0;
  var _saving=false;
  String? _error;
  bool get _editable=>widget.canEdit && widget.onSave!=null && !_saving;
  @override
  void initState(){
    super.initState();_basis=widget.initialValue.selectedBasis;
    _bases={for(final b in CertificatePayBasis.values)b:_BasisDraft(widget.initialValue.bases[b]!)};
    _items=widget.initialValue.items.map(_ItemDraft.new).toList();
    _welfare=TextEditingController(text:widget.initialValue.welfarePercent.toString());
    _tax=TextEditingController(text:widget.initialValue.taxPercent.toString());
  }
  @override
  void dispose(){
    for(final b in _bases.values){b.dispose();}
    for(final i in [..._items,..._retired]){i.dispose();}
    _welfare.dispose();_tax.dispose();super.dispose();
  }
  void _add(){
    String id;
    do{id='certificate-item-${_nextId++}';}while(_items.any((i)=>i.value.id==id));
    setState(()=>_items.add(_ItemDraft(CertificateUnitItem(id:id,basis:_basis,
      direction:_direction,unit:_unit,name:'',amountYen:0))));
  }
  int _money(TextEditingController c,String label){
    final n=int.tryParse(c.text.trim());
    if(n==null || n<0){throw StateError('$labelは0以上の整数で入力してください');}
    return n;
  }
  double _percent(TextEditingController c,String label){
    final n=double.tryParse(c.text.trim());
    if(n==null || !n.isFinite || n<0 || n>100){throw StateError('$labelは0〜100で入力してください');}
    return n;
  }
  CertificateBasisTerms _terms(CertificatePayBasis b,{bool validate=false}){
    final d=_bases[b]!;
    final map=<String,dynamic>{'base_mode':b==CertificatePayBasis.hourly?'hourly':'daily'};
    for(final e in d.formulas.entries){
      final n=double.tryParse(e.value.text.trim());
      if(validate && (n==null || !n.isFinite || n<0 || e.key=='hours_per_day' && n<=0)){
        throw StateError('${_basisLabels[b]}の${_formulaLabels[e.key]}を確認してください');
      }
      map[e.key]=n??0;
    }
    return CertificateBasisTerms(
      amountYen:validate?_money(d.amount,'${_basisLabels[b]}の金額'):int.tryParse(d.amount.text)??0,
      calculationDailyYen:validate?_money(d.daily,'計算用の1日単価'):int.tryParse(d.daily.text)??0,
      formula:RateFormulaSettings.fromMap(map));
  }
  Future<void> _save()async{
    if(!_editable){return;}
    try{
      final bases={for(final b in CertificatePayBasis.values)b:_terms(b,validate:true)};
      final names=<String>{};
      final rows=<CertificateUnitItem>[];
      for(final i in _items){
        final name=i.name.text.trim();
        if(name.isEmpty){throw StateError('追加項目の名称を入力してください');}
        final key='${i.value.basis.name}/${i.value.direction.name}/${i.value.unit.name}/$name';
        if(!names.add(key)){throw StateError('同じタブ・単位の項目名が重複しています');}
        rows.add(CertificateUnitItem(id:i.value.id,basis:i.value.basis,direction:i.value.direction,
          unit:i.value.unit,name:name,amountYen:_money(i.amount,name)));
      }
      final value=CertificateTermsDraft(selectedBasis:_basis,bases:bases,items:rows,
        welfarePercent:_percent(_welfare,'福利厚生費率'),taxPercent:_percent(_tax,'消費税率'));
      setState(()=>_saving=true);await widget.onSave!(value);
      if(mounted){setState(()=>_error=null);}
    }catch(e){if(mounted){setState(()=>_error=e.toString().replaceFirst('Bad state: ',''));}}
    finally{if(mounted){setState(()=>_saving=false);}}
  }
  Widget _tabs<T>(Iterable<T> values,T selected,String Function(T) label,void Function(T) select)=>
    Row(children:[for(final value in values)Expanded(child:Padding(
      padding:const EdgeInsets.symmetric(horizontal:2),child:OutlinedButton(
        style:OutlinedButton.styleFrom(padding:const EdgeInsets.symmetric(horizontal:3),
          backgroundColor:value==selected?Theme.of(context).colorScheme.primaryContainer:null),
        onPressed:_saving?null:()=>setState(()=>select(value)),child:Text(label(value)))))]);

  Widget _field(TextEditingController c,String label,{Key? key,bool decimal=false,String? suffix='円'})=>
    Padding(padding:const EdgeInsets.symmetric(vertical:6),child:TextField(
      key:key,controller:c,enabled:_editable,onChanged:(_)=>setState((){}),
      keyboardType:TextInputType.numberWithOptions(decimal:decimal),
      decoration:InputDecoration(labelText:label,suffixText:suffix,border:const OutlineInputBorder())));

  @override
  Widget build(BuildContext context){
    final d=_bases[_basis]!;
    final terms=_terms(_basis);
    final visible=_items.where((i)=>i.value.basis==_basis &&
      i.value.direction==_direction && i.value.unit==_unit);
    return Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
      _tabs(CertificatePayBasis.values,_basis,(b)=>_basisLabels[b]!,(b)=>_basis=b),
      _field(d.amount,'${_basisLabels[_basis]}の金額',key:ValueKey('base-${_basis.name}')),
      if(_basis==CertificatePayBasis.monthly || _basis==CertificatePayBasis.contract)
        _field(d.daily,'計算用の1日単価',key:ValueKey('calculation-daily-${_basis.name}')),
      ExpansionTile(key:PageStorageKey('certificate-terms-formula-${_basis.name}'),
        title:const Text('計算式'),maintainState:true,initiallyExpanded:false,children:[
          for(final e in d.formulas.entries)_field(e.value,_formulaLabels[e.key]!,decimal:true,suffix:null),
          Text('残業 ${terms.formula.overtimeFormula(terms.calculationInput(_basis),hourlyBase:_basis==CertificatePayBasis.hourly)}'),
        ]),
      const SizedBox(height:10),
      _tabs(CertificateItemDirection.values,_direction,
        (d)=>d==CertificateItemDirection.payment?'支払い':'差引き',(d)=>_direction=d),
      _tabs(CertificateItemUnit.values,_unit,(u)=>_unitLabels[u]!,(u)=>_unit=u),
      for(final i in visible)Card(key:ValueKey(i.value.id),child:Padding(
        padding:const EdgeInsets.all(10),child:Column(children:[
          TextField(controller:i.name,enabled:_editable,decoration:const InputDecoration(
            labelText:'項目名',border:OutlineInputBorder())),
          _field(i.amount,'単価'),
          Align(alignment:Alignment.centerRight,child:TextButton.icon(
            onPressed:_editable?()=>setState((){_items.remove(i);_retired.add(i);}):null,
            icon:const Icon(Icons.delete_outline),label:const Text('削除'))),
        ]))),
      OutlinedButton.icon(onPressed:_editable?_add:null,icon:const Icon(Icons.add),label:const Text('項目を追加')),
      const SizedBox(height:16),
      const Text('福利厚生費・消費税',style:TextStyle(fontWeight:FontWeight.bold)),
      _field(_welfare,'福利厚生費率',decimal:true,suffix:'%'),
      _field(_tax,'消費税率',decimal:true,suffix:'%'),
      if(_error!=null)Text(_error!,style:TextStyle(color:Theme.of(context).colorScheme.error)),
      FilledButton(onPressed:_editable?_save:null,child:Text(_saving?'保存中…':'設定を保存')),
    ]);
  }
}
class _BasisDraft{
  _BasisDraft(CertificateBasisTerms v):amount=TextEditingController(text:v.amountYen.toString()),
    daily=TextEditingController(text:v.calculationDailyYen.toString()),
    formulas={for(final k in _formulaLabels.keys)k:TextEditingController(text:v.formula.toMap()[k].toString())};
  final TextEditingController amount,daily;
  final Map<String,TextEditingController> formulas;
  void dispose(){amount.dispose();daily.dispose();for(final c in formulas.values){c.dispose();}}
}
class _ItemDraft{
  _ItemDraft(this.value):name=TextEditingController(text:value.name),amount=TextEditingController(text:value.amountYen.toString());
  final CertificateUnitItem value;
  final TextEditingController name,amount;
  void dispose(){name.dispose();amount.dispose();}
}
