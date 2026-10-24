import 'dart:convert';

import 'package:flutter/material.dart';
import '../../data/supabase_backend.dart';
import 'payroll_insurance_basis_reference.dart';
import 'payroll_insurance_basis_section.dart';

typedef PayrollTaxRpc = Future<dynamic> Function(String, Map<String, dynamic>);

const manualPayrollInsuranceLabels = <String, String>{
  'employment_insurance': '雇用保険料',
  'health_insurance': '健康保険料',
  'pension_insurance': '厚生年金保険',
  'nursing_insurance': '介護保険料',
  'child_support': '子ども・子育て支援金',
};

bool validManualPayrollInsurance(Map value) {
  final premiums = value['manual_insurance_premiums'];
  if (premiums is! Map || premiums.length != manualPayrollInsuranceLabels.length ||
      manualPayrollInsuranceLabels.keys.any((key) => premiums[key] is! int ||
          (premiums[key] as int) < 0 || (premiums[key] as int) > 2147483647)) {
    return false;
  }
  if (premiums.values.fold<int>(0, (sum, amount) => sum + (amount as int)) > 2147483647) return false;
  const allowed = {'insurance_mode', 'manual_insurance_premiums', 'income_mode',
    'dependents', 'non_taxable_yen', 'additional_social_deduction_yen', 'deduction_overrides',
    'insurance_basis_reference'};
  if (value.keys.any((key) => !allowed.contains(key))) return false;
  if (value['insurance_basis_reference'] != null) {
    try { PayrollInsuranceBasisReference.fromJson(value['insurance_basis_reference']); }
    on FormatException { return false; }
  }
  final overrides = value['deduction_overrides'];
  return overrides == null || (overrides is Map && overrides.keys.every((key) => key == 'income_tax') &&
    overrides.values.every((amount) => amount is int && amount >= 0 && amount <= 2147483647));
}


/// Conditions are effective-dated; existing fixed amounts remain stored.
class PayrollTaxConditionsPage extends StatefulWidget {
  const PayrollTaxConditionsPage({
    super.key,
    required this.companyId,
    required this.workerId,
    this.rpc,
    this.month,
  });
  final String companyId;
  final String workerId;
  final PayrollTaxRpc? rpc;
  /// Month being inspected, rather than the month of the newest saved profile.
  final DateTime? month;
  @override
  State<PayrollTaxConditionsPage> createState() =>
      _PayrollTaxConditionsPageState();
}

class _PayrollTaxConditionsPageState extends State<PayrollTaxConditionsPage> {
  final _form = GlobalKey<FormState>();
  final _month = TextEditingController();
  final _birth = TextEditingController();
  final _amounts = <String, TextEditingController>{
    for (final key in const [
      'health_base_yen',
      'pension_base_yen',
      'dependents',
      'non_taxable_yen',
      'employment_excluded_yen',
      'additional_social_deduction_yen',
    ])
      key: TextEditingController(text: '0'),
  };
  final _manualPremiums = <String, TextEditingController>{
    for (final key in manualPayrollInsuranceLabels.keys) key: TextEditingController(),
  };
  bool _manualSupported = false;
  bool _basisSupported = false;
  PayrollInsuranceBasisReference? _basisReference, _loadedBasisReference;
  int _basisEditorRevision = 0;
  final _flags = <String, bool>{
    for (final key in const [
      'health',
      'pension',
      'employment',
      'nursing',
      'child_support',
    ])
      key: false,
  };
  Map<String, dynamic> _deductionOverrides = {};
  String _insurance = 'rates';
  String _income = 'koh';
  bool _initialConditionsConfirmed = false;
  bool _busy = true;
  bool _loading = true;
  bool _canEdit = false;
  bool _uncertain = false;
  String? _error;
  String? _message;
  List<Map<String, dynamic>> _items = [];
  int _generation = 0;
  String? _actor;

  String get _targetMonth {
    final date = widget.month ?? DateTime.now();
    return '${date.year}-${date.month.toString().padLeft(2, '0')}';
  }

  Future<dynamic> _rpc(String name, Map<String, dynamic> params) {
    if (widget.rpc != null) return widget.rpc!(name, params);
    if (SupabaseBackend.client.auth.currentUser?.id != _actor ||
        _actor == null) {
      throw StateError('ログイン状態が変わりました。画面を開き直してください。');
    }
    return SupabaseBackend.client.rpc(name, params: params);
  }

  Map<String, dynamic> get _scope => {
    'p_company_id': widget.companyId,
    'p_worker_id': widget.workerId,
  };

  @override
  void initState() {
    super.initState();
    if (widget.rpc == null && SupabaseBackend.isInitialized) {
      _actor = SupabaseBackend.client.auth.currentUser?.id;
    }
    _month.text = _targetMonth;
    _load();
  }

  @override
  void didUpdateWidget(covariant PayrollTaxConditionsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.companyId != widget.companyId ||
        oldWidget.workerId != widget.workerId ||
        oldWidget.month != widget.month) {
      _items = [];
      _message = null;
      _load();
    }
  }

  @override
  void dispose() {
    _month.dispose();
    _birth.dispose();
    for (final c in _manualPremiums.values) { c.dispose(); }
    for (final c in _amounts.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _accept(dynamic raw) {
    if (raw is! Map ||
        raw['company_id'] != widget.companyId ||
        raw['worker_id'] != widget.workerId ||
        raw['items'] is! List ||
        raw['can_edit'] is! bool) {
      throw const FormatException('計算条件の取得結果を確認できません');
    }
    final items = <Map<String, dynamic>>[];
    for (final row in raw['items'] as List) {
      if (row is! Map ||
          row['value'] is! Map ||
          row['version'] is! int ||
          (row['version'] as int) < 1 ||
          row['starts_on'] is! String) {
        throw const FormatException('計算条件の形式を確認できません');
      }
      final value = row['value'] as Map;
      if (!RegExp(
            r'^20\d{2}-(0[1-9]|1[0-2])-01$',
          ).hasMatch(row['starts_on'] as String) ||
          !const ['fixed', 'rates', 'manual'].contains(value['insurance_mode']) ||
          !const ['fixed', 'koh', 'otsu'].contains(value['income_mode']) ||
          (value['insurance_mode'] == 'manual'
              ? !validManualPayrollInsurance(value) ||
                  const ['dependents', 'non_taxable_yen', 'additional_social_deduction_yen'].any((k) => value[k] is! int || (value[k] as int) < 0)
              : _flags.keys.any((k) => value[k] is! bool) ||
                  _amounts.keys.any((k) => value[k] is! int || (value[k] as int) < 0)) ||
          (value['birth_date'] != null && value['birth_date'] is! String)) {
        throw const FormatException('税計算条件の内容を確認できません');
      }
      if (value['insurance_basis_reference'] != null) {
        PayrollInsuranceBasisReference.fromJson(value['insurance_basis_reference']);
      }
      items.add(Map<String, dynamic>.from(row));
    }
    items.sort((a, b) =>
        (b['starts_on'] as String).compareTo(a['starts_on'] as String));
    _items = items;
    _manualSupported = raw['manual_insurance_contract_version'] == 1;
    _basisSupported = raw['insurance_basis_reference_contract_version'] == 1;
    _canEdit = raw['can_edit'] == true &&
        (_manualSupported || !items.any((row) => (row['value'] as Map)['insurance_mode'] == 'manual')) &&
        (_basisSupported || !items.any((row) => (row['value'] as Map)['insurance_basis_reference'] != null));
  }

  void _fill(Map<String, dynamic> row) {
    final value = row['value'] as Map;
    _month.text = (row['starts_on'] as String).substring(0, 7);
    _basisReference = value['insurance_basis_reference'] == null ? null :
        PayrollInsuranceBasisReference.fromJson(value['insurance_basis_reference']);
    _loadedBasisReference = _basisReference;
    _basisEditorRevision++;
    _insurance = value['insurance_mode'] as String;
    _income = value['income_mode'] as String;
    _birth.text = value['birth_date'] as String? ?? '';
    _deductionOverrides = value['deduction_overrides'] is Map
        ? Map<String, dynamic>.from(value['deduction_overrides'] as Map) : {};
    for (final key in _amounts.keys) {
      _amounts[key]!.text = '${value[key] ?? 0}';
    }
    for (final key in _flags.keys) {
      _flags[key] = value[key] == true;
    }
    for (final entry in _manualPremiums.entries) {
      final premiums = value['manual_insurance_premiums'];
      entry.value.text = premiums is Map && premiums[entry.key] is int ? '${premiums[entry.key]}' : '';
    }
    if (_insurance == 'manual') _initialConditionsConfirmed = false;
  }

  void _resetInitialConditions() {
    _month.text = _targetMonth;
    _basisReference = null;
    _loadedBasisReference = null;
    _basisEditorRevision++;
    _deductionOverrides = {};
    for (final c in _manualPremiums.values) { c.clear(); }
    _insurance = 'rates';
    _income = 'koh';
    _birth.clear();
    for (final controller in _amounts.values) {
      controller.text = '0';
    }
    for (final key in _flags.keys) {
      _flags[key] = false;
    }
    _flags['health'] = true;
    _flags['pension'] = true;
    _initialConditionsConfirmed = false;
  }

  String get _insurancePlan => _flags['health']! && _flags['pension']!
      ? 'kenpo'
      : !_flags['health']! && !_flags['pension']!
      ? 'kokuho'
      : 'custom';

  bool get _needsInitialConfirmation =>
      _insurance == 'manual' || (_items.isEmpty && (_income != 'fixed' || _insurance != 'fixed'));

  Future<void> _load() async {
    final generation = ++_generation;
    setState(() {
      _busy = true;
      _loading = true;
      _error = null;
      _canEdit = false;
    });
    try {
      final raw = await readPayrollTaxConditionsWithInsuranceReference((name, params) async {
        final response = await _rpc(name, params);
        if (widget.rpc == null && SupabaseBackend.client.auth.currentUser?.id != _actor) {
          throw StateError('ログイン状態が変わりました');
        }
        return response;
      }, _scope);
      if (!mounted || generation != _generation) return;
      _accept(raw);
      if (_items.isNotEmpty) {
        final month = '$_targetMonth-01';
        // Calculation uses the latest profile effective on the target month.
        // Future profiles remain available for deliberate editing.
        _fill(_items.where((e) =>
            (e['starts_on'] as String).compareTo(month) <= 0).firstOrNull ??
            _items.first);
      } else {
        _resetInitialConditions();
      }
      _uncertain = false;
    } catch (_) {
      if (!mounted || generation != _generation) return;
      _canEdit = false;
      _items = [];
      _error = '税計算条件を取得できません。サーバーの接続状態を確認して再読み込みしてください。';
    } finally {
      if (mounted && generation == _generation) {
        setState(() {
          _busy = false;
          _loading = false;
        });
      }
    }
  }

  Future<void> _save() async {
    if (_needsInitialConfirmation && !_initialConditionsConfirmed) return;
    if (_insurance == 'manual' && !_manualSupported) return;
    final generation = _generation;
    if (!_form.currentState!.validate()) return;
    final start = '${_month.text}-01';
    final referenceToSave = _basisReference ?? _loadedBasisReference;
    final value = <String, dynamic>{
      'insurance_mode': _insurance,
      'income_mode': _income,
      if (_basisSupported && referenceToSave != null)
        'insurance_basis_reference': referenceToSave.toJson(),
      if (_insurance == 'manual') ...{
        'manual_insurance_premiums': {for (final e in _manualPremiums.entries) e.key: int.parse(e.value.text)},
        for (final key in const ['dependents', 'non_taxable_yen', 'additional_social_deduction_yen']) key: int.parse(_amounts[key]!.text),
        if (_deductionOverrides.containsKey('income_tax')) 'deduction_overrides': {'income_tax': _deductionOverrides['income_tax']},
      } else ...{
        'birth_date': _birth.text.isEmpty ? null : _birth.text,
        if (_deductionOverrides.isNotEmpty) 'deduction_overrides': _deductionOverrides,
        ..._flags,
        for (final key in _amounts.keys) key: int.parse(_amounts[key]!.text),
      },
    };
    if (_insurance == 'manual' && !validManualPayrollInsurance(value)) {
      setState(() => _error = '保険別の月額と合計を確認してください。空欄は保存できません。');
      return;
    }
    final previous = _items.where((e) => e['starts_on'] == start).firstOrNull;
    final version = previous?['version'] ?? 0;
    setState(() {
      _busy = true;
      _error = null;
      _message = null;
    });
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('給与の税計算を保存'),
        content: SingleChildScrollView(
          child: Text(
            '${_month.text}分から適用します。\n'
            '${referenceToSave == null ? '' : _basisSupported
                ? '参考期間：${referenceToSave.from.substring(0, 7)}〜${referenceToSave.to.substring(0, 7)}\n平均月収（参考額）：${referenceToSave.averageMonthlyIncomeYen}円\n標準報酬月額へ自動換算しません。\n'
                : '対象期間・平均月収は未保存です。この保存では標準報酬月額など既存条件だけを保存します。\n'}'
            '所得税：${_income == 'fixed'
                ? '個別設定の固定月額'
                : _income == 'koh'
                ? '月額表・甲欄'
                : '月額表・乙欄'}\n'
            '社会保険：${_insurance == 'manual' ? '保険別の個別手入力月額' : _insurance == 'fixed' ? '個別設定の固定月額' : '会社の登録料率'}\n'
            '扶養人数：${value['dependents']}人\n'
            '${_insurance == 'manual'
                ? manualPayrollInsuranceLabels.entries.map((e) => '${e.value}：${(value['manual_insurance_premiums'] as Map)[e.key]}円').join('\n')
                : '健康保険の標準報酬月額：${value['health_base_yen']}円\n厚生年金の標準報酬月額：${value['pension_base_yen']}円'}\n'
            '非課税支給額：${value['non_taxable_yen']}円\n'
            '${_insurance == 'manual' ? '' : '雇用保険対象外額：${value['employment_excluded_yen']}円\n'}'
            '他項目で控除済みの社会保険料等：${value['additional_social_deduction_yen']}円\n\n'
            '対象の未確定給与を再計算します。${_insurance == 'manual' ? '本人負担月額・適用月・所得税の方式' : '加入条件・標準報酬・扶養申告・非課税額'}を確認してください。'
            '確定済み給与は変更しません。',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('戻る'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('確認して保存'),
          ),
        ],
      ),
    );
    if (!mounted || generation != _generation) return;
    if (confirmed != true) {
      setState(() => _busy = false);
      return;
    }
    try {
      final raw = await _rpc('save_worker_payroll_tax_conditions', {
        ..._scope,
        'p_starts_on': start,
        'p_expected_version': version,
        'p_value': value,
        'p_confirmed': true,
      });
      if (!mounted || generation != _generation) return;
      _accept(raw);
      final saved = _items.where((e) => e['starts_on'] == start).firstOrNull;
      if (saved == null ||
          saved['version'] != version + 1 ||
          !_same(saved['value'], value)) {
        throw const FormatException('保存結果が一致しません');
      }
      if (_basisSupported || referenceToSave == null) _fill(saved);
      _message = '保存しました。対象の未確定給与へ反映しました。'
          '${!_basisSupported && referenceToSave != null ? '対象期間・平均月収は未保存です。' : ''}';
    } catch (e) {
      if (!mounted || generation != _generation) return;
      _uncertain = true;
      _error = '保存結果を確認できません。再読み込みして保存された条件を確認してください。\n$e';
    } finally {
      if (mounted && generation == _generation) setState(() => _busy = false);
    }
  }

  bool _same(dynamic a, dynamic b) {
    if (a is Map && b is Map) {
      return a.length == b.length &&
          a.keys.every((k) => b.containsKey(k) && _same(a[k], b[k]));
    }
    return jsonEncode(a) == jsonEncode(b);
  }

  Widget _amount(String key, String label) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: TextFormField(
      controller: _amounts[key],
      enabled: _canEdit && !_busy && !_uncertain,
      keyboardType: TextInputType.number,
      decoration: InputDecoration(labelText: label),
      validator: (s) {
        if (_insurance == 'rates' &&
            ((key == 'health_base_yen' && _flags['health']!) ||
                (key == 'pension_base_yen' && _flags['pension']!)) &&
            (int.tryParse(s ?? '') ?? 0) <= 0) {
          return '加入している保険の標準報酬月額を入力してください';
        }
        return s == null ||
                !RegExp(r'^\d{1,9}$').hasMatch(s) ||
                (key == 'dependents' && int.parse(s) > 99)
            ? '0以上の整数を入力してください'
            : null;
      },
    ),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('保険料の基準・税計算'), toolbarHeight: kToolbarHeight,
      actions: [IconButton(key: const ValueKey('insurance-basis-help'),
        tooltip: '設定ヘルプ', icon: const Icon(Icons.help_outline),
        onPressed: () => showDialog<void>(context: context, builder: (context) => AlertDialog(
          title: const Text('対象期間・平均月収・標準報酬月額'),
          content: const SingleChildScrollView(child: Text('平均月収は、指定した給与対象月の控除前支給総額を確認する参考額です。未登録月を0円として平均しません。支給日は明細の記録を表示し、記録が無い場合は勤務月で代用しません。\n\n平均月収から法定の標準報酬月額への自動換算は行いません。健康保険と厚生年金の標準報酬月額は、確認した額をそれぞれ入力してください。\n\n適用開始月から対象の未確定給与へ既存計算で反映します。確定済み給与は変更しません。')),
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('閉じる'))],
        )))],
    ),
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : _error != null && !_uncertain
        ? Center(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_error!),
                  TextButton(onPressed: _load, child: const Text('再読み込み')),
                ],
              ),
            ),
          )
        : Form(
            key: _form,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Text('月払い給与の所得税と保険料を設定します。住民税は個別の月額設定を使います。'),
                if (_items.isNotEmpty && !_items.any((e) =>
                    (e['starts_on'] as String).compareTo('$_targetMonth-01') <= 0))
                  Text('$_targetMonth分に適用される税計算条件は未登録です。表示中の登録済み条件は将来分です。'),
                if (_deductionOverrides.isNotEmpty)
                  const Text('個別給与設定で保存した手入力修正を保持します。解除は控除の月単位で「自動計算に戻す」を選んでください。'),
                if (_error != null)
                  Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                if (_message != null) Text(_message!),
                if (_items.isEmpty && _error == null)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'はじめての自動計算設定',
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            '初期設定は自動計算です。次の内容を確認して保存すると、給与へ反映されます。\n'
                            '① 所得税の甲欄・乙欄と扶養人数を確認\n'
                            '② けんぽ／国保を選び、加入している保険の標準報酬月額を入力\n'
                            '③ 適用開始月と会社の登録料率を確認して保存',
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            '保険の未選択は未加入として保存されます。保存までは従来の固定月額を使用します。'
                            '登録済みの条件は、再インストールしても引き継ぎます。',
                          ),
                        ],
                      ),
                    ),
                  ),
                if (_items.isNotEmpty)
                  DropdownButtonFormField<String>(
                    key: ValueKey('${widget.companyId}/${widget.workerId}/${_month.text}'),
                    initialValue: _items.any((e) => e['starts_on'] == '${_month.text}-01')
                        ? '${_month.text}-01' : null,
                    decoration: const InputDecoration(labelText: '登録済みの適用月'),
                    items: [
                      for (final item in _items)
                        DropdownMenuItem(
                          value: item['starts_on'] as String,
                          child: Text(
                            (item['starts_on'] as String).substring(0, 7),
                          ),
                        ),
                    ],
                    onChanged: _busy || _uncertain
                        ? null
                        : (v) {
                            if (v != null) {
                              setState(
                                () => _fill(
                                  _items.firstWhere((e) => e['starts_on'] == v),
                                ),
                              );
                            }
                          },
                  ),
                TextFormField(
                  controller: _month,
                  enabled: _canEdit && !_busy && !_uncertain,
                  decoration: const InputDecoration(
                    labelText: '適用開始月（YYYY-MM）',
                  ),
                  validator: (v) =>
                      v != null &&
                          RegExp(r'^20\d{2}-(0[1-9]|1[0-2])$').hasMatch(v)
                      ? null
                      : '年月を入力してください',
                ),
                PayrollInsuranceBasisSection(
                  key: ValueKey('insurance-basis-${widget.companyId}/${widget.workerId}/$_basisEditorRevision'),
                  month: '$_targetMonth-01', supported: _basisSupported,
                  enabled: _canEdit && !_busy && !_uncertain,
                  initialReference: _basisReference,
                  readHistory: (from, to) async {
                    final generation = _generation;
                    final result = await PayrollInsuranceIncomeHistoryRepository((name, params) async {
                      final raw = await _rpc(name, params);
                      if (widget.rpc == null && SupabaseBackend.client.auth.currentUser?.id != _actor) {
                        throw StateError('ログイン状態が変わりました');
                      }
                      return raw;
                    }).read(companyId: widget.companyId, workerId: widget.workerId, from: from, to: to);
                    if (!mounted || generation != _generation) throw StateError('対象が変わりました');
                    return result;
                  },
                  onChanged: (value) { _basisReference = value; },
                ),
                DropdownButtonFormField<String>(
                  key: ValueKey('income-$_income'),
                  initialValue: _income,
                  decoration: const InputDecoration(labelText: '所得税'),
                  items: [
                    const DropdownMenuItem(value: 'fixed', child: Text('個別設定の固定月額')),
                    const DropdownMenuItem(value: 'koh', child: Text('自動計算・月額表甲欄')),
                    const DropdownMenuItem(value: 'otsu', child: Text('自動計算・月額表乙欄')),
                  ],
                  onChanged: _canEdit && !_busy && !_uncertain
                      ? (v) => setState(() => _income = v!)
                      : null,
                ),
                const Text('自動計算は令和8年分の国税庁月額表に対応。日払い・賞与は対象外です。'),
                _amount(
                  'dependents',
                  _income == 'otsu'
                      ? '従たる給与の申告書に記載した扶養人数'
                      : '申告書に基づく扶養親族等の人数（加算分を含む）',
                ),
                DropdownButtonFormField<String>(
                  key: ValueKey('insurance-$_insurance'),
                  initialValue: _insurance,
                  decoration: const InputDecoration(labelText: '保険料'),
                  items: [
                    if (_manualSupported || _insurance == 'manual')
                      DropdownMenuItem(value: 'manual', enabled: _manualSupported,
                        child: const Text('保険別の月額を手入力')),
                    const DropdownMenuItem(value: 'fixed', child: Text('個別設定の固定月額')),
                    const DropdownMenuItem(
                      value: 'rates',
                      child: Text('会社の登録料率で自動計算'),
                    ),
                  ],
                  onChanged: _canEdit && !_busy && !_uncertain
                      ? (v) => setState(() {
                          _insurance = v!;
                          if (v == 'manual' && _items.isEmpty) _income = 'fixed';
                          _initialConditionsConfirmed = false;
                        })
                      : null,
                ),
                if (_insurance == 'manual') ...[
                  const Text('通知書などに記載された本人負担の月額を入力してください。会社負担分は含めません。該当しない項目も0円を入力します。加入条件や標準報酬からは推測しません。'),
                  for (final entry in manualPayrollInsuranceLabels.entries)
                    TextFormField(
                      key: ValueKey('manual-insurance-${entry.key}'),
                      controller: _manualPremiums[entry.key],
                      enabled: _manualSupported && _canEdit && !_busy && !_uncertain,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(labelText: '${entry.value}（本人負担月額）', suffixText: '円'),
                      validator: (text) => text != null && RegExp(r'^\d{1,10}$').hasMatch(text) &&
                          int.parse(text) <= 2147483647 ? null : '月額を入力してください。該当なしは0円',
                    ),
                ],
                if (_insurance == 'rates') ...[
                  DropdownButtonFormField<String>(
                    key: ValueKey('insurance-plan-$_insurancePlan'),
                    initialValue: _insurancePlan,
                    decoration: const InputDecoration(labelText: '加入保険'),
                    items: const [
                      DropdownMenuItem(value: 'kenpo', child: Text('けんぽ')),
                      DropdownMenuItem(
                        value: 'kokuho',
                        child: Text('国保・社会保険未加入'),
                      ),
                      DropdownMenuItem(
                        value: 'custom',
                        enabled: false,
                        child: Text('個別に選択'),
                      ),
                    ],
                    onChanged: _canEdit && !_busy && !_uncertain
                        ? (v) {
                            if (v == 'custom') return;
                            setState(() {
                              _flags['health'] = v == 'kenpo';
                              _flags['pension'] = v == 'kenpo';
                            });
                          }
                        : null,
                  ),
                  const Text('国保へ切り替えると健康保険・厚生年金を外します。その他の項目は個別に確認してください。'),
                  for (final item in const {
                    'health': '健康保険',
                    'pension': '厚生年金',
                    'employment': '雇用保険',
                    'nursing': '介護保険（40〜64歳を自動判定）',
                    'child_support': '子ども・子育て支援金',
                  }.entries)
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(item.value),
                      value: _flags[item.key],
                      onChanged: _canEdit && !_busy && !_uncertain
                          ? (v) => setState(() => _flags[item.key] = v!)
                          : null,
                    ),
                  _amount('health_base_yen', '健康保険の標準報酬月額（円）'),
                  _amount('pension_base_yen', '厚生年金の標準報酬月額（円）'),
                  TextFormField(
                    controller: _birth,
                    enabled: _canEdit && !_busy && !_uncertain,
                    decoration: const InputDecoration(
                      labelText: '生年月日（YYYY-MM-DD）',
                    ),
                    validator: (v) =>
                        _flags['nursing']! &&
                            (v == null ||
                                !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(v))
                        ? '生年月日を入力してください'
                        : null,
                  ),
                ],
                _amount('non_taxable_yen', '支給額のうち非課税分（月額・円）'),
                if (_insurance != 'manual') _amount('employment_excluded_yen', '支給額のうち雇用保険対象外分（月額・円）'),
                _amount(
                  'additional_social_deduction_yen',
                  '他項目で控除済みの社会保険料等（月額・円）',
                ),
                const Text(
                  '自動計算へ切り替える税・保険料を自由控除にも登録している場合は、二重控除にならないよう確認してください。',
                ),
                if (_canEdit && _needsInitialConfirmation)
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(_insurance == 'manual' ? '本人負担の各月額・該当なしの0円・適用月を確認しました' : '扶養人数・保険の加入／未加入・標準報酬月額を確認しました'),
                    value: _initialConditionsConfirmed,
                    onChanged: _busy || _uncertain
                        ? null
                        : (v) =>
                              setState(() => _initialConditionsConfirmed = v!),
                  ),
                if (_canEdit)
                  FilledButton(
                    onPressed:
                        _busy ||
                            _uncertain ||
                            (_needsInitialConfirmation &&
                                !_initialConditionsConfirmed)
                        ? null
                        : _save,
                    child: const Text('確認して保存'),
                  ),
                TextButton(
                  onPressed: _busy ? null : _load,
                  child: const Text('再読み込み'),
                ),
              ],
            ),
          ),
  );
}

