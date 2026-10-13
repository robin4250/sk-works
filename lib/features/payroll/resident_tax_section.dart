import 'package:flutter/material.dart';

import 'resident_tax_repository.dart';

class ResidentTaxSection extends StatefulWidget {
  const ResidentTaxSection({super.key, required this.workerId, required this.canEdit,
    required this.legacyAmount, this.companyId, this.repository, this.month});
  final String workerId;
  final String? companyId;
  final bool canEdit;
  final num legacyAmount;
  final String? month;
  final ResidentTaxRepository? repository;
  @override
  State<ResidentTaxSection> createState() => _ResidentTaxSectionState();
}

class _ResidentTaxSectionState extends State<ResidentTaxSection> {
  late ResidentTaxRepository _repository;
  final _amount = TextEditingController();
  final _start = TextEditingController();
  ResidentTaxData? _data;
  ResidentTaxState? _pendingSave;
  bool _busy = false;
  bool _loading = false;
  int _generation = 0;
  String? _error;
  String? _result;
  late String _month;
  @override
  void initState() {
    super.initState();
    final now = DateTime.now().toUtc().add(const Duration(hours: 9));
    _month = widget.month ?? '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-01';
    _repository = widget.repository ?? SupabaseResidentTaxRepository();
    _load();
  }
  @override
  void didUpdateWidget(covariant ResidentTaxSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.workerId != widget.workerId || oldWidget.companyId != widget.companyId || oldWidget.repository != widget.repository || oldWidget.month != widget.month) {
      _repository = widget.repository ?? SupabaseResidentTaxRepository();
      if (widget.month != null) {
        _month = widget.month!;
      }
      _data = null; _result = null; _pendingSave = null;
      _load();
    }
  }
  @override
  void dispose() { _amount.dispose(); _start.dispose(); super.dispose(); }

  Future<void> _load() async {
    final generation = ++_generation;
    setState(() { _busy = true; _loading = true; _error = null; });
    try {
      final data = await _repository.read(widget.workerId, _month, companyId: widget.companyId);
      if (!mounted || generation != _generation) {
        return;
      }
      _amount.text = data.amount.toString();
      _start.text = _month.substring(0, 7);
      setState(() {
        _data = data;
        if (_pendingSave != null && residentTaxStateMatches(data.state, _pendingSave!)) {
          _pendingSave = null; _result = '住民税の保存を確認しました';
        }
      });
    } catch (_) {
      if (!mounted || generation != _generation) {
        return;
      }
      setState(() { _data = null; _error = '住民税設定を取得できません。再読み込みしてください。'; });
    } finally {
      if (mounted && generation == _generation) {
        setState(() { _busy = false; _loading = false; });
      }
    }
  }

  Future<void> _save({bool restoreLegacy = false}) async {
    final data = _data;
    if (_busy || _pendingSave != null || !widget.canEdit || data == null) {
      return;
    }
    final generation = _generation;
    final amount = int.tryParse(_amount.text.trim());
    if (!restoreLegacy && (amount == null || amount < 0 || amount > 2147483647)) {
      setState(() => _error = '月額は0以上の整数で入力してください'); return;
    }
    String month;
    try { month = restoreLegacy ? _month : validateResidentTaxMonth('${_start.text.trim()}-01'); } on FormatException catch (error) {
      setState(() => _error = error.message); return;
    }
    List<ResidentTaxEntry> entries;
    try {
      entries = restoreLegacy ? <ResidentTaxEntry>[] : residentTaxEntriesWithMonth(
        data.state?.entries ?? [], ResidentTaxEntry(month: month, amount: amount!));
    } on FormatException catch (error) {
      setState(() => _error = error.message);
      return;
    }
    final cutover = restoreLegacy ? null : entries.first.month;
    setState(() { _busy = true; _error = null; _result = null; });
    try {
      final confirmed = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
        title: Text(restoreLegacy ? '従来の固定額に戻す' : '住民税を保存'),
        content: Text(restoreLegacy ?
          '開始年月の設定を解除し、従来の月額${widget.legacyAmount.toStringAsFixed(0)}円を使用します。確認対象年月は${_month.substring(0, 7)}です。未確定給与は従来の固定額で再計算されます。過去の確定給与は変更しません。' :
          '${month.substring(0, 7)}から月額$amount円を設定します。\n月額設定の開始は${cutover!.substring(0, 7)}です。それより前は従来の固定額を使用します。\n\n住民税はこの操作で個別に保存されます。過去の確定給与は変更しません。'),
        actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('キャンセル')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('確認して保存'))],
      )) ?? false;
      if (!mounted || generation != _generation || !confirmed || !widget.canEdit) {
        return;
      }
      setState(() {
        _loading = true;
        _pendingSave = ResidentTaxState(version: (data.state?.version ?? 0) + 1, mode: restoreLegacy ? 'legacy' : 'timeline',
          cutover: cutover, entries: entries, updatedBy: '', updatedAt: '');
      });
      await _repository.save(companyId: data.companyId, workerId: widget.workerId, expectedVersion: data.state?.version ?? 0,
        mode: restoreLegacy ? 'legacy' : 'timeline', cutover: cutover, entries: entries);
      if (!mounted || generation != _generation) {
        return;
      }
      setState(() { _pendingSave = null; _result = '住民税を保存しました'; });
      await _load();
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() => _error = '保存結果を確認できません。再読み込みして確認してください。');
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() { _busy = false; _loading = false; });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    if (_loading) const LinearProgressIndicator(),
    if (_error != null) Text(_error!),
    if (_result != null) Text(_result!),
    if (_pendingSave != null) const Text('保存結果の確認が必要です。住民税を再読み込みしてください。'),
    if (_data != null) ...[
      Text('${_month.substring(0, 7)}の住民税：${_data!.amount}円', style: Theme.of(context).textTheme.titleMedium),
      Text(_data!.mode == 'legacy' ? '従来の固定額を適用中' : '${_data!.effectiveMonth!.substring(0, 7)}からの月額を適用中'),
      const SizedBox(height: 8),
      Row(children: [Expanded(child: TextField(key: const ValueKey('resident-amount'), controller: _amount,
        enabled: widget.canEdit && !_busy && _pendingSave == null, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: '月額（円）'))),
        const SizedBox(width: 12), Expanded(child: TextField(key: const ValueKey('resident-start'), controller: _start,
          enabled: widget.canEdit && !_busy && _pendingSave == null, decoration: const InputDecoration(labelText: '開始年月（YYYY-MM）')))]),
      const SizedBox(height: 8),
      FilledButton(onPressed: widget.canEdit && !_busy && _pendingSave == null ? () => _save() : null, child: const Text('住民税だけ保存')),
      const Text('この設定は住民税の保存ボタンで保存します。'),
      ExpansionTile(title: const Text('予約・履歴・従来設定'), children: [
        if (_data!.state == null) const Text('開始年月の設定はまだ登録されていません'),
        for (final entry in _data!.state?.entries ?? <ResidentTaxEntry>[])
          ListTile(title: Text('${entry.month.substring(0, 7)}から ${entry.amount}円')),
        ListTile(title: Text('従来の固定月額 ${widget.legacyAmount.toStringAsFixed(0)}円')),
        TextButton(onPressed: widget.canEdit && !_busy && _pendingSave == null && _data!.state?.mode == 'timeline' ? () => _save(restoreLegacy: true) : null,
          child: const Text('従来の固定額に戻す')),
        for (final row in _data!.history) ListTile(title: Text('変更者 ${row['actor_id']}'), subtitle: Text('変更日時 ${row['changed_at']}')),
      ]),
    ],
    TextButton(onPressed: _busy ? null : _load, child: const Text('住民税を再読み込み')),
  ]);
}
