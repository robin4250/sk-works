import 'line_release_access.dart';
import '../../domain/rate_formula_settings.dart';
import '../../domain/invoice_engine.dart';
import 'line_historical_amount_preview.dart';
import '../invoices/invoice_pdf_service.dart';
import 'package:flutter/material.dart';
import '../../data/supabase_backend.dart';
import 'line_historical_invoice_model.dart';
import 'line_historical_invoice_repository.dart';
import 'line_historical_invoice_bridge_page.dart';
import 'line_import_page.dart';
import 'line_historical_monthly_import.dart';
import 'line_historical_monthly_import_page.dart';
import 'line_import_repository.dart';
import 'line_saved_monthly_merge_page.dart';
import '../../international/language_controller.dart';

class LineHistoricalInvoicePage extends StatelessWidget {
  const LineHistoricalInvoicePage({super.key, this.initialGroupId, this.initialMonth})
      : editingRates = false, initialSiteId = null;
  const LineHistoricalInvoicePage.rates({super.key, this.initialGroupId, this.initialMonth, this.initialSiteId})
      : editingRates = true;
  final bool editingRates;
  final String? initialGroupId;
  final DateTime? initialMonth;
  final String? initialSiteId;
  @override
  Widget build(BuildContext context) => LineReleaseBoundary(builder: (_) => editingRates ? _LineHistoricalInvoicePageContent.rates(initialGroupId: initialGroupId, initialMonth: initialMonth, initialSiteId: initialSiteId) : _LineHistoricalInvoicePageContent(initialGroupId: initialGroupId, initialMonth: initialMonth));
}

class _LineHistoricalInvoicePageContent extends StatefulWidget {
  const _LineHistoricalInvoicePageContent({this.initialGroupId, this.initialMonth})
      : editingRates = false, initialSiteId = null;
  const _LineHistoricalInvoicePageContent.rates({this.initialGroupId, this.initialMonth, this.initialSiteId})
      : editingRates = true;
  final bool editingRates;
  final String? initialGroupId;
  final DateTime? initialMonth;
  final String? initialSiteId;
  @override
  State<_LineHistoricalInvoicePageContent> createState() => _LineHistoricalInvoicePageState();
}
class _LineHistoricalInvoicePageState extends State<_LineHistoricalInvoicePageContent> {
  final _repository = LineHistoricalInvoiceRepository.maybeCreate();
  final _rates = <String, TextEditingController>{};
  final _siteNames = <String, TextEditingController>{};
  List<Map<String, dynamic>> _groups = [];
  List<LineHistoricalGroup> _summary = [];
  List<Map<String, dynamic>> _candidateRows = [];
  Map<String, dynamic> _data = {};
  Map<String, dynamic>? _pending;
  String? _group, _error;
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month - 1);
  bool _busy = true, _edited = false;
  bool _openedInitialSite = false;
  @override
  void initState() {
    super.initState();
    final month = widget.initialMonth;
    if (month != null) _month = DateTime(month.year, month.month);
    _initialize();
  }
  @override
  void dispose() { for (final c in [..._rates.values, ..._siteNames.values]) { c.dispose(); } super.dispose(); }
  Future<void> _initialize() async {
    if (_repository == null) { setState(() { _busy = false; _error = 'Masterでログインしてください。'; }); return; }
    try {
      final master = await SupabaseBackend.client.rpc('is_current_user_master_admin');
      if (master != true) throw StateError('Master required');
      final groups = await LineImportRepository.maybeCreate()!.destinations();
      if (!mounted) return;
      _groups = groups.where((x) => x['group_type'] != 'direct').toList();
      final initial = widget.initialGroupId;
      _group = _groups.any((g) => g['id'].toString() == initial)
          ? initial : _groups.isEmpty ? null : _groups.first['id'].toString();
      await _load();
    } catch (_) { if (mounted) setState(() { _busy = false; _error = 'Master権限と接続を確認してください。'; }); }
  }
  Future<void> _load() async {
    if (_group == null) { setState(() => _busy = false); return; }
    setState(() { _busy = true; _error = null; _data = {}; _summary = []; _candidateRows = []; });
    try {
      final workspace = await LineImportRepository.maybeCreate()!.load(_group!, 'invoice', _month);
      if (workspace['can_edit'] != true || !LineImportFeatures.fromJson(workspace['features']).invoice) {
        throw StateError('請求書取込の権限とON設定を確認してください。');
      }
      final candidates = [for (final row in workspace['candidate_rows'] as List)
        Map<String, dynamic>.from(row as Map)];
      final now = DateTime.now();
      final data = _month.isBefore(DateTime(now.year, now.month))
        ? await _repository!.load(_group!, _month)
        : <String, dynamic>{'rows': <Map<String, dynamic>>[], 'saved': <Map<String, dynamic>>[]};
      final rows = [for (final row in data['rows'] as List) Map<String, dynamic>.from(row as Map)];
      final summary = historicalGroups(rows);
      if (!mounted) return;
      for (final c in [..._rates.values, ..._siteNames.values]) { c.dispose(); }
      _rates.clear(); _siteNames.clear();
      final saved = data['saved'] as List? ?? [];
      final snapshot = saved.isEmpty ? <String, dynamic>{}
          : Map<String, dynamic>.from(saved.first['snapshot'] as Map);
      final lines = snapshot['lines'] as List? ?? [];
      for (final group in summary) {
        _siteNames.putIfAbsent(group.siteId, () => TextEditingController(
          text: lineHistoricalFormalSiteName(snapshot, group.siteId) ?? _formalName(rows, group)));
        final matching = lines.where((line) => line['site_id'] == group.siteId &&
          line['work_category'] == group.category).toList();
        if (matching.length != 1 || matching.single['rates'] is! Map) continue;
        final rates = matching.single['rates'] as Map;
        for (final unit in ['day', 'overtime', 'early', ...<String>{'PC手当', '鉄骨手当', ...group.allowances.keys}.map((name) => 'allowance:$name')]) {
          final allowances = rates['allowances'];
          final value = unit.startsWith('allowance:')
              ? (allowances is Map ? allowances[unit.substring(10)] : null)
              : rates[unit];
          if (value is num && value.isFinite && value == value.truncateToDouble() &&
              historicalUnitRate(value.toInt().toString()) != null) {
            _rates[_key(group, unit)] = TextEditingController(text: value.toInt().toString());
          }
        }
      }
      setState(() { _data = data; _summary = summary; _candidateRows = candidates; _pending = null; _edited = false; });
    } catch (_) { if (mounted) setState(() => _error = '確認済み過去月データを取得できませんでした。権限・接続・元データを確認してください。'); }
    finally { if (mounted) setState(() => _busy = false); }
    final site = widget.initialSiteId;
    if (mounted && !_openedInitialSite && site != null && _siteNames.containsKey(site)) {
      _openedInitialSite = true;
      await _openSiteRates(site);
    }
  }
  String _key(LineHistoricalGroup g, String unit) => '${g.siteId}:${g.category}:$unit';
  TextEditingController _controller(LineHistoricalGroup g, String unit) => _rates.putIfAbsent(_key(g, unit), () => TextEditingController(text: unit == 'day' ? lineHistoricalDefaultDayRate(g.category).toString() : unit == 'overtime' || unit == 'early' ? const RateFormulaSettings().overtime(_rate(g, 'day') ?? 32800).toString() : unit == 'allowance:PC' || unit == 'allowance:PC手当' || unit == 'allowance:鉄骨' || unit == 'allowance:鉄骨手当' ? '3000' : ''));
  int? _rate(LineHistoricalGroup g, String unit) => historicalUnitRate(_controller(g, unit).text);
  List<InvoiceLine> _invoiceLines(LineHistoricalGroup g) => [
    InvoiceLine(label: '作業（${g.category}）', quantity: g.manDays, unitPriceYen: _rate(g, 'day')!),
    if (g.overtime > 0) InvoiceLine(label: '残業', quantity: g.overtime, unitPriceYen: _rate(g, 'overtime')!),
    if (g.early > 0) InvoiceLine(label: '早出', quantity: g.early, unitPriceYen: _rate(g, 'early')!),
    for (final entry in g.allowances.entries) InvoiceLine(label: entry.key, quantity: entry.value.toDouble(), unitPriceYen: _rate(g, 'allowance:${entry.key}')!),
  ];
  int? _subtotal(LineHistoricalGroup g) {
    final day = _rate(g, 'day'), ot = _rate(g, 'overtime'), early = _rate(g, 'early');
    if (day == null || (g.overtime > 0 && ot == null) || (g.early > 0 && early == null)) return null;
    for (final entry in g.allowances.entries) {
      final rate = _rate(g, 'allowance:${entry.key}');
      if (rate == null) return null;
    }
    return _invoiceLines(g).fold<int>(0, (sum, line) => sum + line.amountYen);
  }
  Future<void> _save() async {
    if (!widget.editingRates) return;
    if (_pending == null) {
      if (_summary.isEmpty || _summary.any((g) => _subtotal(g) == null ||
          _siteNames[g.siteId]!.text.trim().isEmpty || _siteNames[g.siteId]!.text.trim().length > 200)) {
        setState(() => _error = '現場の正式名称と実数量のある項目の単価を入力してください。空欄を0円として保存しません。'); return;
      }
      final rates = [for (final g in _summary) <String, dynamic>{
        'site_id': g.siteId, 'site_name': _siteNames[g.siteId]!.text.trim(),
        'work_category': g.category, 'day': _rate(g, 'day'),
        'overtime': _rate(g, 'overtime'), 'early': _rate(g, 'early'),
        'allowances': {for (final name in <String>{'PC手当', '鉄骨手当', ...g.allowances.keys}) name: _rate(g, 'allowance:$name')},
      }];
      _pending = _repository!.command(_group!, _month, _data, rates);
    }
    setState(() { _busy = true; _error = null; });
    try {
      await _repository!.save(_pending!);
      if (!mounted) return;
      await _load();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('履歴小計を保存しました。通常請求書は発行していません。')));
    } catch (_) {
      if (mounted) setState(() => _error = '保存を確認できませんでした。同じ内容で再送するか、再読み込みして元データを確認してください。');
    } finally { if (mounted) setState(() => _busy = false); }
  }
  Future<void> _reload() async {
    if (_edited || _pending != null) {
      final yes = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
        title: const Text('保存データを再読み込み'), content: const Text('入力中の単価を閉じて、保存済みの元データと履歴を確認します。'),
        actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('戻る')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('再読み込み'))]));
      if (yes != true || !mounted) return;
    }
    await _load();
  }
  Future<void> _chooseMonth() async {
    final now = DateTime.now();
    final date = await showDatePicker(context: context, initialDate: _month,
      firstDate: DateTime(1900), lastDate: DateTime(now.year, now.month + 1, 0));
    if (date == null || !mounted) return;
    setState(() => _month = DateTime(date.year, date.month));
    await _load();
  }
  String _tr(String text) => SkoLanguageController.tr(text);
  Future<void> _openRates() async {
    await Navigator.of(context).push<void>(MaterialPageRoute(builder: (_) =>
      LineHistoricalInvoicePage.rates(initialGroupId: _group, initialMonth: _month)));
    if (mounted) await _load();
  }
  Future<void> _openImport() async {
    await Navigator.of(context).push<void>(MaterialPageRoute(builder: (_) =>
      LineImportPage(target: 'invoice', initialGroupId: _group, initialMonth: _month)));
    if (mounted) await _load();
  }
  Future<void> _openMonthlyImport() async {
    final group = _group;
    if (group == null) return;
    await Navigator.of(context).push<void>(MaterialPageRoute(builder: (_) =>
      LineHistoricalMonthlyImportPage(groupId: group)));
    if (mounted) await _load();
  }
  Future<void> _openSavedMonthlyMerge() async {
    final group = _group;
    if (_busy || _edited || _pending != null || group == null) return;
    final names = _groups.where((item) => item['id'].toString() == group).toList();
    if (names.length != 1) return;
    final name = names.single['display_name']?.toString() ??
      names.single['name']?.toString() ?? '選択中のグループ';
    final saved = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) =>
      LineSavedMonthlyMergePage(groupId: group, groupName: name, month: _month)));
    if (mounted && saved == true) await _load();
  }
  String _formalName(List<Map<String, dynamic>> rows, LineHistoricalGroup group) {
    final names = rows.where((row) => row['site_id'] == group.siteId)
      .map((row) => row['formal_site_name']?.toString().trim() ?? '')
      .where((name) => name.isNotEmpty).toSet();
    return names.length == 1 ? names.single : group.siteName;
  }

  Future<void> _openSiteRates(String siteId) async {
    await Navigator.of(context).push<void>(MaterialPageRoute(builder: (_) =>
      StatefulBuilder(builder: (context, refresh) => Scaffold(
        appBar: AppBar(title: const Text('現場別単価設定')),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          TextField(controller: _siteNames[siteId], maxLength: 200,
            decoration: const InputDecoration(labelText: '正式現場名（請求書へ表示）'),
            onChanged: (_) => _edited = true),
          for (final g in _summary.where((g) => g.siteId == siteId)) ...[
            Text('${g.siteName} ／ ${g.category}'),
            TextField(controller: _controller(g, 'day'), keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: '1日単価（円）'),
              onChanged: (_) {
                final day = _rate(g, 'day');
                _controller(g, 'overtime').text = day == null ? '' : const RateFormulaSettings().overtime(day).toString();
                setState(() => _edited = true);
                refresh(() {});
              }),
            TextField(controller: _controller(g, 'overtime'), readOnly: true,
              decoration: const InputDecoration(labelText: '残業単価（円／時間・自動計算）', helperText: '1日単価 ÷ 8 × 1.25')),
            if (g.early > 0) _field(g, 'early', '早出単価（円／時間）', '${g.early}時間 × 単価'),
            for (final a in <String, int>{'PC手当': 0, '鉄骨手当': 0, ...g.allowances}.entries)
              _field(g, 'allowance:${a.key}', '${a.key}（円／日）', '${a.value}日 × 単価'),
            const SizedBox(height: 16),
          ],
          FilledButton(onPressed: () => Navigator.pop(context), child: const Text('入力を反映して現場一覧へ')),
          const Text('一覧の「履歴小計を保存」で、この月の各現場の設定を保存します。'),
        ])))));
    if (mounted) setState(() {});
  }

  Widget _field(LineHistoricalGroup g, String unit, String label, String formula) => Padding(
    padding: const EdgeInsets.only(top: 8), child: TextField(controller: _controller(g, unit),
      enabled: !_busy && _pending == null, keyboardType: TextInputType.number,
      decoration: InputDecoration(labelText: label, helperText: formula, border: const OutlineInputBorder()),
      onChanged: (_) => setState(() => _edited = true)));
  @override
  Widget build(BuildContext context) {
    final people = <String>{for (final g in _summary) ...g.workers}.length;
    final days = _summary.fold<double>(0, (n, g) => n + g.manDays);
    final saved = _data['saved'] as List? ?? [];
    final candidateEstimate = lineHistoricalAmountPreview(_candidateRows);
    final bases = <String, int>{};
    var complete = _summary.isNotEmpty;
    for (final group in _summary) {
      final amount = _subtotal(group);
      if (amount == null) { complete = false; continue; }
      bases[group.siteId] = (bases[group.siteId] ?? 0) + amount;
    }
    final siteCalculations = complete ? [for (final site in bases.keys) SiteInvoiceCalculation(
      siteId: site, siteName: _siteNames[site]!.text,
      lines: [for (final group in _summary.where((g) => g.siteId == site)) ..._invoiceLines(group)],
      welfareRateBps: 1500,
    )] : <SiteInvoiceCalculation>[];
    final reference = complete ? InvoiceEngine.calculate(
      customerId: '取引先未確認（参考）', billingPeriod: '${_month.year}年${_month.month}月',
      detailMode: InvoiceDetailMode.siteBreakdownOnInvoice, sites: siteCalculations,
      taxRateBps: 1000, invoiceNumber: '参考・未確認',
      taxYenOverride: siteCalculations.fold<int>(0, (sum, site) => sum +
        InvoiceEngine.calculate(customerId: '参考', billingPeriod: '参考',
          detailMode: InvoiceDetailMode.siteBreakdownOnInvoice, sites: [site], taxRateBps: 1000).taxYen),
    ) : null;
    return Scaffold(appBar: AppBar(title: Text(_tr(widget.editingRates ? 'LINE単価設定' : 'LINE月別請求書')), actions: [
      IconButton(onPressed: () => showDialog<void>(context: context, builder: (context) => AlertDialog(title: const Text('履歴小計'), content: const Text('取込済みの未確認数量でも指定初期単価の参考金額を表示し、既存SKO請求書の書式で確認できます。残業・早出だけの報告は1人工を仮置きと明示し、確認済みにはしません。現場別単価は確認済みの表から編集でき、保存済み帳票の金額は変更しません。過去33ヶ月と当月までの追加月を、書き出しファイルと連携LINEの受信データから同じ月別候補へ取り込めます。通常は既存履歴を残して不足分を追加し、一致するコピーをまとめます。各月の確認済み表から単価設定へ進み、正式現場名・1日単価・残業・手当を保存して、正式下書きへ引き継ぎます。同月の直近保存単価を表示し、変更して別の履歴として保存できます。実人数は重複を除いた人数、延べ人工は各日の人工の合計です。過去月の確認済み候補へ単価を入力して保存します。空欄は未取得、0円は明示入力として扱います。保存は通常請求書の発行とは別です。'), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('閉じる'))])), icon: const Icon(Icons.help_outline), tooltip: 'ヘルプ'),
      IconButton(onPressed: _busy ? null : _reload, icon: const Icon(Icons.refresh), tooltip: '再読み込み')]),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Text(_tr(widget.editingRates
          ? '確認済みの過去月候補へ単価を入力し、履歴小計として保存します。空欄は0円にしません。現在の現場単価・給与は変更しません。'
          : '対象月の確認済み候補と保存した履歴小計を確認します。単価は「単価設定」で入力します。正式下書きは保存履歴から開きます。')),
        if (!widget.editingRates) Padding(
          padding: const EdgeInsets.only(top: 12),
          child: OutlinedButton.icon(onPressed: _busy || _group == null ? null : _openMonthlyImport,
            icon: const Icon(Icons.table_view_outlined),
            label: const Text('月別表・ファイル取込と受信データ'))),
        if (!widget.editingRates) Padding(
          padding: const EdgeInsets.only(top: 12),
          child: OutlinedButton.icon(onPressed: _busy || _edited || _pending != null || _group == null
              ? null : _openSavedMonthlyMerge,
            icon: const Icon(Icons.playlist_add_outlined),
            label: const Text('保存済みデータを追加'))),
        if (!widget.editingRates) Padding(
          padding: const EdgeInsets.only(top: 12),
          child: OutlinedButton.icon(onPressed: _busy ? null : _openImport,
            icon: const Icon(Icons.fact_check_outlined),
            label: Text(_tr('LINE請求候補を確認・取込')))),
        if (!widget.editingRates) Padding(
          padding: const EdgeInsets.only(top: 8),
          child: OutlinedButton.icon(onPressed: _busy || _group == null ? null : _openRates,
            icon: const Icon(Icons.price_change_outlined),
            label: Text(_tr('この月の単価設定')))),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(initialValue: _group, isExpanded: true, decoration: const InputDecoration(labelText: 'LINEグループ'),
          items: [for (final g in _groups) DropdownMenuItem(value: g['id'].toString(), child: Text(g['display_name']?.toString() ?? g['name'].toString(), maxLines: 1, overflow: TextOverflow.ellipsis))],
          onChanged: _busy || _edited || _pending != null ? null : (value) { setState(() => _group = value); _load(); }),
        OutlinedButton.icon(onPressed: _busy || _edited || _pending != null ? null : _chooseMonth,
          icon: const Icon(Icons.calendar_month), label: Text('${_month.year}年${_month.month}月')),
        if (_busy) const LinearProgressIndicator(),
        if (_error != null) Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
        if (_data.isNotEmpty) Text('実人数 $people人 ／ 延べ ${days.toStringAsFixed(1)}人工', style: Theme.of(context).textTheme.titleMedium),
        if (_data.isNotEmpty && !widget.editingRates) Card(child: ExpansionTile(
          title: const Text('読取参考額の計算対象を確認'),
          subtitle: Text(candidateEstimate.workDates.isEmpty ? '計算対象日なし' :
            '${candidateEstimate.workDates.first} 〜 ${candidateEstimate.workDates.last}'),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          expandedAlignment: Alignment.centerLeft,
          children: [
            Text('対象日：${candidateEstimate.workDates.isEmpty ? 'なし' : candidateEstimate.workDates.join('、')}'),
            Text('計算対象 ${candidateEstimate.includedRows}件 ／ 除外 ${_candidateRows.where((row) => row['excluded'] == true).length}件'),
            Text('要確認 ${candidateEstimate.pendingRows}件 ／ 計算対象外 ${candidateEstimate.incompleteRows}件'),
            const Text('本文の出勤日で対象月を判定します。月末で受信を打ち切らず、後日分も同じ月別表へ追加できます。正式請求書は自動発行・送信しません。'),
          ],
        )),
        if (_data.isNotEmpty && !widget.editingRates && _candidateRows.isNotEmpty) Card(child: Padding(
          padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(candidateEstimate.sites.isEmpty ? '請求金額：数量の確認が必要です' : '現在の読取数量による参考請求額 ${candidateEstimate.total}円', style: Theme.of(context).textTheme.titleLarge),
            Text('未確認 ${candidateEstimate.pendingRows}行 ／ 計算対象外 ${candidateEstimate.incompleteRows}行。指定初期単価・福利15%・消費税10%。全件確定額ではありません。'),
            Text('残業・早出報告から1人工を仮置き ${_candidateRows.where((row) => row['excluded'] != true && row['man_days_inferred'] == true).length}行。半日・訂正・未振り分けの原文も月別表で確認してください。'),
            const Text('数量・正式現場名は月別表で修正できます。現場別変更単価と登録経費は確認後の正式下書きプレビューへ反映します。'),
            OutlinedButton.icon(onPressed: _busy || candidateEstimate.sites.isEmpty ? null : () => Navigator.of(context).push<void>(
              MaterialPageRoute(builder: (_) => InvoicePdfPreviewPage(invoices: [candidateEstimate.invoice(_month)], title: 'SKO請求書・参考／未確認'))),
              icon: const Icon(Icons.picture_as_pdf_outlined), label: const Text('SKO請求書の書式で読取金額を確認')),
          ]))),
        if (_data.isNotEmpty && complete) Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(
          crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('入力単価による参考請求額 ${reference?.grandTotalYen}円', style: Theme.of(context).textTheme.titleLarge),
            const Text('現場別の入力単価＋福利15%＋消費税10%。登録経費は含みません。正式下書きの金額プレビューで対象月の条件と経費を確認してください。'),
            for (final entry in bases.entries) Text('${_siteNames[entry.key]?.text ?? entry.key}：作業・手当小計 ${entry.value}円'),
            OutlinedButton.icon(onPressed: _busy || reference == null ? null : () => Navigator.of(context).push<void>(
              MaterialPageRoute(builder: (_) => InvoicePdfPreviewPage(invoices: [reference], title: 'SKO請求書・参考／未確認'))),
              icon: const Icon(Icons.picture_as_pdf_outlined), label: const Text('SKO請求書の書式で金額を確認')),
          ]))),
        if (!_busy && _error == null && _data.isNotEmpty && _summary.isEmpty) Text(_tr('確認済みの請求候補がありません。LINE請求候補を取り込み、照合して保存してください。')),
        if (!_busy && _error == null && _groups.isEmpty) Text(_tr('表示できるLINEグループがありません。連携状態を確認してください。')),
        if (widget.editingRates) for (final entry in _siteNames.entries)
          Card(child: ListTile(title: Text(entry.value.text),
            subtitle: const Text('正式現場名・1日単価・残業自動計算・手当単価'),
            trailing: const Icon(Icons.chevron_right),
            onTap: _busy || _pending != null ? null : () => _openSiteRates(entry.key))),
        if (!widget.editingRates) for (final g in _summary)
          Card(child: ListTile(title: Text('${_siteNames[g.siteId]?.text ?? g.siteName} ／ ${g.category}'),
            subtitle: Text('実人数 ${g.workers.length}人 ／ 延べ ${g.manDays}人工\n残業 ${g.overtime}時間 ／ 早出 ${g.early}時間\n作業・手当小計 ${_subtotal(g)?.toString() ?? '単価を確認'}円'))),
        if (widget.editingRates) FilledButton(onPressed: _busy || _summary.isEmpty ? null : _save,
          child: Text(_pending == null ? '履歴小計を保存' : '同じ保存を再送')),
        const SizedBox(height: 20), const Text('保存済み履歴（現在単価で再計算しません）'),
        for (final raw in saved) ExpansionTile(title: Text('保存 ${raw['created_at']}'), children: [
          ListTile(title: Text('小計 ${raw['snapshot']['subtotal']}円'),
            subtitle: Text('対象月 ${raw['snapshot']['month']} ／ 実人数 ${raw['snapshot']['people']}人 ／ 延べ ${raw['snapshot']['man_days']}人工\n通常請求書は未発行')),
          OutlinedButton.icon(onPressed: _busy ? null : () => Navigator.of(context).push<void>(MaterialPageRoute(builder: (_) => LineHistoricalInvoiceBridgePage(quoteId: raw['id'].toString()))), icon: const Icon(Icons.receipt_long_outlined), label: const Text('正式請求の下書きへ')),
        ]),
      ]));
  }
}


