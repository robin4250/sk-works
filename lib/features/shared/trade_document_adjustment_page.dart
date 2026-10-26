import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'trade_document_adjustment_model.dart';

class TradeDocumentAdjustmentPage extends StatefulWidget {
  const TradeDocumentAdjustmentPage({super.key, required this.companyId,
    required this.kind, required this.month, required this.port, this.initialPartyId});
  final String companyId, month;
  final String? initialPartyId;
  final TradeDocumentAdjustmentKind kind;
  final TradeDocumentAdjustmentPort port;
  @override
  State<TradeDocumentAdjustmentPage> createState() => _TradeDocumentAdjustmentPageState();
}

class _TradeDocumentAdjustmentPageState extends State<TradeDocumentAdjustmentPage> {
  final _title = TextEditingController(), _amount = TextEditingController();
  TradeDocumentAdjustmentWorkspace? _workspace;
  TradeDocumentAdjustmentCommand? _pending, _prepared;
  TradeDocumentAdjustmentPreview? _preview;
  TradeDocumentAdjustmentCalculationMode? _mode;
  String? _siteId;
  TradeDocumentAdjustmentEntry? _editing;
  TradeDocumentAdjustmentSign _sign = TradeDocumentAdjustmentSign.plus;
  TradeDocumentAdjustmentRecurrence _recurrence = TradeDocumentAdjustmentRecurrence.once;
  TradeDocumentAdjustmentUpdateScope _scope = TradeDocumentAdjustmentUpdateScope.currentMonth;
  String? _partyId, _message;
  bool _busy = false;
  @override
  void initState() { super.initState(); _partyId = widget.initialPartyId; _load(); }
  @override
  void dispose() { _title.dispose(); _amount.dispose(); super.dispose(); }
  bool get _enabled => !_busy && _pending == null && (_workspace?.canRegister ?? false);

  Future<bool> _load() async {
    if (mounted) { setState(() { _busy = true; }); }
    try {
      final workspace = await widget.port.load(companyId: widget.companyId,
        kind: widget.kind, month: widget.month, partyId: _partyId);
      if (workspace.companyId != tradeDocumentAdjustmentUuid(widget.companyId) ||
          workspace.kind != widget.kind || workspace.month != widget.month ||
          workspace.partyId != (_partyId == null ? null : tradeDocumentAdjustmentUuid(_partyId!))) {
        throw const FormatException('取得先が一致しません');
      }
      if (!mounted) { return false; }
      setState(() { _workspace = workspace;
        if (!workspace.supportedModes.contains(_mode)) { _mode = null; }
        if (!workspace.chargeSites.any((site) => site.id == _siteId)) { _siteId = null; }
      });
      return true;
    } catch (_) {
      if (mounted) { setState(() { _workspace = null; _message = '登録内容を取得できませんでした。再読み込みしてください。'; }); }
      return false;
    } finally { if (mounted) { setState(() { _busy = false; }); } }
  }

  Future<void> _submit(TradeDocumentAdjustmentAction action, {TradeDocumentAdjustmentEntry? entry}) async {
    if (!_enabled) { return; }
    if (_prepared != null && _preview != null) {
      await _savePrepared(); return;
    }
    if (_mode == null && entry == null) { setState(() { _message = '計算方法を選択してください。'; }); return; }
    final mode = entry?.calculationMode ?? _mode!;
    final site = entry?.siteId ?? _siteId;
    if (!_workspace!.supportedModes.contains(mode) ||
        (mode == TradeDocumentAdjustmentCalculationMode.beforeCharges &&
         widget.kind == TradeDocumentAdjustmentKind.invoice &&
         !_workspace!.chargeSites.any((candidate) => candidate.id == site))) {
      setState(() { _message = '計算方法と対象現場を確認してください。'; }); return;
    }
    TradeDocumentAdjustmentCommand command;
    try {
      command = TradeDocumentAdjustmentCommand(commandId: newTradeDocumentAdjustmentCommandId(),
        companyId: widget.companyId, kind: widget.kind, partyId: _partyId!, month: widget.month,
        expectedVersion: _workspace!.version, action: action,
        calculationMode: entry?.calculationMode ?? _mode!, siteId: entry?.siteId ?? _siteId,
        expectedTemplateVersion: entry?.templateVersion ?? _editing?.templateVersion, entryId: entry?.id ?? _editing?.id,
        sign: action == TradeDocumentAdjustmentAction.add || action == TradeDocumentAdjustmentAction.edit ? _sign : null,
        title: action == TradeDocumentAdjustmentAction.add || action == TradeDocumentAdjustmentAction.edit ? _title.text : null,
        amountYen: action == TradeDocumentAdjustmentAction.add || action == TradeDocumentAdjustmentAction.edit ? int.tryParse(_amount.text) : null,
        recurrence: action == TradeDocumentAdjustmentAction.add || action == TradeDocumentAdjustmentAction.edit ? _recurrence : null,
        updateScope: action == TradeDocumentAdjustmentAction.stop ? TradeDocumentAdjustmentUpdateScope.fromMonth :
          action == TradeDocumentAdjustmentAction.edit ? _scope : TradeDocumentAdjustmentUpdateScope.currentMonth);
    } on FormatException catch (e) { setState(() { _message = e.message; }); return; }
    setState(() { _busy = true; _message = null; });
    try {
      final preview = await widget.port.preview(command);
      preview.verify(command);
      if (mounted) { setState(() { _prepared = command; _preview = preview; }); }
    } catch (_) {
      if (mounted) { setState(() { _message = '計算結果を確認できません。入力内容を確認してやり直してください。'; }); }
    } finally { if (mounted) { setState(() { _busy = false; }); } }
  }

  Future<void> _savePrepared({bool retry = false}) async {
    if (_busy || _preview == null) { return; }
    final command = retry ? _pending : _prepared;
    if (command == null || (retry && !identical(command, _prepared))) { return; }
    final preview = _preview!;
    setState(() { _pending = command; _busy = true; _message = null; });
    try { await _accept(await widget.port.apply(command, preview: preview), command); }
    on TradeDocumentAdjustmentRejected {
      if (!mounted) { return; }
      setState(() { _pending = null; _prepared = null; _preview = null;
        _message = '変更を登録できませんでした。最新の状態を確認してやり直してください。'; });
      await _load();
    } catch (_) {
      if (mounted) { setState(() { _message = '保存結果を確認できません。入力内容を保持しています。「保存状態を確認」を押してください。'; }); }
    } finally { if (mounted) { setState(() { _busy = false; }); } }
  }

  Future<void> _accept(TradeDocumentAdjustmentReceipt receipt, TradeDocumentAdjustmentCommand command) async {
    receipt.verify(command, _preview!);
    if (!mounted) { return; }
    // Keep the command until a matching receipt has been verified.
    setState(() { _pending = null; _prepared = null; _preview = null; _editing = null; _title.clear(); _amount.clear();
      _scope = TradeDocumentAdjustmentUpdateScope.currentMonth; });
    final loaded = await _load();
    if (mounted && loaded) { setState(() { _message = '登録内容を保存しました。'; }); }
  }

  Future<void> _lookup() async {
    final command = _pending;
    if (command == null || _busy) { return; }
    setState(() { _busy = true; });
    try {
      final receipt = await widget.port.lookup(command);
      if (receipt == null) {
        if (mounted) { setState(() { _message = 'まだ保存を確認できません。時間をおいて再確認してください。'; }); }
      } else { await _accept(receipt, command); }
    } catch (_) {
      if (mounted) { setState(() { _message = '保存状態を確認できません。入力内容は保持しています。'; }); }
    } finally { if (mounted) { setState(() { _busy = false; }); } }
  }

  Future<void> _confirm(TradeDocumentAdjustmentEntry entry, bool stop) async {
    final accepted = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
      title: Text(stop ? '毎月の登録を停止しますか？' : 'この月の項目を削除しますか？'),
      content: Text(stop ? '対象月以降の継続を停止します。過去の確定済み帳票は変更しません。' : 'この月の未確定項目を取り消します。変更履歴は保持されます。'),
      actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('戻る')),
        TextButton(onPressed: () => Navigator.pop(context, true), child: Text(stop ? '停止する' : '削除する'))]));
    if (accepted == true && mounted) { await _submit(stop ? TradeDocumentAdjustmentAction.stop : TradeDocumentAdjustmentAction.cancel, entry: entry); }
  }

  void _edit(TradeDocumentAdjustmentEntry entry) {
    setState(() { _editing = entry; _title.text = entry.title; _amount.text = '${entry.amountYen}';
      _sign = entry.sign; _recurrence = entry.recurrence; _scope = TradeDocumentAdjustmentUpdateScope.currentMonth; _mode = entry.calculationMode; _siteId = entry.siteId; _message = null; });
  }

  @override
  Widget build(BuildContext context) {
    final workspace = _workspace;
    final month = widget.month.split('-');
    return PopScope(canPop: !_busy && _pending == null, child: Scaffold(
      appBar: AppBar(title: const Text('項目を追加（＋／−）')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Text('${month[0]}年${int.tryParse(month[1]) ?? month[1]}月', style: Theme.of(context).textTheme.titleMedium),
        if (_busy) const LinearProgressIndicator(),
        if (_message != null) Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Text(_message!, semanticsLabel: _message)),
        if (workspace == null && !_busy) OutlinedButton(onPressed: _load, child: const Text('再読み込み')),
        if (workspace != null) ...[
          DropdownButtonFormField<String>(value: workspace.partyId,
            decoration: InputDecoration(labelText: widget.kind.partyLabel),
            items: workspace.parties.map((p) => DropdownMenuItem(value: p.id, child: Text(p.name))).toList(),
            onChanged: _busy || _pending != null || _prepared != null || _editing != null ? null : (value) { setState(() { _partyId = value; _mode = null; _siteId = null; _message = null; }); _load(); }),
          if (workspace.locked) const Text('確定済みの帳票は変更できません。'),
          if (!workspace.ready || workspace.supportedModes.isEmpty) const Text('この機能は準備中です。'),
          if (!workspace.canEdit) const Text('登録・編集する権限がありません。'),
          const SizedBox(height: 16),
          DropdownButtonFormField<TradeDocumentAdjustmentCalculationMode>(value: _mode,
            isExpanded: true, decoration: const InputDecoration(labelText: '計算方法'),
            items: workspace.supportedModes.map((mode) => DropdownMenuItem(value: mode,
              child: Text(mode.label, maxLines: 2))).toList(),
            onChanged: _enabled && _prepared == null ? (value) => setState(() { _mode = value; }) : null),
          if (_mode == TradeDocumentAdjustmentCalculationMode.beforeCharges && widget.kind == TradeDocumentAdjustmentKind.invoice)
            DropdownButtonFormField<String>(value: _siteId, decoration: const InputDecoration(labelText: '対象現場'),
              items: workspace.chargeSites.map((site) => DropdownMenuItem(value: site.id, child: Text(site.label))).toList(),
              onChanged: _enabled && _prepared == null ? (value) => setState(() { _siteId = value; }) : null),
          Wrap(spacing: 12, children: TradeDocumentAdjustmentSign.values.map((sign) => ChoiceChip(label: Text(sign.label), selected: _sign == sign,
            onSelected: _enabled && _prepared == null ? (_) => setState(() { _sign = sign; }) : null)).toList()),
          TextField(controller: _title, enabled: _enabled && _prepared == null, maxLength: 120, decoration: const InputDecoration(labelText: '項目名')),
          TextField(controller: _amount, enabled: _enabled && _prepared == null, keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly], decoration: const InputDecoration(labelText: '金額', suffixText: '円')),
          Wrap(spacing: 12, children: TradeDocumentAdjustmentRecurrence.values.map((recurrence) => ChoiceChip(label: Text(recurrence.label), selected: _recurrence == recurrence,
            onSelected: _enabled && _prepared == null && _editing == null ? (_) => setState(() { _recurrence = recurrence; }) : null)).toList()),
          if (_editing?.recurrence == TradeDocumentAdjustmentRecurrence.monthly)
            DropdownButtonFormField<TradeDocumentAdjustmentUpdateScope>(value: _scope,
              decoration: const InputDecoration(labelText: '変更する範囲'),
              items: const [DropdownMenuItem(value: TradeDocumentAdjustmentUpdateScope.currentMonth, child: Text('この月だけ')),
                DropdownMenuItem(value: TradeDocumentAdjustmentUpdateScope.fromMonth, child: Text('この月から毎月'))],
              onChanged: _enabled && _prepared == null ? (value) => setState(() { _scope = value!; }) : null),
          if (_preview != null) ...[
            Text('変更前の合計：${_preview!.baseTotalYen}円'),
            if (_preview!.adjustmentYen != null) Text('加減算：${_preview!.adjustmentYen}円'),
            if (_preview!.welfareYen != null) Text('福利厚生：${_preview!.welfareYen}円'),
            if (_preview!.taxYen != null) Text('税：${_preview!.taxYen}円'),
            Text('登録後の合計：${_preview!.resultTotalYen}円'),
          ],
          if (_pending != null) ...[
            FilledButton(onPressed: _busy ? null : _lookup, child: const Text('保存状態を確認')),
            OutlinedButton(onPressed: _busy ? null : () => _savePrepared(retry: true),
              child: const Text('同じ内容で保存を再試行')),
          ]
          else FilledButton(onPressed: _enabled ? () => _submit(_editing == null ? TradeDocumentAdjustmentAction.add : TradeDocumentAdjustmentAction.edit) : null,
            child: Text(_prepared != null ? 'この計算結果で登録' : '計算結果を確認')),
          if (_prepared != null && _pending == null) TextButton(onPressed: _busy ? null : () => setState(() { _prepared = null; _preview = null; }), child: const Text('入力を変更する')),
          if (_editing != null && _pending == null && _prepared == null) TextButton(onPressed: _busy ? null : () => setState(() { _editing = null; _title.clear(); _amount.clear(); }), child: const Text('編集をやめる')),
          const Divider(),
          ...workspace.entries.where((entry) => !entry.canceled).map((entry) => Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${entry.sign == TradeDocumentAdjustmentSign.plus ? '＋' : '−'} ${entry.title}　${entry.amountYen}円'),
            Text('${entry.recurrence.label}${entry.templateStopped ? '（継続停止済み）' : ''}'),
            Wrap(children: [TextButton(onPressed: _enabled && _prepared == null && entry.editable ? () => _edit(entry) : null, child: const Text('編集')),
              TextButton(onPressed: _enabled && _prepared == null && entry.editable ? () => _confirm(entry, false) : null, child: const Text('削除')),
              if (entry.recurrence == TradeDocumentAdjustmentRecurrence.monthly && !entry.templateStopped)
                TextButton(onPressed: _enabled && _prepared == null && entry.canStop ? () => _confirm(entry, true) : null, child: const Text('今後の毎月登録を停止'))])])))),
        ],
      ])));
  }
}
