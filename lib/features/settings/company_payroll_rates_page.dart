import 'dart:math';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'company_payroll_rates_repository.dart';
import 'company_income_tax_page.dart';

const payrollRateConfirmation = '表示された料率・適用年月・情報元をご自身で確認したうえで適用してください';
const payrollScopeInsurers = <String, String>{'unconfigured': '未設定', 'kyokai': '協会けんぽ', 'union': '健康保険組合', 'other': 'その他'};
const payrollScopeBusinesses = <String, String>{'general': '一般の事業', 'agriculture_forestry_fisheries_sake': '農林水産・清酒製造の事業', 'construction': '建設の事業'};

const payrollRateKinds = <String, String>{
  'health_insurance': '健康保険料率',
  'nursing_insurance': '介護保険料率',
  'pension_insurance': '厚生年金保険料率',
  'employment_insurance': '雇用保険料率',
  'child_support': '子ども・子育て支援金率',
};

// User-requested starting inputs, not verified official candidates or saved rates.
// Unspecified child-support shares remain blank until explicitly confirmed.
const payrollManualStartingRates = <String, Map<String, String>>{
  'health_insurance': {'total': '9.9', 'employee': '4.95', 'employer': '4.95'},
  'nursing_insurance': {'total': '1.62', 'employee': '0.81', 'employer': '0.81'},
  'pension_insurance': {'total': '18.3', 'employee': '9.15', 'employer': '9.15'},
  'employment_insurance': {'total': '1.65', 'employee': '0.6', 'employer': '1.05'},
  'child_support': {'total': '0.23'},
};

class CompanyPayrollRatesPage extends StatefulWidget {
  const CompanyPayrollRatesPage({super.key, required this.companyId, this.repository});
  final String companyId;
  final CompanyPayrollRatesRepository? repository;
  @override
  State<CompanyPayrollRatesPage> createState() => _CompanyPayrollRatesPageState();
}

class _CompanyPayrollRatesPageState extends State<CompanyPayrollRatesPage> {
  late CompanyPayrollRatesRepository _repository;
  CompanyPayrollRatesData? _data;
  String? _error;
  bool _busy = false;
  bool _loading = false;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _repository = widget.repository ?? SupabaseCompanyPayrollRatesRepository();
    _load();
  }

  @override
  void didUpdateWidget(covariant CompanyPayrollRatesPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.companyId != widget.companyId || oldWidget.repository != widget.repository) {
      _repository = widget.repository ?? SupabaseCompanyPayrollRatesRepository();
      _data = null;
      _load();
    }
  }

  Future<void> _load() async {
    final generation = ++_generation;
    setState(() { _busy = true; _loading = true; _error = null; });
    try {
      final data = await _repository.read(widget.companyId);
      if (!mounted || generation != _generation) return;
      setState(() => _data = data);
    } catch (_) {
      if (!mounted || generation != _generation) return;
      setState(() { _data = null; _error = '料率設定を取得できませんでした。接続・利用権限・設定機能の導入状況を確認してください。'; });
    } finally {
      if (mounted && generation == _generation) {
        setState(() { _busy = false; _loading = false; });
      }
    }
  }

  Future<bool> _confirm(String title, Map<String, dynamic> value) async =>
      await showDialog<bool>(context: context, builder: (context) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min, children: [
            _valueDetails(value), const SizedBox(height: 16), const Text(payrollRateConfirmation),
            const SizedBox(height: 8), const Text('この操作では給与の計算・確定は行いません。'),
          ])),
        actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('キャンセル')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('確認して適用'))],
      )) ?? false;

  Future<void> _apply(CompanyPayrollRateCandidate candidate, CompanyPayrollRateItem? item) async {
    if (_busy || !_canEdit || !_scopeMatches(candidate)) {
      return;
    }
    final generation = _generation;
    setState(() => _busy = true);
    try {
      final confirmed = await _confirm('確認値を適用', candidate.value);
      if (!mounted || generation != _generation || !confirmed) return;
      await _repository.applyCandidate(companyId: widget.companyId, itemId: candidate.itemId,
        candidateId: candidate.id, expectedVersion: item?.version ?? 0);
      if (!mounted || generation != _generation) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('選択した項目を適用しました')));
      await _load();
    } catch (_) {
      if (mounted && generation == _generation) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('適用結果を確認できません。再読み込みして設定を確認してください。')));
      }
    } finally {
      if (mounted && generation == _generation) setState(() => _busy = false);
    }
  }

  Future<void> _edit(String kind, CompanyPayrollRateItem? item) async {
    if (_busy || !_canEdit) {
      return;
    }
    final generation = _generation;
    setState(() => _busy = true);
    try {
      final value = await showDialog<Map<String, dynamic>>(context: context,
        builder: (_) => _PayrollRateEditor(kind: kind, initialValue: item?.value, companyScope: _data?.companyScope));
      if (!mounted || generation != _generation || value == null) return;
      if (!await _confirm('手動設定を保存', value)) return;
      if (!mounted || generation != _generation) return;
      await _repository.saveManual(companyId: widget.companyId,
        itemId: item?.id ?? (kind == 'custom' ? _newCustomId() : kind), expectedVersion: item?.version ?? 0, value: value);
      if (!mounted || generation != _generation) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('手動設定を保存しました')));
      await _load();
    } catch (_) {
      if (mounted && generation == _generation) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('保存結果を確認できません。再読み込みして設定を確認してください。')));
      }
    } finally {
      if (mounted && generation == _generation) setState(() => _busy = false);
    }
  }

  bool get _canEdit => _data?.canEdit == true;

  bool _scopeMatches(CompanyPayrollRateCandidate candidate) =>
      _data?.companyScope != null && candidate.scopeVersion == _data!.companyScope!.version;

  static Widget _scopeDetails(Map<String, dynamic>? value) {
    if (value == null) return const Text('会社条件は未登録です');
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      Text('保険者 ${payrollScopeInsurers[value['insurer']] ?? '未設定'}'),
      Text('都道府県 ${value['prefecture'] ?? '未設定'}'),
      Text('雇用保険の事業区分 ${payrollScopeBusinesses[value['employment_business']] ?? '未設定'}'),
    ]);
  }

  Future<void> _editScope() async {
    if (_busy || !_canEdit) {
      return;
    }
    final generation = _generation;
    final previous = _data?.companyScope;
    setState(() => _busy = true);
    try {
      final value = await showDialog<Map<String, dynamic>>(context: context,
        builder: (_) => _PayrollScopeEditor(initialValue: previous?.value));
      if (!mounted || generation != _generation || value == null) return;
      final confirmed = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
        title: const Text('会社の適用条件を保存'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          _scopeDetails(value), const SizedBox(height: 12),
          const Text('会社の保険者・都道府県・事業区分を確認して保存してください。既存料率は変更されません。登録済み確認値は会社条件が変わると再確認が必要になります。'),
        ]),
        actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('キャンセル')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('確認して保存'))],
      )) ?? false;
      if (!mounted || generation != _generation || !confirmed) return;
      await _repository.saveScope(companyId: widget.companyId, expectedVersion: previous?.version ?? 0, value: value);
      if (!mounted || generation != _generation) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('会社の適用条件を保存しました')));
      await _load();
    } catch (_) {
      if (mounted && generation == _generation) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('会社条件の保存結果を確認できません。再読み込みしてください。')));
      }
    } finally {
      if (mounted && generation == _generation) setState(() => _busy = false);
    }
  }

  Widget _scopeCard() {
    final scope = _data!.companyScope;
    return Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(
      crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [Expanded(child: Text('会社の適用条件', style: Theme.of(context).textTheme.titleMedium)),
          if (_canEdit) TextButton(onPressed: _busy ? null : _editScope, child: const Text('会社の適用条件を編集'))]),
        if (scope == null) const Text('会社条件は未登録です') else ...[
          Text('${payrollScopeInsurers[scope.value['insurer']] ?? '未設定'} · ${scope.value['prefecture'] ?? '都道府県未設定'} · ${payrollScopeBusinesses[scope.value['employment_business']] ?? '事業区分未設定'}'),
          ExpansionTile(title: const Text('条件の詳細'), tilePadding: EdgeInsets.zero,
            children: [Align(alignment: Alignment.centerLeft, child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
                _scopeDetails(scope.value), if (scope.updatedBy != null) Text('変更者 ${scope.updatedBy}'), Text('変更日時 ${scope.updatedAt}'),
              ]))]),
        ],
      ],
    )));
  }

  static String _newCustomId() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 15) | 64;
    bytes[8] = (bytes[8] & 63) | 128;
    final hex = bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  static Widget _valueDetails(Map<String, dynamic> value) {
    final source = payrollRateObject(value['source']);
    final applicability = source['applicability'];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      Text(value['label'] as String),
      Text('全体 ${formatPayrollRatePercent(value['total'] as int)}%'),
      Text('従業員負担 ${formatPayrollRatePercent(value['employee'] as int)}%'),
      Text('会社負担 ${formatPayrollRatePercent(value['employer'] as int)}%'),
      Text('保険適用年月 ${_month(value['insurance_month'])}'),
      Text('給与対象年月 ${_month(value['payroll_month'])}'),
      Text('支払年月 ${_month(value['payment_month'])}'),
      Text('情報元 ${source['publisher'] ?? '未記載'}'),
      SelectableText('${source['url'] ?? '未記載'}',
        key: PageStorageKey('payroll-rate-source-url-${source['url']}')),
      _PayrollRateSourceLink(url: source['url']?.toString() ?? ''),
      if (applicability is Map) for (final entry in applicability.entries)
        Text(_applicabilityText(entry.key.toString(), entry.value)),
    ]);
  }

  static String _applicabilityText(String key, dynamic value) {
    const labels = {'prefecture': '都道府県', 'insurer': '保険者', 'employment_business': '事業区分',
      'business_category': '事業区分', 'company_scope_version': '会社条件の版',
      'admin_confirmed_conditions': '適用条件の確認'};
    final display = key == 'insurer' ? payrollScopeInsurers[value] ?? value :
      key == 'employment_business' ? payrollScopeBusinesses[value] ?? value : value;
    return '${labels[key] ?? key}: $display';
  }

  static String _month(dynamic value) => value is String && value.length >= 7 ? value.substring(0, 7) : '未確認';

  Widget _valueSummary(Map<String, dynamic> value, String detailsId) {
    final source = payrollRateObject(value['source']);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('全体 ${formatPayrollRatePercent(value['total'] as int)}%',
        style: Theme.of(context).textTheme.titleMedium),
      Text('従業員負担 ${formatPayrollRatePercent(value['employee'] as int)}%'),
      Text('会社負担 ${formatPayrollRatePercent(value['employer'] as int)}%'),
      const SizedBox(height: 4),
      Text('適用 ${_month(value['insurance_month'])}'),
      Text('情報元 ${source['publisher']}'),
      ExpansionTile(key: PageStorageKey('rate-details-$detailsId'), title: const Text('適用月・資料の詳細'),
        tilePadding: EdgeInsets.zero,
        children: [Align(alignment: Alignment.centerLeft, child: _valueDetails(value))]),
    ]);
  }

  bool _changed(Map<String, dynamic>? current, Map<String, dynamic> candidate) {
    if (current == null) return true;
    return ['total', 'employee', 'employer', 'insurance_month', 'payroll_month', 'payment_month'].any((key) => current[key] != candidate[key]) ||
      !_sameValue(current['source'], candidate['source']);
  }

  bool _sameValue(dynamic left, dynamic right) {
    if (left is Map && right is Map) {
      return left.length == right.length && left.keys.every((key) => right.containsKey(key) && _sameValue(left[key], right[key]));
    }
    if (left is List && right is List) {
      if (left.length != right.length) return false;
      for (var index = 0; index < left.length; index++) {
        if (!_sameValue(left[index], right[index])) return false;
      }
      return true;
    }
    return left == right;
  }

  Widget _itemCard(String kind, String label, CompanyPayrollRateItem? item, String itemId) {
    final candidates = _data!.candidates.where((candidate) => candidate.itemId == itemId).toList();
    return Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(
      crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [Expanded(child: Text(label, style: Theme.of(context).textTheme.titleMedium)),
          if (_canEdit) TextButton(onPressed: _busy ? null : () => _edit(kind, item), child: const Text('編集'))]),
        const SizedBox(height: 8),
        LayoutBuilder(builder: (context, constraints) {
          final current = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('現在設定値', style: TextStyle(fontWeight: FontWeight.bold)),
            if (item == null) const Text('未設定') else ...[
              _valueSummary(item.value, '$itemId-current'),
              Text(item.origin == 'manual' ? '利用者による手動設定' : '確認値を利用者が適用した設定'),
            ],
          ]);
          final checked = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('登録済みの確認値', style: TextStyle(fontWeight: FontWeight.bold)),
            if (candidates.isEmpty) const Text('確認値はまだ登録されていません'),
            for (final candidate in candidates) ...[
              _valueSummary(candidate.value, candidate.id), Text('確認日時 ${candidate.checkedAt}'),
              if (_changed(item?.value, candidate.value)) const Text('変更あり', style: TextStyle(fontWeight: FontWeight.bold)),
              if (!_scopeMatches(candidate)) const Text('会社条件が変更されています。再確認が必要'),
              if (_canEdit) FilledButton(key: ValueKey('apply-${candidate.id}'), onPressed: _busy || !_scopeMatches(candidate) ? null : () => _apply(candidate, item), child: const Text('適用')),
              const SizedBox(height: 12),
            ],
          ]);
          if (constraints.maxWidth < 340) {
            return Column(crossAxisAlignment: CrossAxisAlignment.start,
              children: [current, const Divider(), checked]);
          }
          return Row(crossAxisAlignment: CrossAxisAlignment.start,
            children: [Expanded(child: current), const SizedBox(width: 24), Expanded(child: checked)]);
        }),
      ],
    )));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(appBar: AppBar(title: const Text('会社共通の税率・保険料率'), actions: [
      IconButton(tooltip: '税率設定の使い方', icon: const Icon(Icons.help_outline), onPressed: () => showDialog<void>(
        context: context, builder: (context) => AlertDialog(title: const Text('税率設定の使い方'),
          content: _canEdit ? const Text('会社の適用条件と資料を確認して料率を設定します。未設定項目の編集には利用者指定の初期入力値を表示します。既存値は保持し、適用月・情報元の入力と確認後に保存します。支援金の負担内訳は資料確認が必要です。新規編集では被用者保険の標準折半値を選んで入力できます。確認値は登録済み資料の値で、公式サイトの自動取得は準備中です。\n\n適用月・資料の詳細から情報元と給与対象月・支払月を確認できます。変更履歴は画面下で開けます。\n\n給与連携と介護保険の生年月日判定は準備中です。') : const Text('会社の料率・適用月・情報元と年度PDF資料を確認できます。設定の変更・適用は管理者が行います。確認値は登録済み資料の値です。公式資料の自動取得と給与連携は準備中です。'),
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('閉じる'))],
        ),
      )),
    ]),
      body: SafeArea(child: ListView(padding: const EdgeInsets.all(16), children: [
        const Text('会社共通の料率を管理します。給与連携は準備中です。'),
        const SizedBox(height: 12),
        OutlinedButton.icon(onPressed: _busy ? null : _load, icon: const Icon(Icons.refresh),
          label: const Text('確認値を再読み込み')),
        const Text('登録済みの確認値を表示します。公式資料の自動取得は準備中です。'),
        if (_loading) const LinearProgressIndicator(),
        if (_error != null) ...[Text(_error!), TextButton(onPressed: _busy ? null : _load, child: const Text('再試行'))],
        if (_data != null) ...[
          if (!_canEdit) const Text('閲覧のみ：料率・適用月・情報元を確認できます。'),
          _scopeCard(),
          for (final entry in payrollRateKinds.entries)
            _itemCard(entry.key, entry.value, _findKind(entry.key), _findKind(entry.key)?.id ?? entry.key),
          for (final item in _data!.items.where((item) => item.value['kind'] == 'custom'))
            _itemCard('custom', item.value['label'] as String, item, item.id),
          if (_canEdit) OutlinedButton.icon(onPressed: _busy ? null : () => _edit('custom', null),
            icon: const Icon(Icons.add), label: const Text('料率項目を追加')),
          Card(child: ExpansionTile(title: const Text('所得税'), subtitle: const Text('年度・PDF資料管理'),
            children: [Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('源泉徴収税額表の資料を登録します。税額計算・公式資料検証は準備中です。'),
              OutlinedButton.icon(
                onPressed: _busy ? null : () => Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => CompanyIncomeTaxPage(companyId: widget.companyId))),
                icon: const Icon(Icons.picture_as_pdf_outlined), label: Text(_canEdit ? '年度・PDF資料を管理' : '年度・PDF資料を閲覧')),
            ]))])),
          if (_canEdit) Card(child: ExpansionTile(key: const PageStorageKey('payroll-rate-history'), title: const Text('変更履歴'),
            subtitle: Text('料率 ${_data!.history.length}件・会社条件 ${_data!.scopeHistory.length}件'),
            children: [
              for (final history in _data!.scopeHistory) Padding(
                padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('会社条件の変更履歴'),
                  const Text('変更前'), _scopeDetails(history['before_value'] == null ? null : payrollRateObject(history['before_value'])),
                  const Text('変更後'), _scopeDetails(payrollRateObject(history['after_value'])),
                  Text('変更者 ${history['actor_id']}'), Text('変更日時 ${history['changed_at']}'),
                ])),
              if (_data!.history.isEmpty && _data!.scopeHistory.isEmpty) const Padding(
                padding: EdgeInsets.all(12), child: Text('変更履歴はありません')),
              for (final history in _data!.history) _historyCard(history),
            ])),
        ],
      ])),
    );
  }

  CompanyPayrollRateItem? _findKind(String kind) {
    for (final item in _data!.items) { if (item.value['kind'] == kind) return item; }
    return null;
  }

  Widget _historyCard(Map<String, dynamic> history) {
    final before = history['before_value'];
    final after = history['after_value'];
    String rates(dynamic value) {
      if (value == null) return '未設定';
      try {
        final parsed = validatePayrollRateValue(value);
        return '全体${formatPayrollRatePercent(parsed['total'] as int)}% / 従業員${formatPayrollRatePercent(parsed['employee'] as int)}% / 会社${formatPayrollRatePercent(parsed['employer'] as int)}%';
      } catch (_) { return '履歴の数値を確認できません'; }
    }
    return Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(
      crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('項目 ${history['item_id']}'), Text('${rates(before)} → ${rates(after)}'),
        Text('変更者 ${history['actor_id']}'), Text('変更日時 ${history['changed_at']}'),
      ],
    )));
  }
}

class _PayrollRateEditor extends StatefulWidget {
  const _PayrollRateEditor({required this.kind, this.initialValue, this.companyScope});
  final String kind;
  final Map<String, dynamic>? initialValue;
  final CompanyPayrollRateScope? companyScope;
  @override
  State<_PayrollRateEditor> createState() => _PayrollRateEditorState();
}

class _PayrollRateEditorState extends State<_PayrollRateEditor> {
  final _form = GlobalKey<FormState>();
  bool _conditionsConfirmed = false;
  late final Map<String, dynamic> _initialApplicability;
  late final Map<String, TextEditingController> _fields;
  @override
  void initState() {
    super.initState();
    final value = widget.initialValue;
    final source = value == null ? <String, dynamic>{} : payrollRateObject(value['source']);
    final applicability = source['applicability'] is Map ? payrollRateObject(source['applicability']) : <String, dynamic>{};
    _initialApplicability = Map<String, dynamic>.from(applicability);
    _fields = {
      'label': TextEditingController(text: value?['label'] as String? ?? payrollRateKinds[widget.kind] ?? ''),
      for (final key in ['total', 'employee', 'employer'])
        key: TextEditingController(text: value == null ? payrollManualStartingRates[widget.kind]?[key] ?? '' : formatPayrollRatePercent(value[key] as int)),
      for (final key in ['insurance_month', 'payroll_month', 'payment_month'])
        key: TextEditingController(text: value == null ? '' : (value[key] as String).substring(0, 7)),
      'publisher': TextEditingController(text: source['publisher'] as String? ?? ''),
      'url': TextEditingController(text: source['url'] as String? ?? ''),

    };
  }
  @override
  void dispose() { for (final controller in _fields.values) { controller.dispose(); } super.dispose(); }

  Widget _field(String key, String label, {bool rate = false, bool month = false, bool optional = false}) =>
    Padding(padding: const EdgeInsets.only(bottom: 12), child: TextFormField(
      key: ValueKey('rate-field-$key'), controller: _fields[key], decoration: InputDecoration(labelText: label),
      keyboardType: rate ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text,
      validator: (text) {
        final input = text?.trim() ?? '';
        if (optional && input.isEmpty) return null;
        if (input.isEmpty) return '入力してください';
        if (rate) { try { parsePayrollRatePercent(input); } on FormatException catch (error) { return error.message; } }
        if (month && (!RegExp(r'^\d{4}-(0[1-9]|1[0-2])$').hasMatch(input) || input.startsWith('0000-'))) return 'YYYY-MMで入力してください';
        if (key == 'url') {
          final uri = Uri.tryParse(input);
          if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) return 'httpsの情報元URLを入力してください';
        }
        return null;
      },
    ));

  void _submit() {
    if (!_form.currentState!.validate()) return;
    if (!_conditionsConfirmed) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('適用条件の確認にチェックしてください')));
      return;
    }
    final total = parsePayrollRatePercent(_fields['total']!.text);
    final employee = parsePayrollRatePercent(_fields['employee']!.text);
    final employer = parsePayrollRatePercent(_fields['employer']!.text);
    if (total != employee + employer) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('全体料率は従業員負担率＋会社負担率と一致させてください')));
      return;
    }
    final applicability = Map<String, dynamic>.from(_initialApplicability);
    final scope = widget.companyScope;
    if (scope != null) {
      for (final key in ['insurer', 'prefecture', 'employment_business']) {
        if (scope.value[key] == null) { applicability.remove(key); } else { applicability[key] = scope.value[key]; }
      }
      applicability['company_scope_version'] = scope.version.toString();
    }
    applicability['admin_confirmed_conditions'] = '本人確認済み';
    Navigator.pop(context, <String, dynamic>{
      'kind': widget.kind, 'label': _fields['label']!.text.trim(),
      'total': total, 'employee': employee, 'employer': employer,
      for (final key in ['insurance_month', 'payroll_month', 'payment_month']) key: '${_fields[key]!.text.trim()}-01',
      'source': {
        'publisher': _fields['publisher']!.text.trim(), 'url': _fields['url']!.text.trim(),
        'document_hash': 'admin-manual-entry',
        'applicability': applicability,
      },
    });
  }

  @override
  Widget build(BuildContext context) => AlertDialog(title: const Text('料率の手動設定'),
    content: SizedBox(width: 520, child: SingleChildScrollView(child: Form(key: _form,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Text('数値は公式資料と照合して入力してください。手動設定は正式資料の検証済みデータとして扱いません。'),
        if (widget.initialValue == null && payrollManualStartingRates.containsKey(widget.kind))
          const Text('初期入力値は利用者指定です。適用月と情報元を確認して保存してください。保存するまで現在設定値は変わりません。'),
        if (widget.kind == 'child_support' && widget.initialValue == null)
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('被用者保険の2026年度は全体0.23%、基本は労使折半です。加入条件を確認してから入力してください。'),
            const _PayrollRateSourceLink(url: 'https://www.cfa.go.jp/policies/kodomokosodateshienkinseido'),
            TextButton(
              key: const ValueKey('child-support-standard-shares'),
              onPressed: () {
                _fields['total']!.text = '0.23';
                _fields['employee']!.text = '0.115';
                _fields['employer']!.text = '0.115';
              },
              child: const Text('標準の折半値を入力'),
            ),
          ]),
        _field('label', '項目名'), _field('total', '全体料率（%）', rate: true),
        _field('employee', '従業員負担率（%）', rate: true), _field('employer', '会社負担率（%）', rate: true),
        _field('insurance_month', '保険適用年月（YYYY-MM）', month: true),
        _field('payroll_month', '給与対象年月（YYYY-MM）', month: true),
        _field('payment_month', '支払年月（YYYY-MM）', month: true),
        _field('publisher', '情報元の名称'), _field('url', '情報元URL'),
        const Text('保存時の会社条件を資料の適用条件の記録へ反映します'),
        _CompanyPayrollRatesPageState._scopeDetails(widget.companyScope?.value),
        CheckboxListTile(value: _conditionsConfirmed,
          onChanged: (value) => setState(() => _conditionsConfirmed = value ?? false),
          title: const Text('会社の保険者・都道府県・事業区分などの適用条件を確認しました')), 
      ])))),
    actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('キャンセル')),
      FilledButton(onPressed: _submit, child: const Text('入力内容を確認'))],
  );
}

class _PayrollRateSourceLink extends StatelessWidget {
  const _PayrollRateSourceLink({required this.url});
  final String url;
  @override
  Widget build(BuildContext context) {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) return const SizedBox.shrink();
    return TextButton.icon(icon: const Icon(Icons.open_in_new), label: const Text('情報元を開く'),
      onPressed: () async {
        try {
          final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
          if (!opened && context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('情報元を開けませんでした')));
          }
        } catch (_) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('情報元を開けませんでした')));
          }
        }
      });
  }
}

class _PayrollScopeEditor extends StatefulWidget {
  const _PayrollScopeEditor({this.initialValue});
  final Map<String, dynamic>? initialValue;
  @override
  State<_PayrollScopeEditor> createState() => _PayrollScopeEditorState();
}

class _PayrollScopeEditorState extends State<_PayrollScopeEditor> {
  late String _insurer;
  late String _prefecture;
  late String _business;
  @override
  void initState() {
    super.initState();
    _insurer = widget.initialValue?['insurer'] as String? ?? 'unconfigured';
    _prefecture = widget.initialValue?['prefecture'] as String? ?? '';
    _business = widget.initialValue?['employment_business'] as String? ?? '';
  }
  @override
  Widget build(BuildContext context) => AlertDialog(title: const Text('会社の適用条件'),
    content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
      const Text('正式資料と会社の加入先・事業内容を確認してください。未設定は空欄のまま保存できます。'),
      DropdownButtonFormField<String>(key: const ValueKey('scope-insurer'), initialValue: _insurer,
        decoration: const InputDecoration(labelText: '保険者'), isExpanded: true,
        items: [for (final entry in payrollScopeInsurers.entries) DropdownMenuItem(value: entry.key, child: Text(entry.value))],
        onChanged: (value) => setState(() => _insurer = value ?? 'unconfigured')),
      DropdownButtonFormField<String>(key: const ValueKey('scope-prefecture'), initialValue: _prefecture,
        decoration: const InputDecoration(labelText: '都道府県'), isExpanded: true,
        items: [const DropdownMenuItem(value: '', child: Text('未設定')),
          for (final prefecture in companyPayrollScopePrefectures) DropdownMenuItem(value: prefecture, child: Text(prefecture))],
        onChanged: (value) => setState(() => _prefecture = value ?? '')),
      DropdownButtonFormField<String>(key: const ValueKey('scope-business'), initialValue: _business,
        decoration: const InputDecoration(labelText: '雇用保険の事業区分'), isExpanded: true,
        items: [const DropdownMenuItem(value: '', child: Text('未設定')),
          for (final entry in payrollScopeBusinesses.entries) DropdownMenuItem(value: entry.key, child: Text(entry.value))],
        onChanged: (value) => setState(() => _business = value ?? '')),
    ])),
    actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('キャンセル')),
      FilledButton(onPressed: () => Navigator.pop(context, <String, dynamic>{'insurer': _insurer,
        'prefecture': _prefecture.isEmpty ? null : _prefecture,
        'employment_business': _business.isEmpty ? null : _business}), child: const Text('会社条件を確認'))],
  );
}
