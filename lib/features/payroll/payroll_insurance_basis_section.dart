import 'dart:async';

import 'package:flutter/material.dart';

import 'payroll_insurance_basis_reference.dart';

/// Collects income and notifies the parent; the parent owns standard bases.
class PayrollInsuranceBasisSection extends StatefulWidget {
  const PayrollInsuranceBasisSection({super.key, required this.month,
    required this.supported, required this.enabled, required this.readHistory,
    required this.onChanged, this.onIncomeChanged, this.initialReference});
  final String month;
  final bool supported, enabled;
  final PayrollInsuranceBasisReference? initialReference;
  final Future<PayrollInsuranceIncomeHistory> Function(String from, String to) readHistory;
  final ValueChanged<PayrollInsuranceBasisReference?> onChanged;
  /// Only explicit amount/history selection, never a period-only metadata edit.
  final ValueChanged<PayrollInsuranceBasisReference?>? onIncomeChanged;

  @override
  State<PayrollInsuranceBasisSection> createState() => _PayrollInsuranceBasisSectionState();
}

class _PayrollInsuranceBasisSectionState extends State<PayrollInsuranceBasisSection> {
  final _from = TextEditingController(), _to = TextEditingController();
  final _average = TextEditingController();
  PayrollInsuranceIncomeHistory? _history;
  String _source = 'manual';
  String? _fingerprint, _error;
  int _observed = 0, _generation = 0;
  bool _busy = false;
  Timer? _periodReload;

  @override
  void initState() {
    super.initState();
    _fill();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.supported) _read();
    });
  }

  void _fill() {
    final ref = widget.initialReference;
    _from.text = (ref?.from ?? widget.month).substring(0, 7);
    _to.text = (ref?.to ?? widget.month).substring(0, 7);
    _average.text = ref?.averageMonthlyIncomeYen.toString() ?? '';
    _source = ref?.source ?? 'manual';
    _observed = ref?.observedMonths ?? 0;
    _fingerprint = ref?.historyFingerprint;
  }

  @override
  void dispose() {
    _generation++;
    _periodReload?.cancel();
    _from.dispose(); _to.dispose(); _average.dispose();
    super.dispose();
  }

  String? _monthError(String? value) => RegExp(r'^20\d{2}-(0[1-9]|1[0-2])$')
      .hasMatch(value ?? '') ? null : 'YYYY-MMで入力';

  PayrollInsuranceBasisReference? _reference() {
    if (_average.text.trim().isEmpty) return null;
    return PayrollInsuranceBasisReference.fromJson({
      'schema': 1, 'from': '${_from.text}-01', 'to': '${_to.text}-01',
      'average_monthly_income_yen': int.tryParse(_average.text.trim()),
      'source': _source, 'observed_months': _observed,
      'history_fingerprint': _fingerprint,
    });
  }

  void _changed({bool period = false}) {
    setState(() {
      if (period && _source != 'manual') _average.clear();
      _source = 'manual'; _observed = 0; _fingerprint = null;
      if (period) { _history = null; _generation++; _busy = false; }
      _error = null;
    });
    if (period) {
      _periodReload?.cancel();
      if (widget.supported) {
        _periodReload = Timer(const Duration(milliseconds: 450), () {
          if (!mounted) return;
          try { payrollReferenceMonths('${_from.text}-01', '${_to.text}-01'); }
          on FormatException { return; }
          _read();
        });
      }
    }
    try {
      final reference = _reference();
      widget.onChanged(reference);
      if (!period) widget.onIncomeChanged?.call(reference);
    } on FormatException {
      // The enclosing Form validates before save. Never emit a guessed value.
      widget.onChanged(null);
      if (!period) widget.onIncomeChanged?.call(null);
    }
  }

  Future<void> _read() async {
    String from, to;
    try {
      from = '${_from.text}-01'; to = '${_to.text}-01';
      payrollReferenceMonths(from, to);
    } on FormatException catch (error) {
      setState(() => _error = error.message.toString()); return;
    }
    final generation = ++_generation;
    setState(() { _busy = true; _error = null; });
    try {
      final history = await widget.readHistory(from, to);
      if (!mounted || generation != _generation) return;
      if (history.from != from || history.to != to) throw const FormatException('実績の対象期間が一致しません');
      setState(() { _history = history; _busy = false; });
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() { _busy = false; _error = '実績を取得できません。入力した平均月収は変更していません。'; });
      }
    }
  }

  void _useHistory(bool complete) {
    final history = _history;
    if (history == null) return;
    final ref = history.reference(requireComplete: complete);
    setState(() {
      _source = ref.source; _observed = ref.observedMonths;
      _fingerprint = ref.historyFingerprint;
      _average.text = '${ref.averageMonthlyIncomeYen}';
    });
    widget.onChanged(ref);
    widget.onIncomeChanged?.call(ref);
  }

  String get _sourceLabel => switch (_source) {
    'actual_available' => '実績平均候補を選択（$_observedか月）',
    'actual_complete' => '期間平均候補を選択（$_observedか月）',
    _ => '手動入力',
  };

  @override
  Widget build(BuildContext context) {
    final history = _history;
    final enabled = widget.enabled;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const Text('平均月収の対象期間', style: TextStyle(fontWeight: FontWeight.w700)),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(child: TextFormField(key: const ValueKey('insurance-reference-from'),
          controller: _from, enabled: enabled, keyboardType: TextInputType.datetime,
          decoration: const InputDecoration(labelText: '開始年月', hintText: 'YYYY-MM'),
          validator: (value) {
            final error = _monthError(value); if (error != null) return error;
            if (_monthError(_to.text) == null) {
              try { payrollReferenceMonths('$value-01', '${_to.text}-01'); }
              on FormatException catch (error) { return error.message.toString(); }
            }
            return null;
          }, onChanged: (_) => _changed(period: true))),
        const Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Text('〜')),
        Expanded(child: TextFormField(key: const ValueKey('insurance-reference-to'),
          controller: _to, enabled: enabled, keyboardType: TextInputType.datetime,
          decoration: const InputDecoration(labelText: '終了年月', hintText: 'YYYY-MM'),
          validator: _monthError, onChanged: (_) => _changed(period: true))),
      ]),
      const SizedBox(height: 8),
      TextFormField(key: const ValueKey('insurance-reference-average'),
        controller: _average, enabled: enabled, keyboardType: TextInputType.number,
        decoration: InputDecoration(labelText: '平均月収（初回はここに入力）', suffixText: '円', helperText: _sourceLabel),
        validator: (value) {
          if ((value ?? '').trim().isEmpty) return null;
          try { _reference(); return null; }
          on FormatException { return '平均月収は0〜2,147,483,647円の整数で入力してください'; }
        }, onChanged: (_) => _changed()),
      const ExpansionTile(title: Text('平均月収について'), children: [
        Padding(padding: EdgeInsets.all(8), child: Text('手入力または選択した実績平均を、保険料の計算基準に使います。給与対象月の控除前支給総額の平均で、法定の算定基礎届の平均を自動判定するものではありません。手当や現物給与の対象範囲・支払基礎日数を確認してください。保存済みの記録や計算用の額は、空欄にしただけでは削除しません。')),
      ]),
      if (!widget.supported)
        const Text('対象期間・平均月収はこのサーバーでは未保存です。標準報酬月額・適用開始月は従来どおり保存できます。'),
      if (widget.supported)
        OutlinedButton(onPressed: enabled && !_busy ? _read : null,
          child: const Text('対象期間の実績を確認')),
      if (_busy) const LinearProgressIndicator(),
      if (_error != null) Text(_error!),
      if (history != null) ...[
        Text('明細あり ${history.items.length}/${history.expectedMonths}か月・不足 ${history.missingMonths}か月'),
        if (history.averageYen != null)
          Text('${history.complete ? '期間平均候補' : '実績平均候補'} ${history.averageYen}円（入力値は自動変更しません）'),
        if (history.missingMonths > 0) const Text('未登録・保留などで取得できない月を0円として平均に含めません。'),
        if (history.containsDraft) const Text('未確定の給与が含まれます。確定後に実績が変わる場合があります。'),
        const Text('控除前の支給総額（給与調整を含む）の平均です。1円単位で四捨五入します。'),
        Wrap(spacing: 8, children: [
          OutlinedButton(key: const ValueKey('insurance-use-actual-average'),
            onPressed: enabled && history.averageYen != null ? () => _useHistory(false) : null,
            child: const Text('実績平均候補を使う')),
          OutlinedButton(key: const ValueKey('insurance-use-period-average'),
            onPressed: enabled && history.complete && history.averageYen != null ? () => _useHistory(true) : null,
            child: const Text('期間平均候補を使う')),
        ]),
        ExpansionTile(title: const Text('使用する明細'), children: [
          for (final row in history.items) ListTile(dense: true,
            title: Text('給与対象月 ${row.month.substring(0, 7)}・支給総額 ${row.grossPay}円'),
            subtitle: Text('支給日 ${row.paymentDate ?? '記録なし'}・${row.finalized ? '確定済み' : '未確定'}')),
        ]),
      ],
      const SizedBox(height: 12),
    ]);
  }
}
