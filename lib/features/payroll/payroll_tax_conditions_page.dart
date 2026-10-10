import 'dart:convert';

import 'package:flutter/material.dart';
import '../../data/supabase_backend.dart';

typedef PayrollTaxRpc = Future<dynamic> Function(String, Map<String, dynamic>);

/// Conditions are effective-dated; existing fixed amounts remain stored.
class PayrollTaxConditionsPage extends StatefulWidget {
  const PayrollTaxConditionsPage({
    super.key,
    required this.companyId,
    required this.workerId,
    this.rpc,
  });
  final String companyId;
  final String workerId;
  final PayrollTaxRpc? rpc;
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
  String _insurance = 'fixed';
  String _income = 'fixed';
  bool _busy = true;
  bool _loading = true;
  bool _canEdit = false;
  bool _uncertain = false;
  String? _error;
  String? _message;
  List<Map<String, dynamic>> _items = [];
  int _generation = 0;
  String? _actor;

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
    final today = DateTime.now();
    _month.text = '${today.year}-${today.month.toString().padLeft(2, '0')}';
    _load();
  }

  @override
  void didUpdateWidget(covariant PayrollTaxConditionsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.companyId != widget.companyId ||
        oldWidget.workerId != widget.workerId) {
      _items = [];
      _message = null;
      _load();
    }
  }

  @override
  void dispose() {
    _month.dispose();
    _birth.dispose();
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
          !const ['fixed', 'rates'].contains(value['insurance_mode']) ||
          !const ['fixed', 'koh', 'otsu'].contains(value['income_mode']) ||
          _flags.keys.any((k) => value[k] is! bool) ||
          _amounts.keys.any((k) => value[k] is! int || (value[k] as int) < 0) ||
          (value['birth_date'] != null && value['birth_date'] is! String)) {
        throw const FormatException('税計算条件の内容を確認できません');
      }
      items.add(Map<String, dynamic>.from(row));
    }
    _items = items;
    _canEdit = raw['can_edit'] == true;
  }

  void _fill(Map<String, dynamic> row) {
    final value = row['value'] as Map;
    _month.text = (row['starts_on'] as String).substring(0, 7);
    _insurance = value['insurance_mode'] as String;
    _income = value['income_mode'] as String;
    _birth.text = value['birth_date'] as String? ?? '';
    for (final key in _amounts.keys) {
      _amounts[key]!.text = '${value[key]}';
    }
    for (final key in _flags.keys) {
      _flags[key] = value[key] == true;
    }
  }

  Future<void> _load() async {
    final generation = ++_generation;
    setState(() {
      _busy = true;
      _loading = true;
      _error = null;
      _canEdit = false;
    });
    try {
      final raw = await _rpc('read_worker_payroll_tax_conditions', _scope);
      if (!mounted || generation != _generation) return;
      _accept(raw);
      if (_items.isNotEmpty) _fill(_items.first);
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
    final generation = _generation;
    if (!_form.currentState!.validate()) return;
    final start = '${_month.text}-01';
    final value = <String, dynamic>{
      'insurance_mode': _insurance,
      'income_mode': _income,
      'birth_date': _birth.text.isEmpty ? null : _birth.text,
      ..._flags,
      for (final key in _amounts.keys) key: int.parse(_amounts[key]!.text),
    };
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
            '所得税：${_income == 'fixed'
                ? '個別設定の固定月額'
                : _income == 'koh'
                ? '月額表・甲欄'
                : '月額表・乙欄'}\n'
            '社会保険：${_insurance == 'fixed' ? '個別設定の固定月額' : '会社の登録料率'}\n'
            '扶養人数：${value['dependents']}人\n'
            '健康保険の標準報酬月額：${value['health_base_yen']}円\n'
            '厚生年金の標準報酬月額：${value['pension_base_yen']}円\n'
            '非課税支給額：${value['non_taxable_yen']}円\n'
            '雇用保険対象外額：${value['employment_excluded_yen']}円\n'
            '他項目で控除済みの社会保険料等：${value['additional_social_deduction_yen']}円\n\n'
            '対象の未確定給与を再計算します。加入条件・標準報酬・扶養申告・非課税額を確認してください。'
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
      _message = '保存しました。対象の未確定給与へ反映しました。';
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
      validator: (s) =>
          s == null ||
              !RegExp(r'^\d{1,9}$').hasMatch(s) ||
              (key == 'dependents' && int.parse(s) > 99)
          ? '0以上の整数を入力してください'
          : null,
    ),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('給与の税計算'), toolbarHeight: kToolbarHeight),
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
                if (_error != null)
                  Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                if (_message != null) Text(_message!),
                if (_items.isEmpty && _error == null)
                  const Text('未設定：現在は従来の固定月額を使用しています。'),
                if (_items.isNotEmpty)
                  DropdownButtonFormField<String>(
                    initialValue: _items.first['starts_on'] as String,
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
                DropdownButtonFormField<String>(
                  key: ValueKey('income-$_income'),
                  initialValue: _income,
                  decoration: const InputDecoration(labelText: '所得税'),
                  items: const [
                    DropdownMenuItem(value: 'fixed', child: Text('個別設定の固定月額')),
                    DropdownMenuItem(value: 'koh', child: Text('自動計算・月額表甲欄')),
                    DropdownMenuItem(value: 'otsu', child: Text('自動計算・月額表乙欄')),
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
                  items: const [
                    DropdownMenuItem(value: 'fixed', child: Text('個別設定の固定月額')),
                    DropdownMenuItem(
                      value: 'rates',
                      child: Text('会社の登録料率で自動計算'),
                    ),
                  ],
                  onChanged: _canEdit && !_busy && !_uncertain
                      ? (v) => setState(() => _insurance = v!)
                      : null,
                ),
                if (_insurance == 'rates') ...[
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
                _amount('employment_excluded_yen', '支給額のうち雇用保険対象外分（月額・円）'),
                _amount(
                  'additional_social_deduction_yen',
                  '他項目で控除済みの社会保険料等（月額・円）',
                ),
                const Text(
                  '自動計算へ切り替える税・保険料を自由控除にも登録している場合は、二重控除にならないよう確認してください。',
                ),
                if (_canEdit)
                  FilledButton(
                    onPressed: _busy || _uncertain ? null : _save,
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
