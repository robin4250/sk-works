import 'package:flutter/material.dart';
import '../../data/supabase_backend.dart';
import 'chat_cloud_repository.dart';
import 'line_historical_invoice_model.dart';
import 'line_historical_invoice_repository.dart';

class LineHistoricalInvoicePage extends StatefulWidget {
  const LineHistoricalInvoicePage({super.key});
  @override
  State<LineHistoricalInvoicePage> createState() => _LineHistoricalInvoicePageState();
}
class _LineHistoricalInvoicePageState extends State<LineHistoricalInvoicePage> {
  final _repository = LineHistoricalInvoiceRepository.maybeCreate();
  final _rates = <String, TextEditingController>{};
  List<Map<String, dynamic>> _groups = [];
  List<LineHistoricalGroup> _summary = [];
  Map<String, dynamic> _data = {};
  Map<String, dynamic>? _pending;
  String? _group, _error;
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month - 1);
  bool _busy = true, _edited = false;
  @override
  void initState() { super.initState(); _initialize(); }
  @override
  void dispose() { for (final c in _rates.values) { c.dispose(); } super.dispose(); }
  Future<void> _initialize() async {
    if (_repository == null) { setState(() { _busy = false; _error = 'Masterでログインしてください。'; }); return; }
    try {
      final master = await SupabaseBackend.client.rpc('is_current_user_master_admin');
      if (master != true) throw StateError('Master required');
      final groups = await ChatCloudRepository.maybeCreate()!.loadGroups();
      if (!mounted) return;
      _groups = groups.where((x) => x['group_type'] != 'direct').toList();
      _group = _groups.isEmpty ? null : _groups.first['id'].toString();
      await _load();
    } catch (_) { if (mounted) setState(() { _busy = false; _error = 'Master権限と接続を確認してください。'; }); }
  }
  Future<void> _load() async {
    if (_group == null) { setState(() => _busy = false); return; }
    setState(() { _busy = true; _error = null; _data = {}; _summary = []; });
    try {
      final data = await _repository!.load(_group!, _month);
      final rows = [for (final row in data['rows'] as List) Map<String, dynamic>.from(row as Map)];
      final summary = historicalGroups(rows);
      if (!mounted) return;
      for (final c in _rates.values) { c.dispose(); }
      _rates.clear();
      setState(() { _data = data; _summary = summary; _pending = null; _edited = false; });
    } catch (_) { if (mounted) setState(() => _error = '確認済み過去月データを取得できませんでした。権限・接続・元データを確認してください。'); }
    finally { if (mounted) setState(() => _busy = false); }
  }
  String _key(LineHistoricalGroup g, String unit) => '${g.siteId}:${g.category}:$unit';
  TextEditingController _controller(LineHistoricalGroup g, String unit) => _rates.putIfAbsent(_key(g, unit), TextEditingController.new);
  int? _rate(LineHistoricalGroup g, String unit) => historicalUnitRate(_controller(g, unit).text);
  int? _subtotal(LineHistoricalGroup g) {
    final day = _rate(g, 'day'), ot = _rate(g, 'overtime'), early = _rate(g, 'early');
    if (day == null || (g.overtime > 0 && ot == null) || (g.early > 0 && early == null)) return null;
    var amount = (g.manDays * day).round() + (g.overtime * (ot ?? 0)).round() + (g.early * (early ?? 0)).round();
    for (final entry in g.allowances.entries) {
      final rate = _rate(g, 'allowance:${entry.key}');
      if (rate == null) return null;
      amount += entry.value * rate;
    }
    return amount;
  }
  Future<void> _save() async {
    if (_pending == null) {
      if (_summary.isEmpty || _summary.any((g) => _subtotal(g) == null)) {
        setState(() => _error = '実数量のある項目の単価を入力してください。空欄を0円として保存しません。'); return;
      }
      final rates = [for (final g in _summary) <String, dynamic>{
        'site_id': g.siteId, 'work_category': g.category, 'day': _rate(g, 'day'),
        'overtime': _rate(g, 'overtime'), 'early': _rate(g, 'early'),
        'allowances': {for (final name in g.allowances.keys) name: _rate(g, 'allowance:$name')},
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
      firstDate: DateTime(1900), lastDate: DateTime(now.year, now.month, 0));
    if (date == null || !mounted) return;
    setState(() => _month = DateTime(date.year, date.month));
    await _load();
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
    return Scaffold(appBar: AppBar(title: const Text('LINE過去月の履歴小計'), actions: [
      IconButton(onPressed: () => showDialog<void>(context: context, builder: (context) => AlertDialog(title: const Text('履歴小計'), content: const Text('実人数は重複を除いた人数、延べ人工は各日の人工の合計です。過去月の確認済み候補へ単価を入力して保存します。空欄は未取得、0円は明示入力として扱います。保存は通常請求書の発行とは別です。'), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('閉じる'))])), icon: const Icon(Icons.help_outline), tooltip: 'ヘルプ'),
      IconButton(onPressed: _busy ? null : _reload, icon: const Icon(Icons.refresh), tooltip: '再読み込み')]),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        const Text('Master専用。確認済みの過去月候補と入力した履歴単価で小計を保存します。現在の単価・通常請求書・給与は変更しません。税・福利厚生費は適用しません。'),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(initialValue: _group, decoration: const InputDecoration(labelText: 'LINEグループ'),
          items: [for (final g in _groups) DropdownMenuItem(value: g['id'].toString(), child: Text(g['display_name']?.toString() ?? g['name'].toString()))],
          onChanged: _busy || _edited || _pending != null ? null : (value) { setState(() => _group = value); _load(); }),
        OutlinedButton.icon(onPressed: _busy || _edited || _pending != null ? null : _chooseMonth,
          icon: const Icon(Icons.calendar_month), label: Text('${_month.year}年${_month.month}月')),
        if (_busy) const LinearProgressIndicator(),
        if (_error != null) Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
        Text('実人数 $people人 ／ 延べ ${days.toStringAsFixed(1)}人工', style: Theme.of(context).textTheme.titleMedium),
        if (!_busy && _summary.isEmpty) const Text('確認済みの請求候補がありません。LINE請求書で履歴を取り込み、照合して保存してください。'),
        for (final g in _summary) Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${g.siteName} ／ ${g.category}', style: Theme.of(context).textTheme.titleMedium),
          Text('実人数 ${g.workers.length}人 ／ 延べ ${g.manDays}人工'),
          _field(g, 'day', '人工単価（円／人工）', '${g.manDays}人工 × 単価'),
          if (g.overtime > 0) _field(g, 'overtime', '残業単価（円／時間）', '${g.overtime}時間 × 単価'),
          if (g.early > 0) _field(g, 'early', '早出単価（円／時間）', '${g.early}時間 × 単価'),
          for (final a in g.allowances.entries) _field(g, 'allowance:${a.key}', '${a.key}（円／回）', '${a.value}回 × 単価'),
          const SizedBox(height: 8), Text(_subtotal(g) == null ? '単価未入力' : '履歴小計 ${_subtotal(g)}円'),
        ]))),
        FilledButton(onPressed: _busy || _summary.isEmpty ? null : _save,
          child: Text(_pending == null ? '履歴小計を保存' : '同じ保存を再送')),
        const SizedBox(height: 20), const Text('保存済み履歴（現在単価で再計算しません）'),
        for (final raw in saved) ExpansionTile(title: Text('保存 ${raw['created_at']}'), children: [
          ListTile(title: Text('小計 ${raw['snapshot']['subtotal']}円'),
            subtitle: Text('対象月 ${raw['snapshot']['month']} ／ 実人数 ${raw['snapshot']['people']}人 ／ 延べ ${raw['snapshot']['man_days']}人工\n通常請求書は未発行')),
        ]),
      ]));
  }
}
