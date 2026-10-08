import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../data/supabase_backend.dart';
import 'payment_certificate_repository.dart';
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
    final now = DateTime.now();
    String date(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    final fields = <String, TextEditingController>{
      for (final key in ['unit_price_yen','area','base_amount_yen','tax_amount_yen','tax_rate','taxable_amount_yen','period_start','period_end'])
        key: TextEditingController(text: latest[key]?.toString() ?? (key == 'period_start' ? date(DateTime(now.year,now.month)) : key == 'period_end' ? date(DateTime(now.year,now.month+1,0)) : '0')),
    };
    final extras = [for (var i=0;i<3;i++) <String, TextEditingController>{'name': TextEditingController(), 'amount_yen': TextEditingController(text:'0')}];
    final directions = List.filled(3, 'addition');
    if (latest['adjustments'] is List) {
      final saved = latest['adjustments'] as List;
      for (var i=0;i<saved.length && i<3;i++) {
        final item = saved[i] as Map;
        extras[i]['name']!.text = item['name']?.toString() ?? '';
        extras[i]['amount_yen']!.text = item['amount_yen']?.toString() ?? '0';
        directions[i] = item['direction']?.toString() ?? 'addition';
      }
    }
    var mode = latest['mode']?.toString() ?? 'square_meter';
    var rounding = latest['rounding_rule']?.toString() ?? 'floor';
    var included = latest['tax_included'] == true;
    final result = await showDialog<Map<String,dynamic>>(context:context,builder:(context)=>StatefulBuilder(builder:(context,update)=>AlertDialog(
      title: const Text('現場別の金額提案'),
      content: SizedBox(width:480,child:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[
        const Text('相手の登録額は変更しません。双方が同じ最新版を確認すると合意済みになります。残業等の割増は計算しません。税額は手動入力です。'),
        DropdownButton<String>(value:mode,items:const[DropdownMenuItem(value:'square_meter',child:Text('平米計算')),DropdownMenuItem(value:'lump_sum',child:Text('請け負い'))],onChanged:(v)=>update(()=>mode=v!)),
        for(final entry in fields.entries)
          if(mode=='square_meter' || !['unit_price_yen','area'].contains(entry.key))
            TextField(controller:entry.value,decoration:InputDecoration(labelText:{'unit_price_yen':'平米単価（円）','area':'平米数','base_amount_yen':'基本総額（円）','tax_amount_yen':'消費税額（円）','tax_rate':'税率（%）','taxable_amount_yen':'課税対象額（円）','period_start':'対象期間 開始（YYYY-MM-DD）','period_end':'対象期間 終了（YYYY-MM-DD）'}[entry.key])),
        DropdownButton<String>(value:rounding,items:const[DropdownMenuItem(value:'floor',child:Text('端数切り捨て')),DropdownMenuItem(value:'nearest',child:Text('四捨五入')),DropdownMenuItem(value:'ceil',child:Text('端数切り上げ'))],onChanged:(v)=>update(()=>rounding=v!)),
        CheckboxListTile(value:included,title:const Text('基本額・追加額は税込（消費税を加算しない）'),onChanged:(v)=>update(()=>included=v!)),
        for(var i=0;i<3;i++) ...[
          TextField(controller:extras[i]['name'],decoration:InputDecoration(labelText:'追加項目${i+1} 名称（福利厚生費等）')),
          TextField(controller:extras[i]['amount_yen'],decoration:const InputDecoration(labelText:'金額（円）')),
          DropdownButton<String>(value:directions[i],items:const[DropdownMenuItem(value:'addition',child:Text('加算')),DropdownMenuItem(value:'deduction',child:Text('控除'))],onChanged:(v)=>update(()=>directions[i]=v!)),
        ],
      ]))),
      actions:[TextButton(onPressed:()=>Navigator.pop(context),child:const Text('取消')),FilledButton(onPressed:(){
        final adjustments = [for(var i=0;i<3;i++) if(extras[i]['name']!.text.trim().isNotEmpty) {'name':extras[i]['name']!.text.trim(),'amount_yen':num.tryParse(extras[i]['amount_yen']!.text),'direction':directions[i]}];
        final base=num.tryParse(fields['base_amount_yen']!.text);
        final tax=num.tryParse(fields['tax_amount_yen']!.text);
        if(base==null || tax==null || adjustments.any((a)=>a['amount_yen']==null)) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('金額は数値で入力してください。'))); return; }
        final total=base+adjustments.fold<num>(0,(s,a)=>s+(a['amount_yen'] as num)*(a['direction']=='deduction'?-1:1))+(included?0:tax);
        Navigator.pop(context,<String,dynamic>{'mode':mode,'rounding_rule':rounding,'tax_included':included,for(final e in fields.entries) e.key:e.key.startsWith('period_')?e.value.text:num.tryParse(e.value.text),'adjustments':adjustments,'final_amount_yen':total});
      },child:const Text('提案を保存'))],
    )));
    for(final field in fields.values) { field.dispose(); }
    for(final extra in extras) { for(final field in extra.values) { field.dispose(); } }
    if(result==null || !mounted) return;
    setState(()=>_busy=true);
    try {
      await _client.rpc('propose_site_payment_terms',params:{'p_item':_item,'p_company':_company,'p_expected_revision':_proposals.isEmpty?0:_proposals.first['revision'],'p_terms':result});
      await _load();
    } catch(e) { if(mounted) setState(() { _busy=false;_error=e.toString(); }); }
  }

  Future<void> _preview(Map<String,dynamic> proposal) async {
    final terms=Map<String,dynamic>.from(proposal['terms'] as Map);
    final parent=_workspace!['parent_company_id'].toString();
    final child=_workspace!['child_company_id'].toString();
    // Both confirmations are server-authorized; an equal amount is insufficient.
    final confirmed={for(final c in proposal['confirmations'] as List) (c as Map)['company_id'].toString()};
    if(!confirmed.contains(parent) || !confirmed.contains(child)) return;
    final names=await _client.from('companies').select('id,name').inFilter('id',[parent,child]);
    final byId={for(final row in names) row['id'].toString():row['name'].toString()};
    final lines=<PaymentCertificateLine>[
      PaymentCertificateLine(siteName:_targets.firstWhere((t)=>t['shared_item_id']==_item)['site_name'].toString(),workContent:terms['mode']=='square_meter'?'平米計算':'請け負い',quantityLabel:terms['mode']=='square_meter'?'${terms['area']}㎡':'一式',unitPriceYen:((terms['mode']=='square_meter'?terms['unit_price_yen']:terms['base_amount_yen']) as num).toInt(),amountYen:(terms['base_amount_yen'] as num).toInt()),
      for(final raw in terms['adjustments'] as List)
        PaymentCertificateLine(siteName:'〃',workContent:(raw as Map)['name'].toString(),quantityLabel:'',unitPriceYen:0,amountYen:(raw['amount_yen'] as num).toInt()*(raw['direction']=='deduction'?-1:1)),
      if(terms['tax_included']!=true) PaymentCertificateLine(siteName:'〃',workContent:'消費税',quantityLabel:'',unitPriceYen:0,amountYen:(terms['tax_amount_yen'] as num).toInt()),
    ];
    final total=(terms['final_amount_yen'] as num).toInt();
    if(!mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(builder:(_)=>PaymentCertificatePreviewPage(record:PaymentCertificateRecord(id:'agreement:${proposal['id']}',partnerCompanyName:byId[child]??'',payerCompanyName:byId[parent]??'',payerCompanySealEnabled:false,periodStart:DateTime.parse(terms['period_start'].toString()),periodEnd:DateTime.parse(terms['period_end'].toString()),grossAmount:total,deductions:0,netAmount:total,status:'draft',revision:proposal['revision'] as int,lines:lines))));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar:AppBar(title:const Text('現場別の支払金額調整'),actions:[IconButton(onPressed:()=>showDialog<void>(context:context,builder:(c)=>AlertDialog(title:const Text('金額調整の使い方'),content:const Text('承認済みの親会社・下請け会社の共有現場が対象です。金額提案は履歴に保存し、双方が最新版を確認します。平米・請負では残業などを計算しません。合意済みの最新版のみ同じPDFをプレビュー・印刷・共有できます。'),actions:[TextButton(onPressed:()=>Navigator.pop(c),child:const Text('閉じる'))])),icon:const Icon(Icons.help_outline))]),
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
          for(final extra in (_proposals[i]['terms'] as Map)['adjustments'] as List) Text('${(extra as Map)['name']}：${extra['direction']=='deduction'?'控除':'加算'} ${extra['amount_yen']}円'),
          if(i==0) OutlinedButton(onPressed:()=>_confirm(_proposals[i]),child:const Text('この内訳を確認')),
          if(i==0 && (_proposals[i]['confirmations'] as List).length==2) OutlinedButton(onPressed:()=>_preview(_proposals[i]),child:const Text('合意額の支払証明書')),
        ]))),
      ],
    ]),
  );
}
