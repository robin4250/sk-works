import 'dart:convert';

import 'package:flutter/material.dart';
import '../../data/supabase_backend.dart';
import 'payroll_tax_conditions_page.dart';
import 'payroll_recorded_tax_amounts.dart';
import 'payroll_insurance_basis_reference.dart';
import 'payroll_insurance_settings_entry.dart';

typedef PayrollDeductionStatementReader = Future<Map<String, dynamic>?> Function(
  String companyId, String workerId, String month);

const fixedPayrollDeductions = <(String, String, String)>[
  ('income_tax', '所得税', '所得税'),
  ('employment_insurance', '雇用保険', '雇用保険料'),
  ('health_insurance', '健康保険', '健康保険料'),
  ('pension_insurance', '厚生年金保険', '厚生年金保険'),
  ('nursing_insurance', '介護保険', '介護保険料'),
  ('child_support', '子ども・子育て支援金', '子ども・子育て支援金'),
];

/// Reads generated monthly amounts; corrections use the existing audited,
/// effective-month tax-conditions RPC, never extra custom deductions.
class PayrollFixedDeductions extends StatefulWidget {
  const PayrollFixedDeductions({
    super.key, required this.companyId, required this.workerId,
    required this.readStatement, this.residentTax = const SizedBox.shrink(),
    this.residentTaxBuilder,
    this.openConditions, this.openRates, this.rpc, this.month,
    this.refreshRevision = 0, this.canEdit = false,
    this.legacySocialAmount = 0, this.showAmounts = true, this.entryController,
  });
  final String companyId, workerId;
  final String? month;
  final int refreshRevision;
  final bool canEdit;
  final bool showAmounts;
  final PayrollInsuranceEntryController? entryController;
  final num legacySocialAmount;
  final PayrollDeductionStatementReader readStatement;
  final Widget residentTax;
  final Widget Function(String month, ValueChanged<bool> onEditingChanged)? residentTaxBuilder;
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
  final _adjusting = <String, ({String text, bool manual})>{};
  final _loadedManual = <String>{};
  final _loadedAmounts = <String, String>{};
  final _adjustmentReason = TextEditingController();
  bool _reasonContractAvailable = false;
  final _automatic = <String, int?>{};
  Map<String, dynamic>? _profile;
  String? _conditionsStart;
  PayrollInsuranceBasisReference? _basisReference;
  int _version = 0, _generation = 0;
  final _savedSnapshot = <String, int>{};
  bool _residentEditing = false;
  bool _savedCalculation = false;
  bool _conditionsKnown = false;
  bool _entryPublishQueued = false;
  bool _busy = true, _allowed = false, _dirty = false, _uncertain = false;
  String? _error, _actor;
  late String _month;

  bool get _hasPendingInput => _dirty || _residentEditing || _adjusting.isNotEmpty;

  bool _canAdjust(String key) => key != 'child_support' && widget.canEdit &&
      _allowed && _reasonContractAvailable && !_busy && !_uncertain &&
      (key == 'income_tax' || const ['rates', 'manual'].contains(_profile?['insurance_mode']));

  bool _needsAdjustmentAction(String key) => key == 'income_tax' ||
      _profile?['insurance_mode'] != 'manual';

  void _beginAdjustment(String key) => setState(() {
    _adjusting[key] = (text: _controllers[key]!.text, manual: _manual.contains(key));
  });

  void _cancelAdjustment(String key) {
    final before = _adjusting[key];
    if (before == null) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _controllers[key]!.text = before.text;
      if (before.manual) { _manual.add(key); } else { _manual.remove(key); }
      _adjusting.remove(key);
      _dirty = _manual.length != _loadedManual.length ||
          !_manual.containsAll(_loadedManual) ||
          _manual.any((item) => _controllers[item]!.text != _loadedAmounts[item]);
    });
  }

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
    final now = DateTime.now().toUtc().add(const Duration(hours: 9));
    _month = widget.month ??
        '${now.year}-${now.month.toString().padLeft(2, '0')}-01';
  }

  Future<void> _moveMonth(int offset) async {
    if (widget.month != null || _busy || _hasPendingInput || _uncertain) return;
    final current = DateTime.parse(_month);
    final next = DateTime(current.year, current.month + offset);
    setState(() {
      _month = '${next.year.toString().padLeft(4, '0')}-'
          '${next.month.toString().padLeft(2, '0')}-01';
      _profile = null;
      _conditionsStart = null;
      _basisReference = null;
      _savedSnapshot.clear();
      _manual.clear();
      _adjusting.clear();
      _adjustmentReason.clear();
      _automatic.clear();
      for (final controller in _controllers.values) { controller.clear(); }
    });
    await _load();
  }

  @override
  void didUpdateWidget(covariant PayrollFixedDeductions oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.entryController, widget.entryController)) {
      oldWidget.entryController?.detach(this);
    }
    if (oldWidget.companyId != widget.companyId ||
        oldWidget.workerId != widget.workerId || oldWidget.month != widget.month) {
      _setMonth();
      _profile = null;
      _conditionsStart = null;
      _basisReference = null;
      _savedSnapshot.clear();
      _manual.clear();
      _adjusting.clear();
      _adjustmentReason.clear();
      for (final c in _controllers.values) { c.clear(); }
      _load();
    } else if (oldWidget.refreshRevision != widget.refreshRevision && !_hasPendingInput) {
      _load();
    }
  }

  @override
  void dispose() {
    widget.entryController?.detach(this);
    for (final c in _controllers.values) { c.dispose(); }
    _adjustmentReason.dispose();
    super.dispose();
  }

  int? _yen(Object? raw) => raw is num && raw.isFinite &&
      raw >= 0 && raw <= 2147483647 && raw == raw.round() ? raw.toInt() : null;

  int? _savedNamedDeduction(Map detail, String name) {
    // A saved named scalar remains authoritative. Never divide the old
    // social-insurance aggregate into guessed insurance premiums.
    if (detail.containsKey(name)) return _yen(detail[name]);
    final items = detail['custom_deductions'];
    if (items is! List) return null;
    var found = false;
    var total = 0;
    for (final raw in items) {
      if (raw is! Map || raw['name']?.toString().trim() != name) continue;
      final amount = _yen(raw['amount_yen']);
      if (amount == null || total + amount > 2147483647) return null;
      found = true;
      total += amount;
    }
    return found ? total : null;
  }

  Future<void> _load() async {
    final generation = ++_generation;
    setState(() { _busy = true; _allowed = false; _error = null; _basisReference = null; _conditionsKnown = false; });
    try {
      final supported = await _rpc('payroll_deduction_overrides_contract_version', {});
      _checkActor();
      if (!mounted || generation != _generation) return;
      final raw = await readPayrollTaxConditionsWithInsuranceReference((name, params) async {
        final response = await _rpc(name, params);
        _checkActor();
        return response;
      }, _scope);
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
      if (profile?['insurance_mode'] == 'manual' && !validManualPayrollInsurance(profile!)) {
        throw const FormatException('個別保険月額を確認できません');
      }
      final storedOverrides = profile?['deduction_overrides'] ?? const {};
      if (storedOverrides is! Map || storedOverrides.entries.any((e) =>
          !_controllers.containsKey(e.key) || e.key == 'child_support' ||
          _yen(e.value) == null)) {
        throw const FormatException('控除の修正額を確認できません');
      }
      var reasonAvailable = false;
      if (supported == 1 && raw['can_edit'] == true && widget.canEdit && profile != null) {
        try {
          reasonAvailable = await _rpc('payroll_tax_adjustment_reason_contract_version', {}) == 1;
          _checkActor();
        } catch (_) {
          _checkActor();
          // Missing/newer server capability disables only manual adjustments.
          // Keep the existing settings and saved calculation readable.
        }
      }
      if (!mounted || generation != _generation) return;
      final statement = await widget.readStatement(widget.companyId, widget.workerId, _month);
      _checkActor();
      if (!mounted || generation != _generation) return;
      _profile = profile;
      _reasonContractAvailable = reasonAvailable;
      _conditionsStart = rows.isEmpty ? null : rows.first['starts_on'] as String;
      _conditionsKnown = true;
      _basisReference = profile?['insurance_basis_reference'] == null ? null :
          PayrollInsuranceBasisReference.fromJson(profile!['insurance_basis_reference']);
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
      _savedCalculation = !ready && statement?['calculation_blocked'] != true &&
          detail is Map && hasRecordedPayrollTaxCalculation(detail, month: _month);
      if (_savedCalculation) { _manual.clear(); }
      // Named saved deductions remain visible when no automatic-tax profile
      // applies. An old social-insurance aggregate is never split or inferred.
      _savedSnapshot.clear();
      if (((profile == null && tax == null) || _savedCalculation) &&
          statement?['calculation_blocked'] != true && detail is Map) {
        final calculated = recordedPayrollInsuranceAmounts(detail, month: _month);
        for (final item in fixedPayrollDeductions) {
          final saved = _savedNamedDeduction(detail, item.$3);
          final amount = _savedCalculation
              ? item.$1 != 'income_tax' ? calculated[item.$3]
                  : saved ?? (detail.containsKey(item.$3) ? null : _yen((tax as Map)['income_tax_yen']))
              : saved;
          if (amount != null) _savedSnapshot[item.$1] = amount;
        }
      }
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
        final amount = _savedCalculation ? _savedSnapshot[item.$1]
            : profile?['insurance_mode'] == 'manual' && item.$1 != 'income_tax'
            ? _yen((profile!['manual_insurance_premiums'] as Map)[item.$1])
            : _manual.contains(item.$1) ? _yen(storedOverrides[item.$1])
            : item.$1 == 'income_tax'
                ? (ready ? _yen(tax['income_tax_yen']) : _savedSnapshot[item.$1])
                : (premiums is Map ? _yen(premiums[item.$3]) : _savedSnapshot[item.$1]);
        _controllers[item.$1]!.text = amount?.toString() ?? '';
      }
      _allowed = !_savedCalculation && supported == 1 && raw['can_edit'] == true && widget.canEdit && profile != null &&
          (profile['insurance_mode'] != 'manual' || raw['manual_insurance_contract_version'] == 1);
      _adjusting.clear();
      _loadedManual..clear()..addAll(_manual);
      _loadedAmounts..clear()..addEntries(_controllers.entries.map(
        (entry) => MapEntry(entry.key, entry.value.text)));
      _dirty = false;
      _uncertain = false;
    } catch (_) {
      if (!mounted || generation != _generation) return;
      _conditionsKnown = false;
      // A failed refresh must not present an old calculated amount as current.
      // Keep explicit corrections so an uncertain save never loses user input.
      _automatic.clear();
      _savedSnapshot.clear();
      _savedCalculation = false;
      _basisReference = null;
      for (final entry in _controllers.entries) {
        if (!_manual.contains(entry.key)) entry.value.clear();
      }
      _error = '税・保険料の計算結果を取得できません。再読み込みしてください。';
    } finally {
      if (mounted && generation == _generation) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    if (!widget.canEdit || !_allowed || !_reasonContractAvailable ||
        _busy || _uncertain || _profile == null) return;
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
    Map<String, int>? manualAmounts;
    if (_profile!['insurance_mode'] == 'manual') {
      manualAmounts = Map<String, int>.from(_profile!['manual_insurance_premiums'] as Map);
      for (final entry in overrides.entries.where((entry) => entry.key != 'income_tax')) {
        manualAmounts[entry.key] = entry.value;
      }
      overrides.removeWhere((key, value) => key != 'income_tax');
    }
    final expectedManualAmounts = manualAmounts;
    final value = {..._profile!, 'deduction_overrides': overrides,
      if (manualAmounts != null) 'manual_insurance_premiums': manualAmounts};
    if (manualAmounts != null && !validManualPayrollInsurance(value)) {
      setState(() => _error = '保険料の個別月額・合計を確認してください。');
      return;
    }
    final confirmed = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
      title: const Text('税・保険料の修正を保存'),
      content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('${_month.substring(0, 7)}分の修正を保存して給料明細へ反映します。'
          '${manualAmounts == null ? '\n手入力の項目以外は自動計算します。' : '\n保険料は登録した本人負担月額を使います。所得税は設定した計算条件に従います。'}確定済みの給料明細は変更しません。'),
        const SizedBox(height: 12),
        TextField(key: const ValueKey('fixed-deduction-adjustment-reason'),
          controller: _adjustmentReason, minLines: 1, maxLines: 3, maxLength: 1000,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => FocusManager.instance.primaryFocus?.unfocus(),
          decoration: const InputDecoration(labelText: '調整理由（必須）',
            helperText: '自動計算に戻す場合も理由を記録します。', border: OutlineInputBorder())),
      ])),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('戻る')),
        ValueListenableBuilder<TextEditingValue>(valueListenable: _adjustmentReason,
          builder: (context, value, _) => FilledButton(
            onPressed: _validAdjustmentReason(value.text) ? () => Navigator.pop(context, true) : null,
            child: const Text('確認して保存'))),
      ],
    ));
    if (!mounted || generation != _generation || confirmed != true) return;
    final reason = _adjustmentReason.text.trim();
    if (!_validAdjustmentReason(reason)) return;
    setState(() { _busy = true; _error = null; });
    try {
      final result = await _rpc('save_worker_payroll_tax_conditions_with_reason', {
        ..._scope, 'p_starts_on': _month, 'p_expected_version': _version,
        'p_value': value, 'p_confirmed': true,
        'p_reason': reason,
      });
      _checkActor();
      if (!mounted || generation != _generation) return;
      if (result is! Map || result['company_id'] != widget.companyId ||
          result['worker_id'] != widget.workerId || result['items'] is! List ||
          !(result['items'] as List).any((row) => row is Map &&
            row['starts_on'] == _month && row['version'] == _version + 1 &&
            row['value'] is Map &&
            _sameOverrides((row['value'] as Map)['deduction_overrides'], overrides) &&
            (expectedManualAmounts == null || _sameOverrides((row['value'] as Map)['manual_insurance_premiums'], expectedManualAmounts))) ||
          !_validAdjustmentReceipt(result['adjustment_receipt'], reason)) {
        throw const FormatException('修正額の保存結果を確認できません');
      }
      _adjustmentReason.clear();
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

  bool _validAdjustmentReason(String raw) {
    final reason = raw.trim();
    return reason.isNotEmpty && reason.runes.length <= 1000 && utf8.encode(reason).length <= 4000;
  }

  bool _validAdjustmentReceipt(Object? raw, String reason) => raw is Map &&
      raw['starts_on'] == _month && raw['version'] == _version + 1 &&
      raw['reason'] == reason && raw['actor_id'] is String &&
      (raw['actor_id'] as String).isNotEmpty && (_actor == null || raw['actor_id'] == _actor) &&
      raw['changed_at'] is String && DateTime.tryParse(raw['changed_at'] as String) != null;

  String _amountStatus(String key) {
    if (_manual.contains(key)) return '手入力修正';
    if (_busy) return '計算結果を確認中';
    if (_error != null) return '計算結果未確認';
    if (_savedCalculation) return '保存済みの計算結果（現在の設定とは未照合）';
    if (_profile?['insurance_mode'] == 'manual' && key != 'income_tax') return '個別手入力（月額）';
    if (_profile == null) {
      return _savedSnapshot.containsKey(key)
          ? '保存済み明細（自動計算条件未設定）' : '計算条件未設定';
    }
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
      'child_support' => '本人の加入条件と健康保険の標準報酬月額、会社に登録した支援金の本人負担料率から計算します。金額・加入条件の変更は「個別の計算条件」で行います。',
      'resident_tax' => '通知書に基づいて登録した月額と適用開始月を使います。対象月以前の最新設定を適用します。',
      _ => '健康保険の標準報酬月額 × 会社に登録した本人負担料率',
    };
    final action = await showDialog<String>(context: context, builder: (context) => AlertDialog(
      title: Text('$titleの計算式'),
      content: Text('$formula\n\n金額は給料明細と同じ給与計算結果です。'
          '保存済みの計算結果は、現在の条件と照合できなくても読取専用で表示します。'
          '表示のための再登録・再計算は行わず、PDF・印刷・共有も同じ保存済み金額を使います。'
          '支給・控除カードの外にある「保険料を設定」から、加入条件・初回の平均月収・適用開始月を設定できます。入力した平均月収は2026年の一般被保険者の等級表で標準報酬月額へ換算します。既存設定を開いただけでは変更しません。'
          '${key == 'child_support' ? 'この欄は読取専用です。金額・加入条件の変更は「個別の計算条件」で行います。' : _needsAdjustmentAction(key) ? '通常は読取専用です。「手動で調整」を選ぶと、この項目だけ入力できます。手入力した項目は修正額を優先し、「自動計算に戻す」で解除できます。' : 'この欄は個別手入力の月額です。登録した月額を使います。'}'
          '${key == 'health_insurance' || key == 'nursing_insurance' || key == 'child_support' ? '\n健康保険・介護保険・支援金は給与計算側の共通の端数処理を使います。' : ''}'),
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
    if (mounted && generation == _generation && action != null && !_hasPendingInput) await _load();
  }

  Future<void> _openConditions() async {
    if (_busy || _hasPendingInput || _uncertain) return;
    final generation = _generation;
    await widget.openConditions?.call(_month);
    if (mounted && generation == _generation && !_hasPendingInput) await _load();
  }

  void _publishEntryAfterFrame() {
    if (_entryPublishQueued || widget.entryController == null) return;
    _entryPublishQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _entryPublishQueued = false;
      if (!mounted) return;
      final controller = widget.entryController;
      if (controller == null) return;
      controller.attach(this, _openConditions);
      controller.publish(this, PayrollInsuranceEntryState(
        canOpen: widget.openConditions != null && !_busy && !_hasPendingInput && !_uncertain,
        status: _busy ? '設定状況を確認中'
            : !_conditionsKnown ? '設定状況を確認できません'
            : _profile == null ? '未設定（この月に適用する設定なし）'
            : '設定済み（${_month.substring(0, 7)}に適用）',
        editing: _hasPendingInput,
        effectiveFrom: !_busy && _conditionsKnown ? _conditionsStart?.substring(0, 7) : null,
        referenceText: !_busy && _conditionsKnown && _basisReference != null
            ? '保存済み参考期間 ${_basisReference!.from.substring(0, 7)}〜${_basisReference!.to.substring(0, 7)}・平均月収 ${_basisReference!.averageMonthlyIncomeYen}円' : null,
      ));
    });
  }

  @override
  Widget build(BuildContext context) {
    _publishEntryAfterFrame();
    return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (widget.entryController == null && widget.openConditions != null)
        Card(
          key: const ValueKey('insurance-settings-entry'),
          child: Padding(padding: const EdgeInsets.all(10), child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FilledButton.icon(
                key: const ValueKey('insurance-settings-open'),
                onPressed: _busy || _hasPendingInput || _uncertain ? null : _openConditions,
                icon: const Icon(Icons.settings_outlined),
                label: const Text('保険料を設定'),
              ),
              Text(_busy ? '設定状況を確認中'
                  : !_conditionsKnown ? '設定状況を確認できません'
                  : _profile == null ? '未設定（この月に適用する設定なし）'
                  : '設定済み（${_month.substring(0, 7)}に適用）',
                key: const ValueKey('insurance-settings-status')),
              const Text('加入条件・平均月収・適用開始月を設定します。'),
              if (_hasPendingInput)
                const Text('入力中の修正を保存してから設定を開いてください。'),
            ],
          )),
        ),
      Offstage(offstage: !widget.showAmounts, child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
      Row(children: [
        if (widget.month == null)
          IconButton(key: const ValueKey('deductions-previous-month'),
            tooltip: '前月', onPressed: _busy || _hasPendingInput || _uncertain
                ? null : () => _moveMonth(-1),
            icon: const Icon(Icons.chevron_left)),
        Expanded(child: Text('${_month.substring(0, 7)}分・給料明細と連動')),
        if (widget.month == null)
          IconButton(key: const ValueKey('deductions-next-month'),
            tooltip: '翌月', onPressed: _busy || _hasPendingInput || _uncertain
                ? null : () => _moveMonth(1),
            icon: const Icon(Icons.chevron_right)),
      ]),
      if (_hasPendingInput)
        const Text('月を切り替える前に修正額の保存・読込の完了を確認してください。'),
      if (_busy) const LinearProgressIndicator(),
      if (_error != null) Text(_error!),
      if (!_busy && _allowed && !_reasonContractAvailable)
        const Text('手動調整を利用できません。管理者に確認してください。'),
      if (!_busy && _savedCalculation)
        const Text('保存済み明細の計算結果を表示しています。現在の条件での再計算は行っていません。'),
      if (!_busy && _error == null && _profile == null && !_savedCalculation)
        Card(
          key: const ValueKey('deduction-conditions-missing'),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('この月の本人の計算条件が未設定です。'),
                const Text('空欄は保険料0円を意味しません。保存済みの金額は保持しています。'),
                const ExpansionTile(
                  title: Text('設定する条件について'),
                  children: [
                    Padding(
                      padding: EdgeInsets.all(12),
                      child: Text('会社の料率に加えて、本人の加入条件・標準報酬月額を確認してください。介護保険では生年月日も必要です。正しい月額を個別入力する方法もあります。'),
                    ),
                  ],
                ),
                if (widget.entryController == null && widget.openConditions != null)
                  TextButton(
                    onPressed: _hasPendingInput || _uncertain
                        ? null : _openConditions,
                    child: const Text('保険料の基準・適用月'),
                  ),
              ],
            ),
          ),
        ),
      if (widget.entryController == null && !_busy && _profile != null && !_savedCalculation && widget.openConditions != null)
        TextButton(onPressed: _hasPendingInput || _uncertain ? null : _openConditions,
          child: const Text('保険料の基準・適用月')),
      if (widget.entryController == null && !_busy && _basisReference != null)
        Text('対象期間 ${_basisReference!.from.substring(0, 7)}〜${_basisReference!.to.substring(0, 7)}・平均月収 ${_basisReference!.averageMonthlyIncomeYen}円'),
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
                enabled: _canAdjust(item.$1) &&
                    (!_needsAdjustmentAction(item.$1) || _adjusting.containsKey(item.$1)),
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => FocusManager.instance.primaryFocus?.unfocus(),
                decoration: InputDecoration(labelText: item.$2, suffixText: '円',
                  helperText: _amountStatus(item.$1),
                  border: const OutlineInputBorder()),
                onChanged: (_) => setState(() { _manual.add(item.$1); _dirty = true; }),
              ),
              Wrap(spacing: 8, children: [
                if (_needsAdjustmentAction(item.$1) && item.$1 != 'child_support')
                  if (_adjusting.containsKey(item.$1))
                    TextButton(key: ValueKey('fixed-deduction-${item.$1}-cancel-adjustment'),
                      onPressed: _canAdjust(item.$1) ? () => _cancelAdjustment(item.$1) : null,
                      child: const Text('調整をキャンセル'))
                  else
                    TextButton(key: ValueKey('fixed-deduction-${item.$1}-begin-adjustment'),
                      onPressed: _canAdjust(item.$1) ? () => _beginAdjustment(item.$1) : null,
                      child: const Text('手動で調整')),
                if (_manual.contains(item.$1))
                  const Padding(padding: EdgeInsets.symmetric(vertical: 10),
                    child: Text('手動調整中')),
                TextButton(onPressed: () => _formula(item.$1, item.$2),
                  child: const Text('計算式・設定')),
                if (item.$1 == 'child_support' && !_busy && !_savedCalculation &&
                    _error == null && _profile?['insurance_mode'] == 'rates')
                  const Padding(padding: EdgeInsets.symmetric(vertical: 10),
                    child: Text('自動計算専用')),
                if (_manual.contains(item.$1) && (_profile?['insurance_mode'] != 'manual' || item.$1 == 'income_tax'))
                  TextButton(onPressed: _canAdjust(item.$1) ? () => setState(() {
                    _manual.remove(item.$1);
                    _adjusting.remove(item.$1);
                    _controllers[item.$1]!.text = _automatic[item.$1]?.toString() ?? '';
                    _dirty = true;
                  }) : null, child: const Text('自動計算に戻す')),
              ]),
            ],
          )),
        ),
      if (_profile?['insurance_mode'] != 'rates' && _profile?['insurance_mode'] != 'manual' && widget.legacySocialAmount > 0)
        Text('保険料の個別計算条件を設定してください。以前の一括設定${widget.legacySocialAmount.toStringAsFixed(0)}円は保持されています。'),
      FilledButton(onPressed: widget.canEdit && _allowed && _reasonContractAvailable && _dirty && !_busy && !_uncertain ? _save : null,
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
            widget.residentTaxBuilder?.call(_month, (editing) {
              if (mounted && _residentEditing != editing) {
                setState(() => _residentEditing = editing);
              }
            }) ?? widget.residentTax,
          ],
        )),
      ),
        ],
      )),
    ],
  );
  }
}




