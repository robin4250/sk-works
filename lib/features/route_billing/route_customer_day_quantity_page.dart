import 'package:flutter/material.dart';
import 'route_customer_day_quantity_repository.dart';

class RouteCustomerDayQuantityPage extends StatefulWidget {
  const RouteCustomerDayQuantityPage({super.key, required this.workerId,
    required this.workDate, @visibleForTesting this.accessOverride});
  final String workerId;
  final DateTime workDate;
  final RouteCustomerQuantityAccess? accessOverride;
  @override
  State<RouteCustomerDayQuantityPage> createState() => _RouteCustomerDayQuantityPageState();
}

class _RouteCustomerDayQuantityPageState extends State<RouteCustomerDayQuantityPage> {
  late final _access = widget.accessOverride ?? RouteCustomerDayQuantityRepository.maybeCreate();
  String? _actor, _error;
  RouteCustomerQuantityDay? _day;
  Map<String, double> _quantities = {};
  bool _loading = true, _saving = false;
  @override
  void initState() {
    super.initState();
    _load();
  }
  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final access = _access;
      if (access == null) throw StateError('ログインを確認してください。');
      final captured = access.actor;
      final day = await access.load(widget.workerId, widget.workDate);
      access.checkActor(captured);
      if (!mounted) return;
      setState(() {
        _actor = captured; _day = day;
        _quantities = {for (final c in day.customers)
          if (c.requestedQuantity == 1 || c.requestedQuantity == 0.5) c.id: c.requestedQuantity!};
      });
    } catch (_) {
      if (mounted) setState(() => _error = '対象の日報を取得できませんでした。再読み込みしてください。');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }
  Future<void> _submit() async {
    final access = _access, day = _day, captured = _actor;
    if (_saving || access == null || day == null || captured == null) return;
    setState(() { _saving = true; _error = null; });
    try {
      access.checkActor(captured);
      await access.submit(widget.workerId, widget.workDate, day, Map.of(_quantities));
      access.checkActor(captured);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('請求数量を申請しました。管理者が確認・承認します。')));
      Navigator.of(context).pop(true);
    } catch (_) {
      if (mounted) setState(() => _error = '申請できませんでした。申請や日報が更新された場合は再読み込みしてください。');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
  void _help() {
    showDialog<void>(context: context, builder: (context) => AlertDialog(
      title: const Text('ルートの請求数量'),
      content: const Text('退勤済みの訪問日報を取引会社ごとにまとめています。各社について1人工または0.5人工を選び、申請してください。別々の取引会社の合計を1人工に制限しません。管理者が根拠現場・数量・単価を確認して承認した後、請求書の下書きへ反映します。給与や出勤表の人工は変更しません。戻るだけでは申請しません。'),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('閉じる'))]));
  }
  @override
  Widget build(BuildContext context) {
    final day = _day;
    final canSubmit = !_loading && !_saving && _error == null && day != null && day.customers.isNotEmpty &&
      day.unresolvedCount == 0 && day.customers.every((c) => _quantities.containsKey(c.id) &&
        (c.status != 'rejected' || _quantities[c.id] != c.requestedQuantity));
    return Scaffold(
      appBar: AppBar(title: const Text('ルート請求数量'), actions: [
        IconButton(onPressed: _saving ? null : _help, icon: const Icon(Icons.help_outline), tooltip: 'ヘルプ'),
        IconButton(onPressed: _saving ? null : _load, icon: const Icon(Icons.refresh), tooltip: '再読み込み')]),
      body: _loading ? const Center(child: CircularProgressIndicator()) : ListView(
        padding: const EdgeInsets.all(16), children: [
          Text('${widget.workDate.year}年${widget.workDate.month}月${widget.workDate.day}日', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8), const Text('取引会社ごとに、請求する数量を選んでください。'),
          if (_error != null) Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
          if (day != null && day.unresolvedCount > 0)
            const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Text('取引会社が未設定の現場があります。現場の登録を確認してから再読み込みしてください。')),
          if (day != null && day.customers.isEmpty && day.unresolvedCount == 0)
            const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Text('退勤済みの訪問日報がありません。日報の登録・サインを確認してください。')),
          for (final c in day?.customers ?? <RouteCustomerQuantityCandidate>[])
            Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text(c.name, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 4), Text(c.sites.join('／')),
                if (c.approvedQuantity != null) Text('承認済み：${c.approvedQuantity == 1 ? '1' : '0.5'}人工'),
                if (c.status == 'rejected') const Text('却下済みです。管理者に確認するか、数量を変更して再申請してください。'),
                const SizedBox(height: 12), const Text('申請数量'), const SizedBox(height: 4), SegmentedButton<double>(
                  segments: const [ButtonSegment(value: 1, label: Text('1人工')), ButtonSegment(value: 0.5, label: Text('0.5人工'))],
                  selected: {if (_quantities[c.id] != null) _quantities[c.id]!}, emptySelectionAllowed: true,
                  onSelectionChanged: _saving ? null : (values) => setState(() {
                    if (values.isEmpty) { _quantities.remove(c.id); } else { _quantities[c.id] = values.single; }
                  })),
              ]))),
        ]),
      bottomNavigationBar: SafeArea(child: Padding(padding: const EdgeInsets.all(12), child: FilledButton(
        onPressed: canSubmit ? _submit : null, child: Text(_saving ? '申請中…' : '申請')))),
    );
  }
}
