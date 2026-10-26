import 'package:flutter/material.dart';
import 'trade_document_adjustment_model.dart';

class TradeDocumentAdjustmentHistoryPage extends StatefulWidget {
  const TradeDocumentAdjustmentHistoryPage({super.key, required this.companyId,
    required this.kind, required this.partyId, required this.month, required this.port});
  final String companyId, partyId, month;
  final TradeDocumentAdjustmentKind kind;
  final TradeDocumentAdjustmentPort port;
  @override
  State<TradeDocumentAdjustmentHistoryPage> createState() => _TradeDocumentAdjustmentHistoryPageState();
}

class _TradeDocumentAdjustmentHistoryPageState extends State<TradeDocumentAdjustmentHistoryPage> {
  final _entries = <TradeDocumentAdjustmentHistoryEntry>[];
  bool _busy = false, _hasMore = false, _loaded = false;
  String? _error;
  @override
  void initState() { super.initState(); _load(); }
  Future<void> _load() async {
    if (_busy) { return; }
    setState(() { _busy = true; _error = null; });
    final cursor = _entries.isEmpty ? null : _entries.last.id;
    try {
      final page = await widget.port.history(companyId: widget.companyId, kind: widget.kind,
        partyId: widget.partyId, month: widget.month, beforeId: cursor);
      page.verify(companyId: widget.companyId, kind: widget.kind, partyId: widget.partyId,
        month: widget.month, beforeId: cursor);
      if (!mounted) { return; }
      setState(() { _entries.addAll(page.entries); _hasMore = page.hasMore; _loaded = true; });
    } catch (_) {
      if (mounted) { setState(() { _error = '変更履歴を取得できませんでした。権限とログイン状態を確認してください。'; }); }
    } finally { if (mounted) { setState(() { _busy = false; }); } }
  }
  String _action(TradeDocumentAdjustmentAction action) => switch (action) {
    TradeDocumentAdjustmentAction.add => '追加', TradeDocumentAdjustmentAction.edit => '編集',
    TradeDocumentAdjustmentAction.cancel => '削除', TradeDocumentAdjustmentAction.stop => '毎月登録の停止',
  };
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('変更履歴')),
    body: ListView(padding: const EdgeInsets.all(16), children: [
      Text('対象月：${widget.month.substring(0, 7)}'),
      if (_busy) const LinearProgressIndicator(),
      if (_error != null) Text(_error!),
      if (_loaded && _entries.isEmpty) const Text('この対象月の変更履歴はありません。'),
      ..._entries.map((entry) => Card(child: Padding(padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${_action(entry.action)}：${entry.title}'),
          Text('記録日時（UTC）：${entry.createdAt.toUtc().toIso8601String()}'),
          Text('操作者ID ${entry.actorId}'),
          if (entry.amountYen != null) Text('${entry.sign?.label ?? ''} ${entry.amountYen}円'),
          if (entry.recurrence != null) Text(entry.recurrence!.label),
          if (entry.calculationMode != null) Text(entry.calculationMode!.label),
          Text('変更前の合計：${entry.beforeTotalYen}円'),
          Text('変更後の合計：${entry.afterTotalYen}円'),
          Text('変更対象月：${entry.changedMonths.map((month) => month.substring(0, 7)).join('、')}'),
        ])))),
      if (_error != null || _hasMore)
        OutlinedButton(onPressed: _busy ? null : _load,
          child: Text(_error != null ? '再読み込み' : '次の100件を読み込む')),
    ]),
  );
}
