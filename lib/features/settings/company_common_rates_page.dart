import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'company_common_rates_pending.dart';
import 'company_common_rates_repository.dart';

class CompanyCommonRatesPage extends StatefulWidget {
  const CompanyCommonRatesPage({super.key, required this.companyId, this.embedded = false,
    this.repository, this.pendingStore});
  final String companyId;
  final bool embedded;
  final CompanyCommonRatesRepository? repository;
  final CompanyCommonRatesPendingStore? pendingStore;
  @override
  State<CompanyCommonRatesPage> createState() => _CompanyCommonRatesPageState();
}
class _CompanyCommonRatesPageState extends State<CompanyCommonRatesPage> with WidgetsBindingObserver {
  final _rates = {for (final key in companyCommonRateLabels.keys) key: TextEditingController()};
  final _form = GlobalKey<FormState>();
  late final CompanyCommonRatesRepository? _repository;
  late final CompanyCommonRatesPendingStore _store;
  StreamSubscription<String?>? _subscription;
  Route<bool>? _dialog;
  String? _actor;
  String? _company;
  CompanyCommonRatesState? _base;
  CompanyCommonRatesState? _latest;
  CompanyCommonRatesRequest? _pending;
  AppLifecycleState _lifecycle = AppLifecycleState.resumed;
  int _generation = 0;
  bool _invalid = false;
  bool _busy = false;
  bool _dirty = false;
  bool _conflict = false;
  bool _needsRefresh = true;
  bool _unavailable = false;
  String? _error;
  String? _success;
  bool get _sameActor => !_invalid && _actor != null && _repository?.actorId == _actor;
  bool _current(int generation) => mounted && _sameActor && generation == _generation && _lifecycle == AppLifecycleState.resumed;
  bool get _editable => _sameActor && _lifecycle == AppLifecycleState.resumed && !_busy && !_needsRefresh &&
      !_unavailable && _pending == null && _latest?.canEdit == true;

  @override
  void initState() {
    super.initState();
    _repository = widget.repository ?? SupabaseCompanyCommonRatesRepository.maybeCreate();
    _store = widget.pendingStore ?? FileCompanyCommonRatesPendingStore();
    _lifecycle = WidgetsBinding.instance.lifecycleState ?? AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
    try {
      _company = commonRatesUuid(widget.companyId);
      final actor = _repository?.actorId;
      if (actor == null) throw StateError('No actor');
      _actor = commonRatesUuid(actor);
      if (_store.actorId() != _actor) throw StateError('Wrong actor');
      _subscription = _repository!.actorChanges.listen((actor) {
        if (actor != _actor) _invalidate();
      }, onError: (Object error) => _invalidate());
      if (_lifecycle == AppLifecycleState.resumed) _load();
    } catch (_) {
      _invalid = true;
      _error = '会社・ログイン状態を確認して画面を開き直してください。';
    }
  }
  void _invalidate() {
    if (!mounted || _invalid) return;
    _generation++;
    _dismissDialog();
    for (final controller in _rates.values) { controller.clear(); }
    setState(() {
      _invalid = true; _busy = false; _base = null; _latest = null; _pending = null;
      _error = '会社・ログイン状態が変わりました。画面を開き直してください。';
      _success = null;
    });
  }
  void _dismissDialog() {
    final route = _dialog;
    if (route != null && route.isActive) route.navigator?.removeRoute(route);
    _dialog = null;
  }
  @override
  void didUpdateWidget(covariant CompanyCommonRatesPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.companyId != widget.companyId || !identical(oldWidget.repository, widget.repository) ||
        !identical(oldWidget.pendingStore, widget.pendingStore)) {
      _invalidate();
    }
  }
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final wasResumed = _lifecycle == AppLifecycleState.resumed;
    _lifecycle = state;
    if (state != AppLifecycleState.resumed) {
      _generation++;
      _dismissDialog();
      setState(() { _busy = false; _needsRefresh = true; _success = null; });
    } else if (!wasResumed && !_invalid) {
      _load();
    }
  }
  void _useState(CompanyCommonRatesState state) {
    _base = state; _latest = state;
    for (final key in companyCommonRateLabels.keys) { _rates[key]!.text = '${state.rates[key]}'; }
    _dirty = false; _conflict = false;
  }
  Future<void> _load() async {
    final repository = _repository;
    final company = _company;
    if (!_sameActor || _busy || repository == null || company == null || _lifecycle != AppLifecycleState.resumed) return;
    final generation = ++_generation;
    final keepDraft = _dirty;
    setState(() { _busy = true; _error = null; _success = null; _unavailable = false; _needsRefresh = true; });
    try {
      final pending = await _store.read(company);
      if (!_current(generation)) return;
      _pending = pending;
      final state = await repository.read(company);
      if (!_current(generation) || _store.actorId() != _actor) return;
      _latest = state;
      var confirmed = false;
      if (pending != null) {
        for (final key in companyCommonRateLabels.keys) { _rates[key]!.text = '${pending.rates[key]}'; } _dirty = true;
        if (state.canEdit) {
          final result = await repository.receipt(pending);
          if (!_current(generation) || _store.actorId() != _actor) return;
          if (result != null) {
            await _store.clear(pending);
            if (!_current(generation)) return;
            _pending = null; confirmed = true;
            _success = '保存を確認しました。最新設定を再確認してください。';
          }
        }
      }
      // A receipt is historical proof. Re-read current values rather than
      // presenting its old result as the latest company configuration.
      final fresh = confirmed ? await repository.read(company) : state;
      if (!_current(generation) || _store.actorId() != _actor) return;
      setState(() {
        _latest = fresh; _needsRefresh = false;
        if (_pending != null) {
          _error = '先の保存結果を確認できません。再送せず「保存状態を再確認」を押してください。';
        } else if (confirmed || !keepDraft) {
          _useState(fresh);
          if (confirmed) _success = '残業・早出などの単価の保存を確認しました。';
        } else if (_base == null || !_base!.sameSource(fresh)) {
          _conflict = true;
          _error = '保存済みの設定が更新されています。入力は保持しました。最新設定を確認してください。';
        } else {
          _base = fresh;
        }
      });
    } on CompanyCommonRatesUnavailable {
      if (_current(generation)) setState(() { _unavailable = true; _error = '設定機能は準備中です。入力内容は保持しています。'; });
    } catch (_) {
      if (_current(generation)) setState(() => _error = '設定を確認できません。入力を保持しています。権限・接続を確認して再読み込みしてください。');
    } finally {
      if (_current(generation)) setState(() => _busy = false);
    }
  }
  String _newRequestId() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 15) | 64; bytes[8] = (bytes[8] & 63) | 128;
    final hex = bytes.map((value) => value.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }
  Future<void> _save() async {
    final repository = _repository;
    final base = _base;
    if (!_editable || !_dirty || _conflict || base == null || repository == null || !(_form.currentState?.validate() ?? false)) return;
    final generation = ++_generation;
    final rates = {for (final key in companyCommonRateLabels.keys) key: int.parse(_rates[key]!.text.trim())};
    setState(() { _busy = true; _error = null; _success = null; });
    CompanyCommonRatesRequest? request;
    bool sent = false;
    bool persisted = false;
    try {
      final fresh = await repository.read(base.companyId);
      if (!_current(generation) || _store.actorId() != _actor) return;
      _latest = fresh;
      if (!fresh.canEdit) {
        setState(() { _needsRefresh = false; _error = '現在は閲覧のみです。入力内容は保持しています。'; });
        return;
      }
      if (!base.sameSource(fresh)) {
        setState(() { _conflict = true; _error = '保存済みの設定が更新されています。入力は保持しました。最新設定を確認してください。'; });
        return;
      }
      request = CompanyCommonRatesRequest(companyId: base.companyId, actorId: _actor!, requestId: _newRequestId(),
        expectedVersion: base.version, expectedRates: base.rates, rates: rates);
      _pending = request;
      await _store.write(request);
      persisted = true;
      if (!_current(generation)) {
        // This invocation definitely has not called a mutation. Only this exact
        // prepared record can be cleared, and never under another actor.
        if (_sameActor) await _store.clear(request);
        return;
      }
      if (_store.actorId() != _actor) return;
      sent = true;
      final result = await repository.save(request);
      if (!_current(generation) || _store.actorId() != _actor) return;
      await _store.clear(request);
      if (!_current(generation)) return;
      setState(() {
        _pending = null; _needsRefresh = false; _useState(result);
        _success = '残業・早出などの単価を保存しました。';
      });
    } catch (error) {
      if (!_current(generation)) return;
      final rejected = error is CompanyCommonRatesUnavailable ||
          (error is PostgrestException && const {'40001', '22023', '42501'}.contains(error.code));
      if (sent && rejected && request != null) {
        try {
          await _store.clear(request);
          if (!_current(generation)) return;
          _pending = null;
        } catch (_) { /* Preserve the journal if exact cleanup cannot be proven. */ }
      }
      if (!_current(generation)) return;
      setState(() {
        _needsRefresh = true;
        _unavailable = error is CompanyCommonRatesUnavailable;
        if (_pending != null && (sent || persisted)) {
          _error = '保存結果を確認できません。入力は保持しました。再送せず保存状態を再確認してください。';
        } else if (_unavailable) {
          _error = '設定機能は準備中です。入力内容は保持しています。';
        } else {
          _error = '保存は完了していません。入力内容を保持しました。最新設定を再確認してください。';
        }
      });
    } finally {
      if (_current(generation)) setState(() => _busy = false);
    }
  }
  Future<void> _acceptLatest() async {
    final latest = _latest;
    if (!_editable || !_conflict || latest == null) return;
    final generation = _generation;
    final route = DialogRoute<bool>(context: context, builder: (context) => AlertDialog(
      title: const Text('最新の設定を確認'),
      content: Text([for (final key in companyCommonRateLabels.keys) '${companyCommonRateLabels[key]}\n保存済み：${latest.rates[key]}／入力中：${_rates[key]!.text}'].join('\n\n') + '\n\n入力を保持して編集を続けます。まだ保存は行いません。'),
      actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('戻る')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('確認して編集を続ける'))]));
    _dialog = route;
    final accepted = await Navigator.of(context, rootNavigator: true).push<bool>(route);
    if (identical(_dialog, route)) _dialog = null;
    if (accepted == true && _current(generation) && identical(latest, _latest)) {
      setState(() { _base = latest; _conflict = false; _error = null; });
    }
  }
  String? _validate(String? text) {
    final raw = text?.trim() ?? '';
    final value = int.tryParse(raw);
    return RegExp(r'^\d+$').hasMatch(raw) && value != null && value >= 0 && value <= 2147483647 ? null : '0〜2147483647の整数で入力してください';
  }
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _subscription?.cancel(); _generation++;
    for (final controller in _rates.values) { controller.clear(); controller.dispose(); }
    super.dispose();
  }
  @override
  Widget build(BuildContext context) {
    final latest = _latest;
    final body = Column(children: [
      if (_busy) const LinearProgressIndicator(),
      Expanded(child: _lifecycle != AppLifecycleState.resumed
        ? const Center(child: Text('画面に戻ると設定を確認します。'))
        : Form(key: _form, child: ListView(padding: const EdgeInsets.all(16), children: [
          const Text('残業・早出などの単価', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          const Text('登録済みの残業・早出・夜勤・休日の単価です。税率・福利厚生費率・手当は変更しません。'),
          if (latest != null && !latest.canEdit) const Padding(padding: EdgeInsets.only(top: 12), child: Text('閲覧のみ')),
          if (_error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_error!)),
          if (_success != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_success!, style: const TextStyle(color: Colors.green))),
          const SizedBox(height: 16),
          for (final key in companyCommonRateLabels.keys) Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: TextFormField(key: Key('company-common-rates-$key'), controller: _rates[key], readOnly: !_editable,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly], validator: _validate,
              decoration: InputDecoration(labelText: companyCommonRateLabels[key], border: const OutlineInputBorder()),
              onChanged: (_) => setState(() { _dirty = true; _success = null; })),
          ),
          const SizedBox(height: 16),
          if (_conflict && _pending == null)
            OutlinedButton(onPressed: _editable ? _acceptLatest : null, child: const Text('最新設定を確認')),
          FilledButton(onPressed: _editable && _dirty && !_conflict && _base != null ? _save : null,
            child: const Text('保存')),
          TextButton(onPressed: !_busy && _sameActor ? _load : null,
            child: Text(_pending == null ? '最新設定を再確認' : '保存状態を再確認')),
        ]))),
    ]);
    return widget.embedded ? body : Scaffold(appBar: AppBar(title: const Text('残業・早出などの単価')), body: body);
  }
}

