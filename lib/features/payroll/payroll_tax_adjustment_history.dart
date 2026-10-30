import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/supabase_backend.dart';
import '../shared/trade_document_form_session.dart';

const _amountNames = <String, String>{
  'income_tax': '所得税', 'employment_insurance': '雇用保険料',
  'health_insurance': '健康保険料', 'pension_insurance': '厚生年金保険',
  'nursing_insurance': '介護保険料', 'child_support': '子ども・子育て支援金',
};
const _conditionNames = <String, String>{
  'insurance_mode': '保険料の計算方法', 'income_mode': '所得税の計算方法',
  'health': '健康保険の加入', 'pension': '厚生年金の加入',
  'employment': '雇用保険の加入', 'nursing': '介護保険の対象',
  'child_support': '子ども・子育て支援金の対象', 'birth_date': '生年月日',
  'health_base_yen': '健康保険の標準報酬月額',
  'pension_base_yen': '厚生年金の標準報酬月額', 'dependents': '扶養人数',
  'non_taxable_yen': '非課税額', 'employment_excluded_yen': '雇用保険対象外額',
  'additional_social_deduction_yen': 'その他の社会保険料控除',
};

bool _same(Object? a, Object? b) {
  if (a is Map && b is Map) {
    return a.length == b.length && a.keys.every((key) => b.containsKey(key) && _same(a[key], b[key]));
  }
  if (a is List && b is List) {
    return a.length == b.length && List.generate(a.length, (i) => i).every((i) => _same(a[i], b[i]));
  }
  return a == b;
}

Object? _freeze(Object? raw) {
  if (raw is Map) {
    if (raw.keys.any((key) => key is! String)) throw const FormatException('Invalid history value');
    return Map<String, Object?>.unmodifiable(raw.map((key, value) => MapEntry(key as String, _freeze(value))));
  }
  if (raw is List) return List<Object?>.unmodifiable(raw.map(_freeze));
  if (raw == null || raw is String || raw is bool || raw is num) return raw;
  throw const FormatException('Invalid history value');
}

String _amount(Object? value, {String missing = '修正なし'}) => value == null ? missing
    : value is int && value >= 0 ? '$value円' : '記録値を確認してください';

class PayrollTaxHistoryChange {
  const PayrollTaxHistoryChange(this.label, this.before, this.after);
  final String label, before, after;
}

class PayrollTaxHistoryItem {
  const PayrollTaxHistoryItem({required this.startsOn, required this.version,
    required this.reason, required this.actorId, required this.changedAt,
    required this.beforeValue, required this.afterValue});
  final String startsOn, reason, actorId;
  final int version;
  final DateTime changedAt;
  final Map<String, Object?>? beforeValue;
  final Map<String, Object?> afterValue;

  List<PayrollTaxHistoryChange> get changes {
    final before = beforeValue ?? const <String, Object?>{};
    final result = <PayrollTaxHistoryChange>[];
    for (final namespace in ['deduction_overrides', 'manual_insurance_premiums']) {
      final a = before[namespace] is Map ? before[namespace] as Map : const {};
      final b = afterValue[namespace] is Map ? afterValue[namespace] as Map : const {};
      for (final entry in _amountNames.entries) {
        if (!_same(a[entry.key], b[entry.key])) {
          result.add(PayrollTaxHistoryChange('${entry.value}${namespace == 'deduction_overrides' ? 'の修正額' : 'の個別月額'}',
            _amount(a[entry.key], missing: namespace == 'deduction_overrides' ? '修正なし' : '未設定'),
            _amount(b[entry.key], missing: namespace == 'deduction_overrides' ? '修正なし' : '未設定')));
        }
      }
    }
    String display(String key, Object? value) {
      if (value == null) return '未設定';
      if (value is bool) return value ? '対象' : '対象外';
      if (key.endsWith('_yen')) return _amount(value, missing: '未設定');
      if (key == 'dependents' && value is int) return '$value人';
      if (key == 'insurance_mode') return const {'fixed': '固定額', 'rates': '自動計算', 'manual': '個別月額'}[value] ?? '記録値を確認してください';
      if (key == 'income_mode') return const {'fixed': '固定額', 'koh': '甲欄', 'otsu': '乙欄'}[value] ?? '記録値を確認してください';
      return value is String ? value : '記録値を確認してください';
    }
    for (final entry in _conditionNames.entries) {
      if (!_same(before[entry.key], afterValue[entry.key])) {
        result.add(PayrollTaxHistoryChange(entry.value,
          display(entry.key, before[entry.key]), display(entry.key, afterValue[entry.key])));
      }
    }
    if (!_same(before['insurance_basis_reference'], afterValue['insurance_basis_reference'])) {
      result.add(PayrollTaxHistoryChange('算定根拠資料',
        before['insurance_basis_reference'] == null ? '未登録' : '変更前の資料',
        afterValue['insurance_basis_reference'] == null ? '未登録' : '変更後の資料'));
    }
    return List.unmodifiable(result);
  }
}

class PayrollTaxHistorySnapshot {
  const PayrollTaxHistorySnapshot({required this.items, required this.truncated});
  final List<PayrollTaxHistoryItem> items;
  final bool truncated;
  static final _uuid = RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$');

  factory PayrollTaxHistorySnapshot.fromJson(Object? raw, {required String companyId, required String workerId}) {
    const envelope = {'contract_version', 'company_id', 'worker_id', 'items', 'truncated'};
    if (raw is! Map || raw.length != envelope.length || raw.keys.any((key) => !envelope.contains(key)) ||
        raw['contract_version'] is! int || raw['contract_version'] != 1 ||
        raw['company_id'] != companyId || raw['worker_id'] != workerId ||
        raw['items'] is! List || (raw['items'] as List).length > 100 || raw['truncated'] is! bool) {
      throw const FormatException('Invalid history envelope');
    }
    final items = <PayrollTaxHistoryItem>[], versions = <String>{};
    for (final value in raw['items'] as List) {
      const keys = {'starts_on', 'version', 'reason', 'actor_id', 'changed_at', 'before_value', 'after_value'};
      if (value is! Map || value.length != keys.length || value.keys.any((key) => !keys.contains(key)) ||
          value['starts_on'] is! String || !RegExp(r'^\d{4}-\d{2}-01$').hasMatch(value['starts_on'] as String) ||
          value['version'] is! int || (value['version'] as int) < 1 ||
          value['reason'] is! String || (value['reason'] as String).trim().isEmpty ||
          (value['reason'] as String).runes.length > 1000 || utf8.encode(value['reason'] as String).length > 4000 ||
          value['actor_id'] is! String || !_uuid.hasMatch(value['actor_id'] as String) ||
          value['changed_at'] is! String || value['after_value'] is! Map ||
          (value['before_value'] != null && value['before_value'] is! Map)) {
        throw const FormatException('Invalid history item');
      }
      final month = value['starts_on'] as String;
      final parsedMonth = DateTime.tryParse('${month}T00:00:00Z');
      final time = value['changed_at'] as String;
      final changed = DateTime.tryParse(time);
      if (parsedMonth == null || parsedMonth.toIso8601String().substring(0, 10) != month ||
          changed == null || !RegExp(r'(Z|[+-]\d{2}:\d{2})$').hasMatch(time) ||
          !versions.add('$month/${value['version']}')) {
        throw const FormatException('Invalid history identity');
      }
      items.add(PayrollTaxHistoryItem(startsOn: month, version: value['version'] as int,
        reason: value['reason'] as String, actorId: value['actor_id'] as String, changedAt: changed,
        beforeValue: value['before_value'] == null ? null : _freeze(value['before_value']) as Map<String, Object?>,
        afterValue: _freeze(value['after_value']) as Map<String, Object?>));
    }
    return PayrollTaxHistorySnapshot(items: List.unmodifiable(items), truncated: raw['truncated'] as bool);
  }
}

class PayrollTaxHistoryUnavailable implements Exception {}

abstract class PayrollTaxHistorySource extends ChangeNotifier {
  String get companyId;
  String get workerId;
  bool get isCurrent;
  Future<PayrollTaxHistorySnapshot> load();
  void retire();
  Future<void> refreshAccess() async {
    if (!isCurrent) throw StateError('History scope retired');
  }
}

/// Read-only. Reuses the captured-token/gateway/lifecycle boundary and the
/// canonical payroll workspace; no condition, payroll or reason writer exists.
class PayrollTaxHistoryRepository extends PayrollTaxHistorySource {
  PayrollTaxHistoryRepository(SupabaseClient client, {required this.companyId,
    required this.workerId, bool Function()? scopeIsCurrent})
    : _session = TradeDocumentFormSession(client, target: (companyId, workerId),
        currentTarget: () => scopeIsCurrent?.call() == false ? null : (companyId, workerId)) {
    _session.addListener(_changed);
  }
  @override final String companyId, workerId;
  final TradeDocumentFormSession _session;
  bool _retired = false, _closed = false;
  @override bool get isCurrent => !_retired && !_closed && _session.isCurrent;
  void _changed() { if (!_closed) notifyListeners(); }
  @override void retire() {
    if (_closed || _retired) return;
    _retired = true; notifyListeners();
  }
  void _check() {
    if (_retired || _closed) throw StateError('History scope retired');
    _session.requireScope();
  }
  Future<void> _workspace() async {
    final raw = await _session.rpc('payroll_workspace', {}); _check();
    if (raw is! Map || raw['permissions'] is! Map ||
        (raw['permissions'] as Map)['view'] != true || raw['workers'] is! List ||
        (raw['workers'] as List).where((row) => row is Map && row['id'] == workerId).length != 1) {
      retire(); throw StateError('History workspace changed');
    }
    if (raw.containsKey('company_id')) {
      if (raw['company_id'] != companyId) {
        retire(); throw StateError('History workspace changed');
      }
    } else {
      // The deployed older workspace omits company_id. Resolve only this
      // selected worker through the existing RLS path, with the same captured
      // bearer and cancellation boundary as every other history read.
      final rows = await _session.readWorkerCompany(workerId); _check();
      if (rows is! List || rows.length != 1 || rows.single is! Map ||
          (rows.single as Map)['id'] != workerId ||
          (rows.single as Map)['company_id'] != companyId) {
        retire(); throw StateError('History worker company changed');
      }
    }
  }
  @override Future<void> refreshAccess() async {
    try { await _session.ready(); _check(); await _workspace(); _check(); }
    catch (_) { retire(); rethrow; }
  }
  @override Future<PayrollTaxHistorySnapshot> load() async {
    try {
      await _session.ready(); _check();
      await _workspace();
      final raw = await _session.rpc('read_worker_payroll_tax_adjustment_history', {
        'p_company_id': companyId, 'p_worker_id': workerId,
      }); _check();
      final result = PayrollTaxHistorySnapshot.fromJson(raw, companyId: companyId, workerId: workerId);
      await _workspace(); _check();
      return result;
    } on PostgrestException catch (error) {
      if (error.code == '42501') retire();
      if (error.code == 'PGRST202' || error.code == '42883') throw PayrollTaxHistoryUnavailable();
      rethrow;
    } on FormatException { retire(); rethrow; }
  }
  @override void dispose() {
    if (_closed) return;
    _closed = true; _retired = true;
    _session.removeListener(_changed); _session.dispose(); super.dispose();
  }
}

class PayrollTaxAdjustmentHistoryPage extends StatefulWidget {
  const PayrollTaxAdjustmentHistoryPage({super.key, required this.companyId,
    required this.workerId, required this.workerName, this.scopeIsCurrent, this.sourceOverride});
  final String companyId, workerId, workerName;
  final bool Function()? scopeIsCurrent;
  @visibleForTesting final PayrollTaxHistorySource? sourceOverride;
  @override State<PayrollTaxAdjustmentHistoryPage> createState() => _PayrollTaxAdjustmentHistoryPageState();
}

class _PayrollTaxAdjustmentHistoryPageState extends State<PayrollTaxAdjustmentHistoryPage>
    with WidgetsBindingObserver {
  PayrollTaxHistorySource? _source;
  PayrollTaxHistorySnapshot? _snapshot;
  Timer? _timer;
  bool _loading = true, _retired = false, _unavailable = false, _checkingAccess = false;
  String? _error;
  int _generation = 0;
  @override void initState() {
    super.initState(); WidgetsBinding.instance.addObserver(this); _attach();
  }
  void _attach() {
    try {
      _source = widget.sourceOverride ?? (SupabaseBackend.isInitialized
          ? PayrollTaxHistoryRepository(SupabaseBackend.client, companyId: widget.companyId,
              workerId: widget.workerId, scopeIsCurrent: widget.scopeIsCurrent) : null);
      if (_source?.companyId != widget.companyId || _source?.workerId != widget.workerId) {
        _source?.retire(); _retired = true; _loading = false; return;
      }
      _source?.addListener(_changed);
      final lifecycle = WidgetsBinding.instance.lifecycleState;
      if (lifecycle != null && lifecycle != AppLifecycleState.resumed) {
        _source?.retire(); _retired = true; _loading = false; return;
      }
      _load();
      _timer = Timer.periodic(const Duration(seconds: 15), (_) => _verifyAccess());
    } catch (_) { _retired = true; _loading = false; }
  }
  Future<void> _verifyAccess() async {
    if (_loading || _retired || _checkingAccess || !mounted) return;
    _checkingAccess = true;
    final source = _source;
    try { await source?.refreshAccess(); }
    catch (_) { if (mounted && identical(source, _source)) source?.retire(); }
    finally { _checkingAccess = false; }
  }
  void _changed() {
    if (mounted && _source?.isCurrent != true) {
      _generation++;
      setState(() { _snapshot = null; _loading = false; _retired = true; _error = null; });
    }
  }
  Future<void> _load() async {
    final source = _source;
    if (source == null || _retired) { if (mounted) setState(() { _loading = false; _retired = true; }); return; }
    final generation = ++_generation;
    setState(() { _loading = true; _snapshot = null; _error = null; _unavailable = false; });
    try {
      final value = await source.load();
      if (!mounted || generation != _generation) return;
      if (!source.isCurrent || widget.scopeIsCurrent?.call() == false) { source.retire(); return; }
      setState(() { _snapshot = value; _loading = false; });
    } catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _snapshot = null; _loading = false; _retired = !source.isCurrent;
        _unavailable = error is PayrollTaxHistoryUnavailable;
        _error = '変更履歴を読み込めませんでした。再読み込みしてください。';
      });
    }
  }
  @override void didUpdateWidget(covariant PayrollTaxAdjustmentHistoryPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.companyId != widget.companyId || oldWidget.workerId != widget.workerId ||
        oldWidget.sourceOverride != widget.sourceOverride) {
      _generation++; _timer?.cancel(); _source?.removeListener(_changed); _source?.dispose();
      _source = null; _snapshot = null; _retired = false; _loading = true; _attach();
    }
  }
  @override void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _source?.retire();
  }
  @override void dispose() {
    _generation++; _timer?.cancel(); WidgetsBinding.instance.removeObserver(this);
    _source?.removeListener(_changed); _source?.dispose(); super.dispose();
  }
  String _date(DateTime value) {
    final date = value.toLocal();
    return '${date.year}/${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')} '
        '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }
  @override Widget build(BuildContext context) {
    final retired = _retired || widget.scopeIsCurrent?.call() == false ||
        (!_loading && _source?.isCurrent != true);
    final value = retired ? null : _snapshot;
    return Scaffold(appBar: AppBar(title: const Text('変更履歴'), actions: [
      TextButton(onPressed: () => Navigator.of(context).maybePop(), child: const Text('閉じる')),
    ]), body: SafeArea(child: _loading && !retired ? const Center(child: CircularProgressIndicator())
      : ListView(padding: const EdgeInsets.all(16), children: [
        if (retired) const Text('状態が変わりました。閉じて開き直してください。')
        else if (_unavailable) const Text('変更履歴はまだ利用できません。接続設定を確認してください。')
        else if (_error != null) Text(_error!)
        else if (value != null) ...[
          Text(widget.workerName, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          const Text('保険料・税の手動調整を確認できます。'),
          if (value.items.isEmpty) const Padding(padding: EdgeInsets.symmetric(vertical: 24),
            child: Text('このメンバーの変更履歴はまだありません。')),
          for (final item in value.items) Card(child: Padding(padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('適用月 ${item.startsOn.substring(0, 7)}', style: Theme.of(context).textTheme.titleSmall),
              Text(_date(item.changedAt), style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 8), Text(item.reason),
              ExpansionTile(tilePadding: EdgeInsets.zero, title: const Text('変更内容'), children: [
                if (item.changes.isEmpty) const Text('計算条件の変更を記録しています。'),
                for (final change in item.changes) Padding(padding: const EdgeInsets.only(bottom: 8),
                  child: Align(alignment: Alignment.centerLeft,
                    child: Text('${change.label}：${change.before} → ${change.after}'))),
                Align(alignment: Alignment.centerLeft, child: SelectableText('記録者ID：${item.actorId}\n保存版：${item.version}',
                  style: Theme.of(context).textTheme.bodySmall)),
              ]),
            ]))),
          if (value.truncated) const Text('このほかにも過去の履歴があります（表示は最新100件まで）。'),
        ],
        if (!retired) TextButton.icon(onPressed: _loading ? null : _load,
          icon: const Icon(Icons.refresh), label: const Text('再読み込み')),
      ])));
  }
}
