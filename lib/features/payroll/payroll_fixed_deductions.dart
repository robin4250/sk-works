import 'package:flutter/material.dart';
import '../../data/supabase_backend.dart';
import 'payroll_tax_conditions_page.dart';

typedef PayrollDeductionStatementReader = Future<Map<String, dynamic>?> Function(
  String companyId, String workerId, String month);

const fixedPayrollDeductions = <(String, String, String)>[
  ('income_tax', '所得税', '所得税'),
  ('employment_insurance', '雇用保険', '雇用保険料'),
  ('health_insurance', '健康保険', '健康保険料'),
  ('pension_insurance', '厚生年金保険', '厚生年金保険'),
  ('nursing_insurance', '介護保険', '介護保険料'),
];

/// Reads generated monthly amounts; corrections use the existing audited,
/// effective-month tax-conditions RPC, never extra custom deductions.
class PayrollFixedDeductions extends StatefulWidget {
  const PayrollFixedDeductions({
    super.key, required this.companyId, required this.workerId,
    required this.readStatement, required this.residentTax,
    this.openConditions, this.openRates, this.rpc, this.month,
    this.refreshRevision = 0, this.canEdit = false,
    this.legacySocialAmount = 0,
  });
  final String companyId, workerId;
  final String? month;
  final int refreshRevision;
  final bool canEdit;
  final num legacySocialAmount;
  final PayrollDeductionStatementReader readStatement;
  final Widget residentTax;
  final Future<void> Function(String month)? openConditions;
  final Future<void> Function()? openRates;
  final PayrollTaxRpc? rpc;
  @override
  State<PayrollFixedDeductions> createState() => _PayrollFixedDeductionsState();
}

class _PayrollFixedDeductionsState extends State<PayrollFixedDeductions> {
  final _controllers = <String, TextEditingController>{
    for (final item in fixedPayrollDeductions) item.$1: TextEditingController(),
  };
  final _manual = <String>{};
  final _automatic = <String, int?>{};
  Map<String, dynamic>? _profile;
  int _version = 0, _generation = 0;
  bool _busy = true, _allowed = false, _dirty = false, _uncertain = false;
  String? _error, _actor;
  late String _month;

  void _checkActor() {
    if (widget.rpc == null && (!SupabaseBackend.isInitialized || _actor == null ||
        SupabaseBackend.client.auth.currentUser?.id != _actor)) {
      throw StateError('ログイン状態が変わりました');
    }
  }

  Future<dynamic> _rpc(String name, Map<String, dynamic> params) {
    if (widget.rpc != null) return widget.rpc!(name, params);
    if (!SupabaseBackend.isInitialized || _actor == null ||
        SupabaseBackend.client.auth.currentUser?.id != _actor) {
      throw StateError('給与の計算条件を確認できません');
    }
    return SupabaseBackend.client.rpc(name, params: params);
  }

  Map<String, dynamic> get _scope => {
    'p_company_id': widget.companyId, 'p_worker_id': widget.workerId,
  };

  @override
  void initState() {
    super.initState();
    if (SupabaseBackend.isInitialized) {
      _actor = SupabaseBackend.client.auth.currentUser?.id;
    }
    _setMonth();
    _load();
  }

  void _setMonth() {
    final now = DateTime.now();
    _month = widget.month ??
        '${now.year}-${now.month.toString().padLeft(2, '0')}-01';
  }

  @override
  void didUpdateWidget(covariant PayrollFixedDeductions oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.companyId != widget.companyId ||
        oldWidget.workerId != widget.workerId || oldWidget.month != widget.month) {
      _setMonth();
      _profile = null;
      _manual.clear();
      for (final c in _controllers.values) { c.clear(); }
      _load();
    } else if (oldWidget.refreshRevision != widget.refreshRevision && !_dirty) {
      _load();
    }
  }

  @override
  void dispose() {
    for (final c in _controllers.values) { c.dispose(); }
    super.dispose();
  }

  int? _yen(Object? raw) => raw is num && raw.isFinite &&
      raw >= 0 && raw <= 2147483647 && raw == raw.round() ? raw.toInt() : null;

  Future<void> _load() async {
    final generation = ++_generation;
    setState(() { _busy = true; _allowed = false; _error = null; });
    try {
      final supported = await _rpc('payroll_deduction_overrides_contract_version', {});
      _checkActor();
      if (!mounted || generation != _generation) return;
      final raw = await _rpc('read_worker_payroll_tax_conditions', _scope);
      _checkActor();
      if (!mounted || generation != _generation) return;
      if (raw is! Map || raw['company_id'] != widget.companyId ||
          raw['worker_id'] != widget.workerId || raw['items'] is! List ||
          raw['can_edit'] is! bool) {
        throw const FormatException('給与の計算条件が一致しません');
      }
      final rows = <Map<String, dynamic>>[];
      int version = 0;
      for (final item in raw['items'] as List) {
        if (item is! Map || item['starts_on'] is! String ||
            item['version'] is! int || item['value'] is! Map) {
          throw const FormatException('給与の計算条件を確認できません');
        }
        if (item['starts_on'] == _month) { version = item['version'] as int; }
        if ((item['starts_on'] as String).compareTo(_month) <= 0) {
          rows.add(Map<String, dynamic>.from(item));
        }
      }
      rows.sort((a, b) => (b['starts_on'] as String).compareTo(a['starts_on'] as String));
      final profile = rows.isEmpty ? null : Map<String, dynamic>.from(rows.first['value'] as Map);
      final storedOverrides = profile?['deduction_overrides'] ?? const {};
      if (storedOverrides is! Map || storedOverrides.entries.any((e) =>
          !_controllers.containsKey(e.key) || _yen(e.value) == null)) {
        throw const FormatException('控除の修正額を確認できません');
      }
      final statement = await widget.readStatement(widget.companyId, widget.workerId, _month);
      _checkActor();
      if (!mounted || generation != _generation) return;
      _profile = profile;
      _version = version;
      _manual
        ..clear()
        ..addAll(storedOverrides.keys.cast<String>());
      final detail = statement?['detail'];
      final tax = detail is Map ? detail['tax_calculation'] : null;
      final ready = statement?['calculation_blocked'] != true &&
          tax is Map && tax['blocked'] != true &&
          rows.isNotEmpty && tax['condition_version'] == rows.first['version'] &&
          tax['conditions_start'] == rows.first['starts_on'];
      if (statement?['calculation_blocked'] == true ||
          (tax is Map && tax['blocked'] == true)) {
        _error = '給料明細の計算が保留中です。計算条件・料率を確認してください。';
      }
      final premiums = ready ? tax['premiums'] : null;
      final autoPremiums = ready ? (tax['automatic_premiums'] ?? premiums) : null;
      for (final item in fixedPayrollDeductions) {
        final automatic = item.$1 == 'income_tax'
            ? (ready ? _yen(tax['automatic_income_tax_yen'] ?? tax['income_tax_yen']) : null)
            : (autoPremiums is Map ? _yen(autoPremiums[item.$3]) : null);
        _automatic[item.$1] = automatic;
        final amount = _manual.contains(item.$1) ? _yen(storedOverrides[item.$1])
            : item.$1 == 'income_tax'
                ? (ready ? _yen(tax['income_tax_yen']) : null)
                : (premiums is Map ? _yen(premiums[item.$3]) : null);
        _controllers[item.$1]!.text = amount?.toString() ?? '';
      }
      _allowed = supported == 1 && raw['can_edit'] == true && widget.canEdit && profile != null;
      _dirty = false;
      _uncertain = false;
    } catch (_) {
      if (!mounted || generation != _generation) return;
      // A failed refresh must not present an old calculated amount as current.
      // Keep explicit corrections so an uncertain save never loses user input.
      _automatic.clear();
      for (final entry in _controllers.entries) {
        if (!_manual.contains(entry.key)) entry.value.clear();
      }
      _error = '税・保険料の計算結果を取得できません。再読み込みしてください。';
    } finally {
      if (mounted && generation == _generation) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    if (!widget.canEdit || !_allowed || _busy || _uncertain || _profile == null) return;
    final overrides = <String, int>{};
    for (final key in _manual) {
      final value = int.tryParse(_controllers[key]!.text.trim());
      if (value == null || value < 0 || value > 2147483647) {
        setState(() => _error = '修正額は0以上の整数で入力してください');
        return;
      }
      overrides[key] = value; // Explicit zero is a correction, never automatic.
    }
    final generation = _generation;
    final value = {..._profile!, 'deduction_overrides': overrides};
    final confirmed = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
      title: const Text('税・保険料の修正を保存'),
      content: Text('${_month.substring(0, 7)}分の修正を保存して給料明細へ反映します。'
          '\n手入力の項目以外は自動計算します。確定済みの給料明細は変更しません。'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('戻る')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('確認して保存')),
      ],
    ));
    if (!mounted || generation != _generation || confirmed != true) return;
    setState(() { _busy = true; _error = null; });
    try {
      final result = await _rpc('save_worker_payroll_tax_conditions', {
        ..._scope, 'p_starts_on': _month, 'p_expected_version': _version,
        'p_value': value, 'p_confirmed': true,
      });
      _checkActor();
      if (!mounted || generation != _generation) return;
      if (result is! Map || result['company_id'] != widget.companyId ||
          result['worker_id'] != widget.workerId || result['items'] is! List ||
          !(result['items'] as List).any((row) => row is Map &&
            row['starts_on'] == _month && row['version'] == _version + 1 &&
            row['value'] is Map &&
            _sameOverrides((row['value'] as Map)['deduction_overrides'], overrides))) {
        throw const FormatException('修正額の保存結果を確認できません');
      }
      await _load();
    } catch (_) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _uncertain = true; _busy = false;
        _error = '保存結果を確認できません。入力を保持しています。再読み込みして確認してください。';
      });
    }
  }

  bool _sameOverrides(Object? raw, Map<String, int> expected) =>
      raw is Map && raw.length == expected.length &&
      expected.entries.every((e) => raw[e.key] == e.value);

  String _amountStatus(String key) {
    if (_manual.contains(key)) return '手入力修正';
    if (_busy) return '計算結果を確認中';
    if (_error != null) return '計算結果未確認';
    if (_profile == null) return '計算条件未設定';
    if (key == 'income_tax' && _profile!['income_mode'] == 'fixed') {
      return _controllers[key]!.text.isEmpty
          ? '固定額設定・給与計算待ち' : '固定額設定';
    }
    if (key != 'income_tax' && _profile!['insurance_mode'] == 'fixed') {
      return '一括固定額設定（個別計算なし）';
    }
    return _controllers[key]!.text.isEmpty ? '給与計算待ち' : '自動計算';
  }

  Future<void> _formula(String key, String title) async {
    final generation = _generation;
    final formula = switch (key) {
      'income_tax' => '支給額から非課税額・社会保険料等を差し引き、適用する所得税月額表・甲欄／乙欄・扶養人数で計算します。',
      'employment_insurance' => '雇用保険の対象支給額 × 会社に登録した本人負担料率',
      'pension_insurance' => '厚生年金の標準報酬月額 × 会社に登録した本人負担料率',
      'nursing_insurance' => '加入条件・対象月の年齢条件を確認し、健康保険の標準報酬月額 × 会社に登録した本人負担料率',
      'resident_tax' => '通知書に基づいて登録した月額と適用開始月を使います。対象月以前の最新設定を適用します。',
      _ => '健康保険の標準報酬月額 × 会社に登録した本人負担料率',
    };
    final action = await showDialog<String>(context: context, builder: (context) => AlertDialog(
      title: Text('$titleの計算式'),
      content: Text('$formula\n\n金額は給料明細と同じ給与計算結果です。手入力した項目は修正額を優先し、「自動計算に戻す」で解除できます。'
          '${key == 'health_insurance' || key == 'nursing_insurance' ? '\n健康保険・介護保険・支援金は給与計算側の共通の端数処理を使います。' : ''}'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('閉じる')),
        if (key != 'resident_tax' && widget.openConditions != null)
          TextButton(onPressed: () => Navigator.pop(context, 'conditions'), child: const Text('個別の計算条件')),
        if (key != 'income_tax' && key != 'resident_tax' && widget.openRates != null)
          TextButton(onPressed: () => Navigator.pop(context, 'rates'), child: const Text('会社の料率')),
      ],
    ));
    if (!mounted || generation != _generation) return;
    if (action == 'conditions') {
      await _openConditions();
      return;
    }
    if (action == 'rates') await widget.openRates?.call();
    if (mounted && generation == _generation && action != null && !_dirty) await _load();
  }

  Future<void> _openConditions() async {
    final generation = _generation;
    await widget.openConditions?.call(_month);
    if (mounted && generation == _generation && !_dirty) await _load();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text('${_month.substring(0, 7)}分・給料明細と連動'),
      if (_busy) const LinearProgressIndicator(),
      if (_error != null) Text(_error!),
      for (final item in fixedPayrollDeductions)
        Card(
          key: ValueKey('fixed-deduction-${item.$1}'),
          margin: const EdgeInsets.only(bottom: 10),
          child: Padding(padding: const EdgeInsets.all(10), child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                key: ValueKey('fixed-deduction-${item.$1}-amount'),
                controller: _controllers[item.$1],
                enabled: widget.canEdit && _allowed && !_busy && !_uncertain &&
                    (item.$1 == 'income_tax' || _profile?['insurance_mode'] == 'rates'),
                keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: item.$2, suffixText: '円',
                  helperText: _amountStatus(item.$1),
                  border: const OutlineInputBorder()),
                onChanged: (_) => setState(() { _manual.add(item.$1); _dirty = true; }),
              ),
              Wrap(spacing: 8, children: [
                TextButton(onPressed: () => _formula(item.$1, item.$2),
                  child: const Text('計算式・設定')),
                if (_manual.contains(item.$1))
                  TextButton(onPressed: widget.canEdit && _allowed && !_busy && !_uncertain ? () => setState(() {
                    _manual.remove(item.$1);
                    _controllers[item.$1]!.text = _automatic[item.$1]?.toString() ?? '';
                    _dirty = true;
                  }) : null, child: const Text('自動計算に戻す')),
              ]),
            ],
          )),
        ),
      if (_profile?['insurance_mode'] != 'rates' && widget.legacySocialAmount > 0)
        Text('保険料の個別計算条件を設定してください。以前の一括設定${widget.legacySocialAmount.toStringAsFixed(0)}円は保持されています。'),
      if (_profile == null && widget.openConditions != null)
        TextButton(onPressed: _busy ? null : _openConditions,
          child: const Text('税・保険料の自動計算を設定')),
      FilledButton(onPressed: widget.canEdit && _allowed && _dirty && !_busy && !_uncertain ? _save : null,
        child: const Text('税・保険料を登録')),
      TextButton(onPressed: _busy ? null : _load, child: const Text('税・保険料を再読み込み')),
      Card(key: const ValueKey('fixed-deduction-resident_tax'),
        margin: const EdgeInsets.only(bottom: 10),
        child: Padding(padding: const EdgeInsets.all(10), child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('住民税', style: Theme.of(context).textTheme.titleMedium),
            TextButton(onPressed: () => _formula('resident_tax', '住民税'),
              child: const Text('計算式・設定')),
            widget.residentTax,
          ],
        )),
      ),
    ],
  );
}

