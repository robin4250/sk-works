import 'line_release_access.dart';
import 'package:flutter/material.dart';
import '../invoices/invoice_cloud_page.dart';
import 'line_historical_invoice_bridge_model.dart';
import 'line_historical_invoice_bridge_repository.dart';
import 'line_historical_monthly_import.dart';

class LineHistoricalInvoiceBridgePage extends StatelessWidget {
  const LineHistoricalInvoiceBridgePage({super.key, required this.quoteId});
  final String quoteId;
  @override
  Widget build(BuildContext context) => LineReleaseBoundary(builder: (_) => _LineHistoricalInvoiceBridgePageContent(quoteId: quoteId));
}

class _LineHistoricalInvoiceBridgePageContent extends StatefulWidget {
  const _LineHistoricalInvoiceBridgePageContent({required this.quoteId});
  final String quoteId;
  @override
  State<_LineHistoricalInvoiceBridgePageContent> createState() => _LineHistoricalInvoiceBridgePageState();
}
class _LineHistoricalInvoiceBridgePageState extends State<_LineHistoricalInvoiceBridgePageContent> {
  final _repository = LineHistoricalInvoiceBridgeRepository.maybeCreate();
  final _tax = TextEditingController(text: '10');
  final _names = <String, TextEditingController>{};
  final _welfare = <String, TextEditingController>{};
  final _customers = <String, String>{};
  Map<String, dynamic> _data = {};
  Map<String, dynamic>? _preview, _previewParams, _pending, _created;
  List<String> _sites = [];
  bool _busy = true, _termsConfirmed = false, _previewConfirmed = false, _edited = false;
  String? _error;
  int _formVersion = 0;
  @override
  void initState() { super.initState(); _load(); }
  @override
  void dispose() { _tax.dispose(); for (final c in [..._names.values, ..._welfare.values]) { c.dispose(); } super.dispose(); }
  Future<void> _load() async {
    if (_repository == null) { setState(() { _busy = false; _error = 'Masterでログインしてください。'; }); return; }
    setState(() { _busy = true; _error = null; });
    try {
      final data = await _repository.load(widget.quoteId);
      final quote = Map<String, dynamic>.from(data['quote'] as Map);
      final sites = <String>{for (final line in quote['lines'] as List) line['site_id'].toString()}.toList();
      if (!mounted) return;
      for (final c in [..._names.values, ..._welfare.values]) { c.dispose(); }
      _names.clear(); _welfare.clear(); _customers.clear(); _tax.clear();
      final rows = quote['rows'] as List;
      for (final site in sites) {
        final matches = rows.where((r) => r['site_id'] == site).toList();
        final row = matches.isEmpty ? null : matches.first;
        _names[site] = TextEditingController(text: lineHistoricalFormalSiteName(quote, site) ?? row?['site_name']?.toString() ?? '');
        _welfare[site] = TextEditingController(text: '15');
      }
      setState(() { _formVersion++; _data = data; _sites = sites; _preview = null; _previewParams = null; _pending = null; _created = null; _termsConfirmed = false; _previewConfirmed = false; _edited = false; });
    } catch (_) { if (mounted) setState(() => _error = '保存済み履歴・Master権限・接続を確認してください。'); }
    finally { if (mounted) setState(() => _busy = false); }
  }
  void _changed() => setState(() { _edited = true; _preview = null; _previewParams = null; _previewConfirmed = false; });
  Map<String, dynamic>? _params() {
    final tax = historicalPercentBps(_tax.text);
    if (tax == null || !_termsConfirmed || _sites.isEmpty) return null;
    final terms = <Map<String, dynamic>>[];
    for (final site in _sites) {
      final welfare = historicalPercentBps(_welfare[site]!.text);
      final name = _names[site]!.text.trim();
      if (welfare == null || name.isEmpty || !_customers.containsKey(site)) return null;
      terms.add({'site_id': site, 'customer_id': _customers[site], 'site_name': name, 'welfare_rate_bps': welfare});
    }
    return {'p_quote_id': widget.quoteId, 'p_quote_fingerprint': _data['quote_fingerprint'], 'p_site_terms': terms, 'p_tax_rate_bps': tax, 'p_terms_confirmed': true};
  }
  Future<void> _showPreview() async {
    final params = _params();
    if (params == null) { setState(() => _error = '過去の取引先・現場名・税率・福利率を明示し、対象月の契約と照合してください。'); return; }
    setState(() { _busy = true; _error = null; _preview = null; _previewConfirmed = false; });
    try {
      final preview = await _repository!.preview(params);
      if (preview['quote_id'] != widget.quoteId || preview['fingerprint'] is! String || preview['quotes'] is! List || preview['status'] != 'draft') throw StateError('Preview mismatch');
      if (mounted) setState(() { _preview = preview; _previewParams = params; });
    } catch (_) { if (mounted) setState(() => _error = '金額を確認できませんでした。元履歴・取引先・登録経費を再確認してください。'); }
    finally { if (mounted) setState(() => _busy = false); }
  }
  Future<void> _create() async {
    if (_pending == null) {
      if (_preview == null || _previewParams == null || !_previewConfirmed) return;
      _pending = _repository!.command(_previewParams!, _preview!['fingerprint'] as String);
    }
    setState(() { _busy = true; _error = null; });
    try {
      final result = await _repository!.create(_pending!);
      if (result['invoices'] is! List || result['status'] != 'draft' || result['issued'] != false || result['approved'] != false) throw StateError('Result mismatch');
      if (mounted) setState(() { _created = result; _pending = null; _edited = false; });
    } catch (_) { if (mounted) setState(() => _error = '作成結果を確認できませんでした。同じ作成を再送するか、再読み込みしてください。設定・経費変更時はプレビューをやり直してください。'); }
    finally { if (mounted) setState(() => _busy = false); }
  }
  Future<void> _refreshExpenses(String invoiceId) async {
    setState(() { _busy = true; _error = null; });
    try {
      final preview = await _repository!.expensePreview(widget.quoteId, invoiceId);
      if (preview['invoice_id'] != invoiceId || preview['quote_id'] != widget.quoteId || preview['fingerprint'] is! String || preview['expense_extra_claims'] is! List) throw StateError('Expense preview mismatch');
      if (!mounted) return;
      final confirmed = await showDialog<bool>(context: context, builder: (dialogContext) => AlertDialog(
        title: const Text('登録経費の更新を確認'),
        content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${preview['customer_name']}\n前回の登録経費 ${preview['previous_expense_amount_yen']}円 → ${preview['expense_extra_amount_yen']}円\n更新後の合計 ${preview['grand_total']}円'),
          const Text('保存した人工・単価・消費税・法定福利費は変わりません。'),
          for (final claim in preview['expense_extra_claims'] as List) Text('${claim['incurred_on']} ${claim['description']} ${claim['amount_yen']}円'),
        ])), actions: [TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('戻る')), FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('確認して経費を更新'))]));
      if (confirmed != true || !mounted) return;
      final result = await _repository.refreshExpenses(widget.quoteId, invoiceId, preview['fingerprint'] as String);
      if (result['invoice_id'] != invoiceId || result['quote_id'] != widget.quoteId) throw StateError('Expense update mismatch');
      await _load();
    } catch (_) { if (mounted) setState(() => _error = '経費を更新できませんでした。承認済み・確定済み・手動編集済みの請求書は変更しません。再読み込みして内容を確認してください。'); }
    finally { if (mounted) setState(() => _busy = false); }
  }
  Future<void> _reload() async {
    if (_edited || _pending != null) {
      final yes = await showDialog<bool>(context: context, builder: (context) => AlertDialog(title: const Text('保存済み状態を再確認'), content: const Text('入力・プレビューを閉じて、作成済み下書きと履歴を再読み込みします。'), actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('戻る')), TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('再読み込み'))]));
      if (yes != true || !mounted) return;
    }
    await _load();
  }
  @override
  Widget build(BuildContext context) {
    final quote = _data['quote'] as Map?;
    final registered = _data['customers'] as List? ?? [];
    final previous = _data['created_invoices'] as List? ?? [];
    final locked = _busy || _pending != null || _created != null || previous.isNotEmpty;
    final results = _created?['invoices'] as List? ?? previous;
    return Scaffold(appBar: AppBar(title: const Text('履歴から正式請求の下書き'), actions: [
      IconButton(onPressed: () => showDialog<void>(context: context, builder: (context) => AlertDialog(title: const Text('履歴と正式下書き'), content: const Text('保存時の数量と単価を使用します。過去の取引先・現場名・税福利条件を明示し、登録済み対象月経費を含む金額を確認してから下書きを作成します。作成後の登録経費変更は、この画面から金額を確認して更新できます。承認済み・確定済み・手動編集済みの下書きは変更しません。承認と発行は既存の請求書画面で行います。'), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('閉じる'))])), icon: const Icon(Icons.help_outline), tooltip: 'ヘルプ'),
      IconButton(onPressed: _busy ? null : _reload, icon: const Icon(Icons.refresh), tooltip: '再読み込み')]),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        const Text('Master専用。保存済みの数量・単価で正式請求書の下書きを作成します。過去月の条件を入力し、金額と登録経費を確認してください。'),
        if (quote != null) Text('対象月 ${quote['month']} ／ 実人数 ${quote['people']}人 ／ 延べ ${quote['man_days']}人工\n保存時の小計 ${quote['subtotal']}円'),
        if (_busy) const LinearProgressIndicator(),
        if (_error != null) Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
        TextField(controller: _tax, enabled: !locked, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: '対象月の消費税率（%）', helperText: '空欄は未設定。0%も明示入力してください。'), onChanged: (_) => _changed()),
        for (final site in _sites) Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(children: [
          TextField(controller: _names[site], enabled: !locked, decoration: const InputDecoration(labelText: '履歴現場名（正式下書きへ表示）'), onChanged: (_) => _changed()),
          DropdownButtonFormField<String>(key: ValueKey('$_formVersion:$site'), initialValue: _customers[site], isExpanded: true, decoration: const InputDecoration(labelText: '過去の取引先（明示指定）'), items: [for (final customer in registered) DropdownMenuItem(value: customer['id'].toString(), child: Text(customer['name'].toString(), overflow: TextOverflow.ellipsis))], onChanged: locked ? null : (value) { if (value != null) _customers[site] = value; _changed(); }),
          TextField(controller: _welfare[site], enabled: !locked, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: '対象月の法定福利費率（%）', helperText: '保存小計に対する率。空欄を0%にしません。'), onChanged: (_) => _changed()),
        ]))),
        CheckboxListTile(value: _termsConfirmed, onChanged: locked ? null : (value) { _termsConfirmed = value == true; _changed(); }, title: const Text('取引先・現場名・税福利条件を対象月の契約と照合済み')),
        OutlinedButton(onPressed: locked ? null : _showPreview, child: const Text('正式下書きの金額をプレビュー')),
        if (_preview != null) ...[
          for (final invoice in _preview!['quotes'] as List) ExpansionTile(initiallyExpanded: true, title: Text(invoice['customer_name'].toString()), subtitle: Text('税込合計 ${invoice['grand_total']}円'), children: [
            ListTile(title: Text('小計 ${invoice['subtotal']}円（福利 ${invoice['welfare']}円含む）\n税 ${invoice['tax']}円 ／ 登録経費 ${invoice['expense_extra_amount_yen']}円'), subtitle: Text(invoice['customer_address'].toString())),
            for (final site in invoice['sites'] as List) for (final line in site['lines'] as List) ListTile(dense: true, title: Text('${site['site_name']}：${line['work_content']}'), subtitle: Text('${line['quantity']} × ${line['unit_price']}円'), trailing: Text('${line['amount']}円')),
            for (final expense in invoice['expense_extra_claims'] as List) ListTile(dense: true, title: Text('登録経費 ${expense['description']}'), subtitle: Text('${expense['incurred_on']}'), trailing: Text('${expense['amount_yen']}円')),
          ]),
          CheckboxListTile(value: _previewConfirmed, onChanged: locked ? null : (value) => setState(() => _previewConfirmed = value == true), title: const Text('表示された取引先・金額・登録経費を確認しました')),
          FilledButton(onPressed: _busy || _created != null || previous.isNotEmpty || (!_previewConfirmed && _pending == null) ? null : _create, child: Text(_pending == null ? '正式請求書の下書きを作成' : '同じ作成を再送')),
        ],
        if (results.isNotEmpty) ...[const SizedBox(height: 16), const Text('正式請求書への作成記録。請求書画面で状態を確認してください。'), for (final invoice in results) ListTile(title: Text(invoice['customer_name']?.toString() ?? '作成記録'), subtitle: Text(invoice['invoice_exists'] == false ? '請求書を確認できません。作成記録は保持しています。' : '${invoice['work_month']} ／ 合計 ${invoice['grand_total']}円'), trailing: OutlinedButton(onPressed: invoice['invoice_exists'] == false ? null : () => Navigator.of(context).push<void>(MaterialPageRoute(builder: (_) => InvoiceCloudPage(initialInvoiceId: invoice['invoice_id'].toString()))), child: const Text('請求書を確認'))), for (final invoice in results) OutlinedButton(onPressed: _busy || invoice['invoice_exists'] == false ? null : () => _refreshExpenses(invoice['invoice_id'].toString()), child: Text('${invoice['customer_name'] ?? '作成記録'}：登録経費を確認・更新'))],
      ]));
  }
}

