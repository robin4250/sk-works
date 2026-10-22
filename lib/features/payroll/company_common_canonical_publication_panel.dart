import 'dart:async';
import 'package:flutter/material.dart';
import 'company_common_allowance_repository.dart';
import 'company_common_canonical_publication_approval.dart';
import 'company_common_canonical_publication_controller.dart';
import 'company_common_canonical_publication_pending_store.dart';
import 'company_common_canonical_publication_repository.dart';
import 'company_common_payroll_publication_repository.dart';

class CompanyCommonCanonicalPublicationPanel extends StatefulWidget {
  const CompanyCommonCanonicalPublicationPanel({super.key, required this.settings,
    required this.repository, this.pendingStore, this.enabled = true,
    this.canReconcile = true, this.initialPayrollType = 'hourly', this.onBusyChanged});
  final CompanyCommonAllowanceState settings;
  final CommonPayrollCanonicalPublicationRepository repository;
  final CommonPayrollCanonicalPublicationPendingStore? pendingStore;
  final bool enabled, canReconcile;
  final String initialPayrollType;
  final ValueChanged<bool>? onBusyChanged;
  @override State<CompanyCommonCanonicalPublicationPanel> createState() => _CompanyCommonCanonicalPublicationPanelState();
}

class _CompanyCommonCanonicalPublicationPanelState extends State<CompanyCommonCanonicalPublicationPanel>
    with WidgetsBindingObserver {
  late final CommonPayrollCanonicalPublicationController _controller;
  StreamSubscription<String?>? _subscription;
  late final String? _session, _actor;
  CommonPayrollPublicationState? _timeline;
  bool _busy = false, _confirming = false, _active = true, _revoked = false;
  bool _available = false, _storageBlocked = false;
  bool _running = false, _reloadRequested = false;
  int _generation = 0;
  late DateTime _month;
  late String _type;
  String? _error, _message;
  BuildContext? _dialog;
  DateTime get _currentMonth { final now = DateTime.now().toUtc().add(const Duration(hours: 9)); return DateTime(now.year, now.month); }
  bool _valid(int generation) => mounted && _active && !_revoked && generation == _generation &&
      widget.repository.sessionKey == _session && widget.repository.actorId == _actor;
  bool get _legacyReady => !widget.settings.legacyRefs.any((ref) => ref['amount_yen'] is int &&
      (ref['amount_yen'] as int) > 0 && ref['name'] is String && (ref['name'] as String).trim().isNotEmpty) ||
      widget.settings.expectedSource['legacy_adopted'] == true;
  void _parentBusy() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (mounted) widget.onBusyChanged?.call(_busy || _confirming || _controller.pending != null || _storageBlocked || _revoked);
  });
  @override void initState() {
    super.initState();
    _month = _currentMonth;
    _type = const ['daily', 'hourly', 'monthly'].contains(widget.initialPayrollType) ? widget.initialPayrollType : 'hourly';
    _session = widget.repository.sessionKey; _actor = widget.repository.actorId;
    _controller = CommonPayrollCanonicalPublicationController(companyId: widget.settings.companyId,
      repository: widget.repository, store: widget.pendingStore ??
        FileCommonPayrollCanonicalPublicationPendingStore(currentActor: () => widget.repository.actorId));
    _subscription = widget.repository.sessionChanges.listen((key) {
      if (key != _session || widget.repository.actorId != _actor) _revoke();
    }, onError: (Object _) => _revoke());
    WidgetsBinding.instance.addObserver(this);
    _active = WidgetsBinding.instance.lifecycleState == null || WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    if (_active) unawaited(_load());
  }
  @override void didUpdateWidget(covariant CompanyCommonCanonicalPublicationPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.settings.companyId != widget.settings.companyId || oldWidget.repository != widget.repository) _revoke();
  }
  void _closeDialog() {
    final dialog = _dialog; _dialog = null;
    if (dialog != null) WidgetsBinding.instance.addPostFrameCallback((_) {
      if (dialog.mounted && ModalRoute.of(dialog)?.isCurrent == true) Navigator.of(dialog).pop();
    });
  }
  void _revoke() {
    if (!mounted || _revoked) return;
    _generation++; _closeDialog();
    setState(() { _revoked = true; _timeline = null; _message = null;
      _error = 'ログイン情報が変わりました。画面を開き直してください。'; });
    _parentBusy();
  }
  @override void didChangeAppLifecycleState(AppLifecycleState state) {
    _active = state == AppLifecycleState.resumed;
    if (!_active) { _generation++; _closeDialog(); if (mounted) setState(() { _timeline = null; _message = null; }); }
    else if (!_revoked) unawaited(_load());
  }
  Future<void> _load() async {
    if (!_active || _revoked) return;
    if (_running || _controller.busy) { _reloadRequested = true; return; }
    final generation = ++_generation;
    _running = true;
    setState(() { _busy = true; _message = null; }); _parentBusy();
    try {
      await _controller.load();
      if (!_valid(generation)) return;
      final available = await widget.repository.available();
      if (!_valid(generation)) return;
      final timeline = available ? await widget.repository.read(widget.settings.companyId) : null;
      if (!_valid(generation)) return;
      setState(() { _available = available; _timeline = timeline; _storageBlocked = false;
        _error = available ? null : '給与への反映を確認できません。時間をおいて、もう一度確認してください。'; });
    } catch (_) {
      if (_valid(generation)) setState(() {
        _storageBlocked = !_controller.ready && _controller.pending == null;
        _error = _storageBlocked ? '前の給与反映の確認記録を読み取れません。給与への反映を止めています。'
            : '給与反映の設定を取得できません。もう一度確認してください。';
      });
    } finally { _finish(); }
  }
  void _finish() {
    _running = false;
    if (!mounted) return;
    setState(() { _busy = false; _confirming = false; });
    _parentBusy();
    if (_reloadRequested && _active && !_revoked) {
      _reloadRequested = false;
      unawaited(_load());
    }
  }
  Future<void> _start() async {
    final timeline = _timeline, generation = _generation;
    if (timeline == null || !timeline.canEdit || !_available || !_legacyReady || !_controller.ready ||
        !widget.enabled || _running || _busy || _confirming || !_valid(generation)) return;
    _running = true;
    setState(() { _busy = true; _message = null; _error = null; }); _parentBusy();
    try {
      final params = canonicalCommonPayrollPreviewParams(widget.settings, timeline, _type,
        '${_month.year}-${_month.month.toString().padLeft(2, '0')}-01');
      final preview = await widget.repository.preview(params);
      if (!_valid(generation) || !widget.enabled) return;
      setState(() { _busy = false; _confirming = true; });
      final approval = await showDialog<CommonPayrollCanonicalApproval>(context: context, builder: (context) {
        _dialog = context;
        return CommonPayrollCanonicalPublicationApprovalDialog(preview: preview.approvalView, deploymentAvailable: true);
      });
      _dialog = null;
      if (!_valid(generation) || approval == null || !widget.enabled) return;
      setState(() { _busy = true; _confirming = false; });
      final command = preview.approve(activation: approval.approveActivation, selectedDays: approval.approveSelectedDays);
      final result = await _controller.publish(command);
      if (!_valid(generation)) return;
      setState(() { _timeline = result.timeline; _message = result.message; _error = null; });
    } catch (_) {
      if (_valid(generation)) setState(() {
        _error = _controller.pending != null
          ? '給与反映の結果を確認できません。「結果を確認」で同じ申請の結果を確認してください。'
          : '給与へ反映できませんでした。保存済みの設定を再読み込みして確認してください。';
        _message = null;
      });
    } finally {
      _dialog = null;
      _finish();
    }
  }
  Future<void> _lookup() async {
    final generation = _generation;
    if (!_available || !_active || _revoked || _running || _busy || !widget.canReconcile || _controller.pending == null) return;
    _running = true;
    setState(() { _busy = true; _message = null; }); _parentBusy();
    try {
      final result = await _controller.lookup();
      if (!_valid(generation)) return;
      setState(() {
        if (result == null) _error = 'まだ結果を確認できません。同じ申請を保持しています。時間をおいて確認してください。';
        else { _timeline = result.timeline; _message = result.message; _error = null; }
      });
    } catch (_) { if (_valid(generation)) setState(() => _error = '結果を確認できません。同じ申請を保持しています。'); }
    finally { _finish(); }
  }
  @override void dispose() { _generation++; _subscription?.cancel(); WidgetsBinding.instance.removeObserver(this); super.dispose(); }
  @override Widget build(BuildContext context) {
    final editable = widget.enabled && !_busy && !_confirming && _active && !_revoked &&
        _available && _legacyReady && _controller.ready && _timeline?.canEdit == true;
    return Card(child: ExpansionTile(title: const Text('未確定給与への反映'),
      subtitle: const Text('保存済みの共通手当・適用開始月'), children: [
      Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: Row(children: [
        Expanded(child: DropdownButton<String>(key: const ValueKey('canonical-publication-type'),
          value: _type, isExpanded: true, items: [for (final type in ['daily', 'hourly', 'monthly'])
            DropdownMenuItem(value: type, child: Text(const {'daily': '日給', 'hourly': '時給', 'monthly': '月給'}[type]!))],
          onChanged: editable ? (type) => setState(() { _type = type!; _message = null; }) : null)),
        IconButton(key: const ValueKey('canonical-publication-previous'), icon: const Icon(Icons.chevron_left),
          onPressed: editable && _month.isAfter(_currentMonth) ? () => setState(() { _month = DateTime(_month.year, _month.month - 1); _message = null; }) : null),
        Text('${_month.year}/${_month.month}'),
        IconButton(key: const ValueKey('canonical-publication-next'), icon: const Icon(Icons.chevron_right),
          onPressed: editable && _month.isBefore(DateTime(_currentMonth.year, _currentMonth.month + 12))
            ? () => setState(() { _month = DateTime(_month.year, _month.month + 1); _message = null; }) : null),
      ])),
      if (!_legacyReady) const Padding(padding: EdgeInsets.all(12),
        child: Text('先に共通手当を保存してください。保存後に未確定給与へ反映できます。')),
      if (_error != null) Padding(padding: const EdgeInsets.all(12), child: Text(_error!)),
      if (_message != null) Padding(padding: const EdgeInsets.all(12), child: Text(_message!)),
      if (_controller.pending != null) TextButton(key: const ValueKey('canonical-publication-lookup'),
        onPressed: _busy || !_active || !_available || _revoked || !widget.canReconcile ? null : _lookup,
        child: const Text('結果を確認'))
      else TextButton(key: const ValueKey('canonical-publication-prepare'),
        onPressed: editable ? _start : null, child: const Text('対象を確認して反映')),
      if (_error != null) TextButton(onPressed: _busy || !_active || _revoked ? null : _load, child: const Text('再読み込み')),
      if (_busy) const LinearProgressIndicator(),
      for (final entry in (_timeline?.entries ?? const <Map<String, dynamic>>[]).take(5))
        ListTile(dense: true, title: Text('${const {'daily': '日給', 'hourly': '時給', 'monthly': '月給'}[entry['payroll_type']]} '
          '${(entry['starts_on'] as String).substring(0, 7)} 適用登録済み')),
    ]));
  }
}
