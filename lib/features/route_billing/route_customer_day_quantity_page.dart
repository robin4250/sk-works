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
      content: const SingleChildScrollView(child: Text('退勤済みの訪問日報を取引会社ごとにまとめています。各社について1人工または0.5人工を選び、申請してください。別々の取引会社の合計を1人工に制限しません。管理者が根拠現場・数量・単価を確認して承認した後、請求書の下書きへ反映します。給与や出勤表の人工は変更しません。戻るだけでは申請しません。\n\n自分が作成した対象日の完了訪問日報を確認しています。日報が保存されていても、退勤記録を確認できない場合は数量の申請候補に表示しません。「日報なし」や「取引会社未設定」とは別の状態です。過去の記録は管理者に日付・現場・保存済み日報の確認を依頼してください。実際に勤務中なら通常の退勤操作後に再読み込みしてください。\n\nこの画面で表示した候補を申請しても、同じ月の別の日報に根拠不足や承認待ちがあれば、請求書の確定は完了しません。過去の退勤日時や人工を推測して登録せず、請求数量の承認ページと保存済み記録を確認してください。')),
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
          if (day != null) _evidenceNotice(day),
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

  Widget _evidenceNotice(RouteCustomerQuantityDay day) {
    final diagnostics = day.diagnostics;
    if (diagnostics == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Text('訪問日報の根拠確認情報は未取得です。候補に出ない日報がある場合は、再読み込みするか、管理者に元の出勤・退勤記録の確認を依頼してください。'),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('自分が作成した対象日の完了訪問日報：${diagnostics.completedReportCount}件／申請候補：${diagnostics.eligibleReportCount}件'),
        if (diagnostics.missingSourceCount > 0)
          Text('元の出勤・退勤記録を確認できない日報：${diagnostics.missingSourceCount}件。日報は保存されていますが、この画面から数量を申請できません。管理者に日付・現場・保存済み日報の確認を依頼してください。'),
        if (diagnostics.waitingCheckoutCount > 0)
          Text('退勤記録を確認できない日報：${diagnostics.waitingCheckoutCount}件。実際に勤務中なら通常の退勤操作後に再読み込みしてください。過去の記録は管理者に確認してください。'),
        if (diagnostics.completedReportCount == 0)
          const Text('自分が作成した対象日の、署名まで完了した訪問日報が見つかりません。日報の登録・サインを確認してください。'),
        if (diagnostics.missingSourceCount > 0 ||
            diagnostics.waitingCheckoutCount > 0)
          const Text('同じ月に未申請・未承認の日報が残る場合、請求書の確定は停止します。出勤表に勤務が表示されていることだけでは、請求数量の申請・承認が完了したことにはなりません。'),
      ]),
    );
  }
}

