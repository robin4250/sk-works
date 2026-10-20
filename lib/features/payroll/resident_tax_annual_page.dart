import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../data/supabase_backend.dart';
import 'resident_tax_annual_repository.dart';

class ResidentTaxAnnualUpdatePage extends StatefulWidget {
  const ResidentTaxAnnualUpdatePage({super.key, required this.companyId,
    required this.fiscalYear, this.repository, this.reminderPanel, this.authClient});
  final String companyId;
  final int fiscalYear;
  final ResidentTaxAnnualRepository? repository;
  final Widget? reminderPanel;
  final SupabaseClient? authClient;
  @override
  State<ResidentTaxAnnualUpdatePage> createState() => _ResidentTaxAnnualUpdatePageState();
}

String residentTaxAnnualDisplay(List<int?> amounts) {
  if (amounts.every((v) => v == null)) return '未確認';
  if (amounts.any((v) => v == null)) return '一部未確認';
  if (amounts.toSet().length != 1) return '月別';
  return '${amounts.first}円';
}

class _AnnualDraft {
  _AnnualDraft(this.worker);
  final ResidentTaxAnnualWorker worker;
  final input = TextEditingController();
  bool dirty = false;
  void dispose() => input.dispose();
}

class _ResidentTaxAnnualUpdatePageState extends State<ResidentTaxAnnualUpdatePage> with WidgetsBindingObserver {
  late ResidentTaxAnnualRepository _repository;
  int _generation = 0;
  ResidentTaxAnnualData? _data;
  final _drafts = <String, _AnnualDraft>{};
  Set<String> _savingWorkers = {};
  bool _busy = false, _sourceConflict = false, _confirming = false;
  bool _invalidated = true, _foreground = true;
  int _sessionEpoch = 0, _authBinding = 0;
  String? _actor, _token;
  SupabaseClient? _authClient;
  StreamSubscription<AuthState>? _authSubscription;
  DialogRoute<bool>? _confirmationRoute;
  NavigatorState? _confirmationNavigator;
  String? _pendingRequest, _error, _message;
  bool get _sessionValid => !_invalidated && _foreground && _actor != null && _token != null &&
    _authClient?.auth.currentUser?.id == _actor && _authClient?.auth.currentSession?.accessToken == _token;
  bool get _editable => _sessionValid && _data?.canEdit == true && !_busy && !_confirming && _pendingRequest == null && !_sourceConflict;
  bool get _dirty => _drafts.values.any((d) => d.dirty);
  bool _owns(_AnnualDraft draft) => identical(_drafts[draft.worker.id], draft);
  @override
  void initState() { super.initState(); WidgetsBinding.instance.addObserver(this);
    _foreground = WidgetsBinding.instance.lifecycleState == null || WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    _repository = widget.repository ?? SupabaseResidentTaxAnnualRepository(); _bindSession(); _load(); }
  void _bindSession() {
    unawaited(_authSubscription?.cancel()); final binding = ++_authBinding;
    _authClient = widget.authClient ?? (SupabaseBackend.isInitialized ? SupabaseBackend.client : null);
    _actor = _authClient?.auth.currentUser?.id; _token = _authClient?.auth.currentSession?.accessToken;
    _sessionEpoch++; _invalidated = _actor == null || _token == null;
    _authSubscription = _authClient?.auth.onAuthStateChange.listen((event) {
      if (binding == _authBinding && (event.session?.user.id != _actor || event.session?.accessToken != _token)) _invalidateSession();
    }, onError: (Object _) { if (binding == _authBinding) _invalidateSession(); });
  }
  bool _sameSession(int epoch, String? actor, String? token) => _sessionValid &&
    epoch == _sessionEpoch && actor == _actor && token == _token;
  void _closeConfirmation() {
    final route = _confirmationRoute, navigator = _confirmationNavigator;
    _confirmationRoute = null; _confirmationNavigator = null;
    if (route != null && navigator != null) { WidgetsBinding.instance.addPostFrameCallback((_) {
      if (navigator.mounted && route.isActive) navigator.removeRoute(route);
    }); }
  }
  void _invalidateSession() {
    _sessionEpoch++; _generation++; _invalidated = true; _closeConfirmation();
    if (!mounted) return;
    setState(() { _data = null; _busy = false; _confirming = false; _pendingRequest = null; _savingWorkers = {};
      _message = null; _error = 'ログイン・アプリの状態が変わりました。再読み込みして確認してください。'; });
    _clearDrafts();
  }
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground) _invalidateSession();
  }
  Future<bool> _showConfirmation(WidgetBuilder builder) async {
    if (!_sessionValid || _busy || _confirming) return false;
    final epoch = _sessionEpoch, actor = _actor, token = _token;
    setState(() => _confirming = true);
    final navigator = Navigator.of(context);
    final route = DialogRoute<bool>(context: context, builder: builder);
    _confirmationRoute = route; _confirmationNavigator = navigator;
    try { final approved = await navigator.push(route);
      return approved == true && mounted && _sameSession(epoch, actor, token);
    } finally {
      if (identical(_confirmationRoute, route)) {
        _confirmationRoute = null; _confirmationNavigator = null;
        if (mounted) setState(() => _confirming = false);
      }
    }
  }
  @override
  void didUpdateWidget(covariant ResidentTaxAnnualUpdatePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.companyId != widget.companyId || oldWidget.fiscalYear != widget.fiscalYear || oldWidget.repository != widget.repository || oldWidget.authClient != widget.authClient) {
      _invalidateSession(); _bindSession();
      _repository = widget.repository ?? SupabaseResidentTaxAnnualRepository();
      _data = null; _pendingRequest = null; _savingWorkers = {}; _clearDrafts(); _load();
    }
  }
  void _clearDrafts() { for (final d in _drafts.values) { d.dispose(); } _drafts.clear(); }
  @override
  void dispose() { _generation++; _sessionEpoch++; _authBinding++; _closeConfirmation();
    WidgetsBinding.instance.removeObserver(this); unawaited(_authSubscription?.cancel()); _clearDrafts(); super.dispose(); }
  Future<void> _load() async {
    if (!_sessionValid) { setState(() { _data = null; _busy = false; _error = 'ログイン状態を確認して再読み込みしてください。'; }); return; }
    final generation = ++_generation, year = widget.fiscalYear;
    final epoch = _sessionEpoch, actor = _actor, token = _token;
    final company = widget.companyId, request = _pendingRequest;
    setState(() { _busy = true; _error = null; _data = null; });
    try {
      final observed = await _repository.read(company, year, requestId: request);
      if (!mounted || generation != _generation || !_sameSession(epoch, actor, token)) return;
      if (request != null && observed.receipt?['request_id'] != request) {
        setState(() => _error = '保存結果はまだ確認できません。時間をおいて再読み込みしてください。'); return;
      }
      // Receipts prove a past operation, never the current amounts or completion.
      final data = request == null ? observed : await _repository.read(company, year);
      if (!mounted || generation != _generation || !_sameSession(epoch, actor, token)) return;
      final next = <String, _AnnualDraft>{}; var conflict = false;
      for (final worker in data.workers) {
        final old = _drafts[worker.id];
        if (request != null && old != null && old.dirty && !_savingWorkers.contains(worker.id)) {
          next[worker.id] = old;
          if (old.worker.sourceJson != worker.sourceJson) conflict = true;
        } else { next[worker.id] = _AnnualDraft(worker); }
      }
      for (final old in _drafts.values) { if (!next.values.contains(old)) old.dispose(); }
      _drafts..clear()..addAll(next);
      setState(() { _data = data; _pendingRequest = null; _savingWorkers = {}; _sourceConflict = conflict;
        if (conflict) { _error = '別の更新と重なった未保存入力を保持しています。再読み込みで登録済みの金額を確認してください。'; }
        if (request != null) { _message = observed.receipt?['undone'] == true ? '住民税を元に戻しました。' :
          data.complete ? '全員分の住民税を更新しました。' : '住民税を更新しました。'; } });
    } catch (_) { if (mounted && generation == _generation) { setState(() { _data = null;
      _error = request == null ? '住民税の一覧を取得できません。接続・利用権限・サーバーの準備状況を確認してください。'
        : '保存結果を確認できません。再読み込みで確認してください。'; }); }
    } finally { if (mounted && generation == _generation) setState(() => _busy = false); }
  }
  Future<void> _reload() async {
    if (_busy || _confirming || !_foreground) return;
    if (!_sessionValid) { _bindSession(); if (!_sessionValid) return; }
    if (_pendingRequest == null && _dirty) {
      final discard = await _showConfirmation((c) => AlertDialog(
        title: const Text('未保存の入力があります'), content: const Text('入力を破棄して再読み込みしますか？'),
        actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('戻る')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('入力を破棄'))]));
      if (!mounted || discard != true) return;
    }
    if (mounted) await _load();
  }
  String _month(int index) => '${widget.fiscalYear + (index >= 7 ? 1 : 0)}-${((index + 5) % 12 + 1).toString().padLeft(2, '0')}';
  String _updated(DateTime? date) {
    if (date == null) return '未更新';
    final d = date.toUtc().add(const Duration(hours: 9));
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year}/${two(d.month)}/${two(d.day)} ${two(d.hour)}:${two(d.minute)}（日本時間）';
  }
  Widget _money(List<int?> values, int year) => Column(children: [
    Text(residentTaxAnnualDisplay(values), textAlign: TextAlign.center),
    Text('$year年度', style: Theme.of(context).textTheme.bodySmall, textAlign: TextAlign.center),
  ]);
  Widget _workerRow(_AnnualDraft d) => Card(key: ValueKey('annual-worker-${d.worker.id}'),
    child: Padding(padding: const EdgeInsets.all(10), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Expanded(flex: 2, child: Text(d.worker.name, style: const TextStyle(fontWeight: FontWeight.w600))),
        Expanded(flex: 2, child: _money(d.worker.previousAmounts, widget.fiscalYear - 1)),
        Expanded(flex: 2, child: _money(d.worker.currentAmounts, widget.fiscalYear)),
        const SizedBox(width: 6),
        Expanded(flex: 4, child: TextField(key: ValueKey('annual-input-${d.worker.id}'), controller: d.input,
          enabled: _editable && !d.worker.excluded, keyboardType: TextInputType.number,
          decoration: const InputDecoration(hintText: '新額', suffixText: '円', border: OutlineInputBorder(), isDense: true,
            contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 10)),
          onChanged: (_) => setState(() => d.dirty = true))),
        TextButton(key: ValueKey('annual-update-${d.worker.id}'), onPressed: _editable ? () => _save(d) : null,
          style: TextButton.styleFrom(minimumSize: const Size(44, 48), padding: const EdgeInsets.symmetric(horizontal: 4)), child: const Text('更新')),
      ]),
      Row(children: [Expanded(child: Text('最終更新日：${_updated(d.worker.lastUpdatedAt ?? d.worker.confirmedAt)}', style: Theme.of(context).textTheme.bodySmall)),
        TextButton(key: ValueKey('annual-undo-${d.worker.id}'),
          onPressed: _editable && (d.dirty || d.worker.undoRequestId != null) ? () => _undo(d) : null,
          child: const Text('元に戻す'))]),
    ])));
  String _requestId() { final r = Random.secure(); final b = List.generate(16, (_) => r.nextInt(256));
    b[6] = (b[6] & 15) | 64; b[8] = (b[8] & 63) | 128;
    final h = b.map((v) => v.toRadixString(16).padLeft(2, '0')).join();
    return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}'; }
  Future<void> _apply(_AnnualDraft d, {required bool undo, ResidentTaxAnnualInput? entry}) async {
    final data = _data;
    if (!_editable || data == null || !_owns(d)) return;
    final target = undo ? d.worker.undoAmounts! : entry!.amounts;
    final changes = [for (var i = 0; i < 12; i++) if (target[i] != d.worker.amounts[i])
      '${_month(i)}：${d.worker.amounts[i]} → ${target[i]}円'];
    final generation = _generation;
    final epoch = _sessionEpoch, actor = _actor, token = _token;
    final approved = await _showConfirmation((c) => AlertDialog(
      title: Text('${d.worker.name}の住民税${undo ? 'を元に戻す' : 'を更新'}'),
      content: SingleChildScrollView(child: Text('${widget.fiscalYear}年度（6月〜翌5月）。\n'
        '${changes.isEmpty ? '金額変更なし・通知書の確認状態を更新します。' : changes.join('\n')}\n\n'
        '${undo ? '直前の自分の更新前へ戻します。別の変更があれば上書きせず停止します。' : '適用開始は6月分です。この従業員だけを保存します。'}\n確定給与・年度外の登録額は変更しません。')),
      actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('戻る')),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(undo ? '確認して元に戻す' : '確認して更新'))]));
    if (!mounted || approved != true || generation != _generation || !_editable || !_owns(d) || !_sameSession(epoch, actor, token)) return;
    final request = _requestId();
    setState(() { _busy = true; _pendingRequest = request; _savingWorkers = {d.worker.id}; _error = null; _message = null; });
    try {
      if (undo) { await _repository.undo(data, d.worker, request); }
      else { await _repository.save(data, [entry!], request); }
      if (!mounted || generation != _generation) return; await _load();
    } on ResidentTaxAnnualReloadRequired {
      if (mounted && generation == _generation) { setState(() {
        _data = null; _busy = false; _pendingRequest = null; _savingWorkers = {};
        _error = '登録内容・権限が変わりました。再読み込みして確認してください。';
      }); }
    } catch (_) { if (mounted && generation == _generation) { setState(() {
      _data = null; _busy = false; _error = '保存結果を確認できません。再読み込みで確認してください。'; }); } }
  }
  Future<void> _save(_AnnualDraft d) async {
    if (!_editable || !_owns(d)) return;
    try {
      final text = d.input.text.trim();
      var values = List<int>.of(d.worker.amounts);
      if (text.isEmpty) {
        if (d.worker.currentAmounts.any((v) => v == null)) throw const FormatException('通知書の金額を記入してください。未確認を0円とは扱いません。');
      } else {
        if (d.worker.currentAmounts.whereType<int>().toSet().length > 1) {
          throw const FormatException('月別の税額が登録されています。個別給料設定で各月額を確認・変更してください。');
        }
        final amount = residentTaxAnnualYen(int.tryParse(text)); values = List.filled(12, amount);
      }
      await _apply(d, undo: false, entry: ResidentTaxAnnualInput(workerId: d.worker.id, amounts: values,
        excluded: d.worker.excluded, reason: d.worker.reason));
    } on FormatException catch (e) { if (mounted) setState(() => _error = e.message); }
  }
  Future<void> _undo(_AnnualDraft d) async {
    if (!_editable || !_owns(d)) return;
    if (d.dirty) {
      final values = d.worker.currentAmounts;
      setState(() { d.input.text = values.every((v) => v != null) && values.toSet().length == 1 ? '${values.first}' : ''; d.dirty = false; _error = null; });
      return;
    }
    if (d.worker.undoRequestId == null || d.worker.undoAmounts?.length != 12) {
      setState(() => _error = '元に戻る金額を確認できません。再読み込みしてください。'); return;
    }
    await _apply(d, undo: true);
  }
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('全員の住民税を更新'), actions: [IconButton(tooltip: '住民税更新の使い方',
      icon: const Icon(Icons.help_outline), onPressed: () => showDialog<void>(context: context, builder: (c) => AlertDialog(
        title: const Text('住民税更新の使い方'), content: const Text('通知書の金額を記入して、その従業員の「更新」を押します。同額の確認は未入力でも更新できますが、未確認の税額は明示入力が必要です。新額は6月〜翌5月へ適用します。月別の金額が異なる場合は個別給料設定で確認してください。前・現在の金額や年度は表示専用です。最終更新日はサーバーで確認できた日時です。保存前の「元に戻す」は記入を戻し、保存後は直前の自分の更新を確認して戻します。保存結果が不明な場合は再送せず再読み込みしてください。'),
        actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('閉じる'))])))]),
    body: SafeArea(child: ListView(padding: const EdgeInsets.all(12), children: [
      Text('${widget.fiscalYear}年度（${widget.fiscalYear}年6月〜${widget.fiscalYear + 1}年5月）', style: Theme.of(context).textTheme.titleMedium),
      const Text('原則、毎年6月の給与から切替。通知書の各月額を確認してください。'),
      if (widget.reminderPanel != null) widget.reminderPanel!,
      if (_busy) const LinearProgressIndicator(),
      if (_pendingRequest != null) const Text('保存結果の確認中です。再送せず、再読み込みしてください。'),
      if (_error != null) Text(_error!), if (_message != null) Text(_message!),
      OutlinedButton(onPressed: _busy ? null : _reload, child: const Text('住民税の一覧を再読み込み')),
      if (_data != null) ...[
        if (!_data!.scopeComplete) const Text('全従業員を確認できないため、更新はできません。'),
        if (!_data!.canEdit) const Text('閲覧のみ：住民税の更新は会社管理者が行います。'),
        Text('確認済み ${_data!.workers.where((w) => w.confirmed).length} / ${_data!.workers.length}名'),
        if (_data!.complete) const Text('この年度は全員更新済みです。'),
        const Padding(padding: EdgeInsets.symmetric(horizontal: 10, vertical: 8), child: Row(children: [
          Expanded(flex: 2, child: Text('名前')), Expanded(flex: 2, child: Text('前住民税', textAlign: TextAlign.center)),
          Expanded(flex: 2, child: Text('現在住民税', textAlign: TextAlign.center)), SizedBox(width: 6),
          Expanded(flex: 4, child: Text('記入枠', textAlign: TextAlign.center)), SizedBox(width: 44),
        ])),
        for (final d in _drafts.values) _workerRow(d),
      ],
    ])),
  );
}
