import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../data/supabase_backend.dart';
import 'site_payment_agreement_document.dart';
import 'payment_certificates_page.dart';

/// Only the deployed, enabled server workspace exposes editable agreements.
class SitePaymentAgreementPage extends StatefulWidget {
  const SitePaymentAgreementPage({super.key});
  @override
  State<SitePaymentAgreementPage> createState() => _SitePaymentAgreementPageState();
}

class _SitePaymentAgreementPageState extends State<SitePaymentAgreementPage> {
  String? _company;
  String? _item;
  Map<String, dynamic>? _workspace;
  List<Map<String, dynamic>> _targets = [];
  bool _busy = true;
  String? _error;
  SupabaseClient get _client => SupabaseBackend.client;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    if (!SupabaseBackend.isInitialized || _client.auth.currentUser == null) {
      if (mounted) setState(() { _busy = false; _error = 'ログインが必要です。'; });
      return;
    }
    setState(() { _busy = true; _error = null; });
    try {
      final memberships = await _client.from('company_members').select('company_id')
          .eq('user_id', _client.auth.currentUser!.id).limit(1);
      if (memberships.isEmpty) throw StateError('会社情報が見つかりません。');
      _company = memberships.first['company_id'].toString();
      final raw = await _client.rpc('site_payment_agreement_targets', params: {'p_company': _company});
      _targets = [if (raw is List) for (final item in raw) if (item is Map) Map<String, dynamic>.from(item)];
      if (_item != null) {
        final rawWorkspace = await _client.rpc('site_payment_agreement_workspace', params: {'p_item': _item, 'p_company': _company});
        _workspace = Map<String, dynamic>.from(rawWorkspace as Map);
      }
    } on PostgrestException catch (e) {
      _error = e.code == '42883' || e.code == 'PGRST202' || e.code == '55000'
          ? '現場別支払合意はまだ利用できません。' : e.message;
    } catch (e) { _error = e.toString(); }
    if (mounted) setState(() => _busy = false);
  }

  List<Map<String, dynamic>> get _proposals => [
    if (_workspace?['proposals'] is List)
      for (final p in _workspace!['proposals'] as List)
        if (p is Map) Map<String, dynamic>.from(p),
  ];

  Future<void> _confirm(Map<String, dynamic> proposal) async {
    setState(() => _busy = true);
    try {
      await _client.rpc('confirm_site_payment_terms', params: {'p_proposal': proposal['id'], 'p_company': _company});
      await _load();
    } catch (e) { if (mounted) setState(() { _error = e.toString(); _busy = false; }); }
  }

  Future<void> _edit() async {
    final latest = _proposals.isEmpty ? <String, dynamic>{} : Map<String, dynamic>.from(_proposals.first['terms'] as Map);
    if(latest.isEmpty && _workspace?['own_site_billing'] is Map) {
      final source=Map<String,dynamic>.from(_workspace!['own_site_billing'] as Map);
      final price=(source['billing_square_meter_unit_price_yen'] as num?)??0;
      final area=(source['billing_square_meter_quantity'] as num?)??0;
      final lump=(source['billing_contract_amount_yen'] as num?)??0;
      if(price>0 && area>0) { latest.addAll({'mode':'square_meter','unit_price_yen':price,'area':area,'base_amount_yen':price*area}); }
      else if(lump>0) { latest.addAll({'mode':'lump_sum','base_amount_yen':lump}); }
      latest['adjustments']=[for(var i=1;i<=3;i++) if((source['billing_allowance_${i}_name']?.toString().trim()??'').isNotEmpty) {'name':source['billing_allowance_${i}_name'],'amount_yen':source['billing_allowance_${i}_amount_yen']??0,'direction':'addition'}];
    }
    final now = DateTime.now();
    String date(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    final fields = <String, TextEditingController>{
      for (final key in ['unit_price_yen','area','base_amount_yen','tax_amount_yen','tax_rate','taxable_amount_yen','period_start','period_end'])
        key: TextEditingController(text: latest[key]?.toString() ?? (key == 'period_start' ? date(DateTime(now.year,now.month)) : key == 'period_end' ? date(DateTime(now.year,now.month+1,0)) : '0')),
    };
    final extraCount=latest['adjustments'] is List && (latest['adjustments'] as List).length>3 ? (latest['adjustments'] as List).length : 3;
    final extras = [for (var i=0;i<extraCount;i++) <String, TextEditingController>{'name': TextEditingController(), 'amount_yen': TextEditingController(text:'0')}];
    final directions = List<String>.filled(extraCount, 'addition', growable: true);
    final allExtraControllers = [...extras];
    final taxReason = TextEditingController(text: latest['tax_override_reason']?.toString() ?? '');
    var manualTax = taxReason.text.trim().isNotEmpty;
    if (latest['adjustments'] is List) {
      final saved = latest['adjustments'] as List;
      for (var i=0;i<saved.length && i<extraCount;i++) {
        final item = saved[i] as Map;
        extras[i]['name']!.text = item['name']?.toString() ?? '';
        extras[i]['amount_yen']!.text = item['amount_yen']?.toString() ?? '0';
        directions[i] = item['direction']?.toString() ?? 'addition';
      }
    }
    var mode = latest['mode']?.toString() ?? 'square_meter';
    var rounding = latest['rounding_rule']?.toString() ?? 'floor';
    var included = latest['tax_included'] == true;
    void recalculate() {
      num rounded(num value) => rounding=='ceil'?value.ceil():rounding=='nearest'?value.round():value.floor();
      final price=num.tryParse(fields['unit_price_yen']!.text);
      final area=num.tryParse(fields['area']!.text);
      if(mode=='square_meter' && price!=null && area!=null && price.isFinite && area.isFinite && (price*area).isFinite) fields['base_amount_yen']!.text=rounded(price*area).toString();
      final taxable=num.tryParse(fields['taxable_amount_yen']!.text);
      final rate=num.tryParse(fields['tax_rate']!.text);
      if(!manualTax && taxable!=null && rate!=null && taxable.isFinite && rate.isFinite && (taxable*rate/100).isFinite) fields['tax_amount_yen']!.text=rounded(taxable*rate/100).toString();
    }
    recalculate();
    final result = await showDialog<Map<String,dynamic>>(context:context,builder:(context)=>StatefulBuilder(builder:(context,update)=>AlertDialog(
      title: const Text('現場別の金額提案'),
      content: SizedBox(width:480,child:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[
        const Text('相手の登録額は変更しません。双方が同じ最新版を確認すると合意済みになります。残業等の割増は計算しません。消費税は課税対象・税率・端数処理から計算します。手動変更には理由を入力し、相手にもその内容を確認してもらいます。'),
        DropdownButton<String>(value:mode,items:const[DropdownMenuItem(value:'square_meter',child:Text('平米計算')),DropdownMenuItem(value:'lump_sum',child:Text('請け負い'))],onChanged:(v)=>update(() { mode=v!; recalculate(); })),
        for(final entry in fields.entries)
          if(mode=='square_meter' || !['unit_price_yen','area'].contains(entry.key))
            TextField(controller:entry.value,readOnly:(mode=='square_meter' && entry.key=='base_amount_yen') || (entry.key=='tax_amount_yen' && !manualTax),onChanged: (_) => update(recalculate),decoration:InputDecoration(labelText:{'unit_price_yen':'平米単価（円）','area':'平米数','base_amount_yen':'基本総額（円）','tax_amount_yen':'消費税額（円）','tax_rate':'税率（%）','taxable_amount_yen':'課税対象額（円）','period_start':'対象期間 開始（YYYY-MM-DD）','period_end':'対象期間 終了（YYYY-MM-DD）'}[entry.key])),
        DropdownButton<String>(value:rounding,items:const[DropdownMenuItem(value:'floor',child:Text('端数切り捨て')),DropdownMenuItem(value:'nearest',child:Text('四捨五入')),DropdownMenuItem(value:'ceil',child:Text('端数切り上げ'))],onChanged:(v)=>update(() { rounding=v!; recalculate(); })),
        CheckboxListTile(value:manualTax,title:const Text('消費税額を手動変更する'),onChanged:(v)=>update(() { manualTax=v!; recalculate(); })),
        if(manualTax) TextField(controller:taxReason,decoration:const InputDecoration(labelText:'消費税額を変更する理由（必須）')),
        CheckboxListTile(value:included,title:const Text('基本額・追加額は税込（消費税を加算しない）'),onChanged:(v)=>update(()=>included=v!)),
        for(var i=0;i<extras.length;i++) ...[
          TextField(controller:extras[i]['name'],decoration:InputDecoration(labelText:'追加項目${i+1} 名称（福利厚生費等）')),
          TextField(controller:extras[i]['amount_yen'],decoration:const InputDecoration(labelText:'金額（円）')),
          DropdownButton<String>(value:directions[i],items:const[DropdownMenuItem(value:'addition',child:Text('加算')),DropdownMenuItem(value:'deduction',child:Text('控除'))],onChanged:(v)=>update(()=>directions[i]=v!)),
          TextButton.icon(onPressed:()=>update(() { extras.removeAt(i); directions.removeAt(i); }),icon:const Icon(Icons.remove_circle_outline),label:Text('追加項目${i+1}を削除')),
        ],
        OutlinedButton.icon(onPressed:()=>update(() {
          final item=<String,TextEditingController>{'name':TextEditingController(),'amount_yen':TextEditingController(text:'0')};
          extras.add(item); allExtraControllers.add(item); directions.add('addition');
        }),icon:const Icon(Icons.add),label:const Text('追加項目を増やす')),
      ]))),
      actions:[TextButton(onPressed:()=>Navigator.pop(context),child:const Text('取消')),FilledButton(onPressed:(){
        if(manualTax && taxReason.text.trim().isEmpty) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('消費税額を変更する理由を入力してください。'))); return; }
        for(final extra in extras) {
          final amount=num.tryParse(extra['amount_yen']!.text);
          if(extra['name']!.text.trim().isEmpty && (amount==null || amount!=0)) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('金額を入力した追加項目には名称も入力してください。'))); return; }
        }
        final adjustments = [for(var i=0;i<extras.length;i++) if(extras[i]['name']!.text.trim().isNotEmpty) {'name':extras[i]['name']!.text.trim(),'amount_yen':num.tryParse(extras[i]['amount_yen']!.text),'direction':directions[i]}];
        final base=num.tryParse(fields['base_amount_yen']!.text);
        final tax=num.tryParse(fields['tax_amount_yen']!.text);
        if(base==null || !base.isFinite || tax==null || !tax.isFinite || adjustments.any((a)=>a['amount_yen']==null || !(a['amount_yen'] as num).isFinite)) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('金額は数値で入力してください。'))); return; }
        final total=base+adjustments.fold<num>(0,(s,a)=>s+(a['amount_yen'] as num)*(a['direction']=='deduction'?-1:1))+(included?0:tax);
        if(!total.isFinite || total<0) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('最終額は0円以上の有限の金額にしてください。加算・控除と消費税額を確認してください。'))); return; }
        Navigator.pop(context,<String,dynamic>{'mode':mode,'rounding_rule':rounding,'tax_included':included,if(manualTax) 'tax_override_reason':taxReason.text.trim(),for(final e in fields.entries) e.key:e.key.startsWith('period_')?e.value.text:num.tryParse(e.value.text),'adjustments':adjustments,'final_amount_yen':total});
      },child:const Text('提案を保存'))],
    )));
    for(final field in fields.values) { field.dispose(); }
    for(final extra in allExtraControllers) { for(final field in extra.values) { field.dispose(); } }
    taxReason.dispose();
    if(result==null || !mounted) return;
    setState(()=>_busy=true);
    try {
      await _client.rpc('propose_site_payment_terms',params:{'p_item':_item,'p_company':_company,'p_expected_revision':_proposals.isEmpty?0:_proposals.first['revision'],'p_terms':result});
      await _load();
    } catch(e) { if(mounted) setState(() { _busy=false;_error=e.toString(); }); }
  }

  Future<void> _preview(Map<String,dynamic> proposal) async {
    setState(()=>_busy=true);
    try {
      await _openPreview(proposal);
    } catch(e) { if(mounted) setState(()=>_error=e.toString()); }
    finally { if(mounted) setState(()=>_busy=false); }
  }

  Future<void> _openPreview(Map<String,dynamic> proposal) async {
    final rawSnapshot=await _client.rpc('saved_site_payment_document',params:{'p_proposal':proposal['id'],'p_company':_company});
    final snapshot=Map<String,dynamic>.from(rawSnapshot as Map);
    final record=SitePaymentAgreementDocument.fromSnapshot(snapshot);
    if(!mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(builder:(_)=>PaymentCertificatePreviewPage(record:record)));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar:AppBar(title:const Text('現場別の支払金額調整'),actions:[IconButton(onPressed:()=>showDialog<void>(context:context,builder:(c)=>AlertDialog(title:const Text('金額調整の使い方'),content:const Text('承認済みの親会社・下請け会社の共有現場が対象です。金額提案は履歴に保存し、双方が最新版を確認します。平米・請負では残業などを計算しません。追加項目は必要な数だけ増やし、名称・金額・加算／控除を登録できます。消費税は課税対象・税率・端数処理から計算し、手動変更するときは理由を添えて双方で確認します。会社固有の率や条件は自動設定しません。合意済みの最新版のみ同じPDFをプレビュー・印刷・共有できます。'),actions:[TextButton(onPressed:()=>Navigator.pop(c),child:const Text('閉じる'))])),icon:const Icon(Icons.help_outline))]),
    body:_busy?const Center(child:CircularProgressIndicator()):ListView(padding:const EdgeInsets.all(16),children:[
      if(_error!=null) Text(_error!),
      if(_targets.isEmpty) const Text('利用可能な共有現場はありません。双方の会社で機能が有効な承認済み現場が対象です。'),
      for(final target in _targets) ListTile(title:Text('${target['site_name']}／${target['counterparty_name']}'),onTap:(){_item=target['shared_item_id'].toString();_load();}),
      if(_workspace!=null) ...[
        FilledButton(onPressed:_edit,child:const Text('新しい金額を提案')),
        for(var i=0;i<_proposals.length;i++) Card(child:Padding(padding:const EdgeInsets.all(12),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          Text('第${_proposals[i]['revision']}版　${(_proposals[i]['terms'] as Map)['final_amount_yen']}円'),
          Text('基本額 ${(_proposals[i]['terms'] as Map)['base_amount_yen']}円／確認 ${(_proposals[i]['confirmations'] as List).length}/2社'),
          Text('対象期間 ${(_proposals[i]['terms'] as Map)['period_start']}～${(_proposals[i]['terms'] as Map)['period_end']}'),
          Text('方式 ${(_proposals[i]['terms'] as Map)['mode']}／平米単価 ${(_proposals[i]['terms'] as Map)['unit_price_yen']}／平米数 ${(_proposals[i]['terms'] as Map)['area']}'),
          Text('税込 ${(_proposals[i]['terms'] as Map)['tax_included']}／消費税 ${(_proposals[i]['terms'] as Map)['tax_amount_yen']}円／税率 ${(_proposals[i]['terms'] as Map)['tax_rate']}%／課税対象 ${(_proposals[i]['terms'] as Map)['taxable_amount_yen']}円／端数 ${(_proposals[i]['terms'] as Map)['rounding_rule']}'),
          if(((_proposals[i]['terms'] as Map)['tax_override_reason']?.toString().trim() ?? '').isNotEmpty) Text('消費税額の手動変更理由：${(_proposals[i]['terms'] as Map)['tax_override_reason']}'),
          for(final extra in (_proposals[i]['terms'] as Map)['adjustments'] as List) Text('${(extra as Map)['name']}：${extra['direction']=='deduction'?'控除':'加算'} ${extra['amount_yen']}円'),
          if(i==0) OutlinedButton(onPressed:()=>_confirm(_proposals[i]),child:const Text('この内訳を確認')),
          if(i==0 && (_proposals[i]['confirmations'] as List).length==2) OutlinedButton(onPressed:()=>_preview(_proposals[i]),child:const Text('合意額の支払証明書')),
        ]))),
      ],
    ]),
  );
}
