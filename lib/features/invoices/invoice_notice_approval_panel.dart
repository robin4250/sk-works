import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:printing/printing.dart';
import 'invoice_approval_readiness.dart';
import 'invoice_notice_ticket_controller.dart';
import 'invoice_notice_recovery_controller.dart';

/// Candidate-only screen binding. No controller means OFF and no RPC call.
/// Server must return revision-bound readiness and atomically recheck approval.
class InvoiceNoticeApprovalPanel extends StatefulWidget {
  const InvoiceNoticeApprovalPanel({super.key, required this.controller,
    required this.notificationId, required this.invoiceId, required this.revision,
    required this.isApprover, required this.confirmSavedApproval, this.recoveryController})
      : assert(controller == null || recoveryController == null);
  final InvoiceNoticeTicketController? controller;
  final InvoiceNoticeRecoveryController? recoveryController;
  final String notificationId, invoiceId, revision;
  final bool isApprover;
  final Future<bool> Function() confirmSavedApproval;
  @override
  State<InvoiceNoticeApprovalPanel> createState() => _InvoiceNoticeApprovalPanelState();
}

class _InvoiceNoticeApprovalPanelState extends State<InvoiceNoticeApprovalPanel>
    with WidgetsBindingObserver {
  Object? _receipt;
  bool _busy = false, _uncertain = false, _submitting = false;
  int _generation = 0;
  bool _previewVerified = false, _financialConsent = false, _sealConsent = false, _previewError = false;
  Route<bool>? _previewRoute;
  bool get _requiresConsent => widget.recoveryController?.explicitConsentRequired == true;
  bool get _consented => !_requiresConsent || _previewVerified && _financialConsent && _sealConsent;
  void _resetConsent() { _previewVerified = false; _financialConsent = false; _sealConsent = false; _previewError = false; }
  void _closePreview() {
    final route = _previewRoute; _previewRoute = null;
    if (route != null) { WidgetsBinding.instance.addPostFrameCallback((_) { if (route.isActive) { route.navigator?.removeRoute(route); } }); }
  }
  InvoiceNoticeTicketController? get _controller => widget.recoveryController?.tickets ?? widget.controller;
  void _recoveryChanged() {
    if (widget.recoveryController?.state != InvoiceNoticeRecoveryState.invalidated) { return; }
    _generation++; _resetConsent(); _closePreview();
    if (mounted) { setState(() { _receipt = null; _busy = false; _submitting = false; _uncertain = true; }); }
  }
  void _invalidate(InvoiceNoticeApprovalPanel panel) {
    _resetConsent(); _closePreview();
    panel.recoveryController?.invalidate();
    panel.controller?.invalidate();
  }
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.recoveryController?.addListener(_recoveryChanged);
    _load();
  }
  @override
  void didUpdateWidget(covariant InvoiceNoticeApprovalPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller || oldWidget.recoveryController != widget.recoveryController ||
        oldWidget.notificationId != widget.notificationId ||
        oldWidget.invoiceId != widget.invoiceId || oldWidget.revision != widget.revision) {
      oldWidget.recoveryController?.removeListener(_recoveryChanged);
      _invalidate(oldWidget);
      widget.recoveryController?.addListener(_recoveryChanged);
      _uncertain = false;
      _load();
    }
  }
  @override
  void dispose() {
    _generation++;
    widget.recoveryController?.removeListener(_recoveryChanged);
    _invalidate(widget);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      _generation++;
      _invalidate(widget);
      if (mounted) { setState(() {
        _receipt = null; _busy = false;
        if (_submitting) { _uncertain = true; }
      }); }
    }
  }
  Future<void> _load() async {
    final generation = ++_generation;
    _receipt = null;
    _resetConsent();
    _busy = false;
    final controller = _controller;
    if (controller == null || _uncertain) { return; }
    setState(() => _busy = true);
    final opened = await controller.open(widget.notificationId,
      invoiceId: widget.invoiceId, sourceRevision: widget.revision);
    if (!mounted || generation != _generation) { return; }
    setState(() {
      _busy = false;
      _receipt = opened ? {'invoice_id': widget.invoiceId,
        'source_revision': widget.revision, 'status': 'ready'} : null;
    });
  }
  Future<void> _approve() async {
    final controller = _controller;
    if (_busy || _uncertain || !_consented || controller == null || !widget.isApprover) { return; }
    final generation = _generation;
    setState(() { _busy = true; _submitting = true; _receipt = null; });
    final recovery = widget.recoveryController;
    final result = recovery == null ? await controller.approve() : await recovery.approve(
      financialConfirmed: _financialConsent, sealConfirmed: _sealConsent);
    if (!mounted || generation != _generation) { return; }
    var confirmed = false;
    if (widget.recoveryController != null && result != InvoiceNoticeApprovalResult.notSubmitted) {
      confirmed = await widget.recoveryController!.reconcile();
    } else if (result == InvoiceNoticeApprovalResult.confirmed) {
      try { confirmed = await widget.confirmSavedApproval().timeout(const Duration(seconds: 20)); } catch (_) {}
    }
    if (!mounted || generation != _generation) { return; }
    setState(() {
      _busy = false; _submitting = false;
      _uncertain = result != InvoiceNoticeApprovalResult.notSubmitted && !confirmed;
      _receipt = confirmed ? {'invoice_id': widget.invoiceId,
        'source_revision': widget.revision, 'status': 'already_approved'} : null;
    });
  }
  Future<void> _viewPreview() async {
    final build = widget.recoveryController?.buildOwnPreview;
    if (_busy || _uncertain || build == null) { return; }
    final generation = _generation;
    setState(() { _busy = true; _resetConsent(); });
    try {
      final bytes = await build().timeout(const Duration(seconds: 20));
      if (!mounted || generation != _generation || bytes.isEmpty) { return; }
      final route = MaterialPageRoute<bool>(fullscreenDialog: true, builder: (_) =>
        _InvoiceNoticeOwnPreview(bytes: bytes, recovery: widget.recoveryController!, current: () => mounted && generation == _generation));
      _previewRoute = route;
      final reviewed = await Navigator.of(context).push(route);
      if (identical(_previewRoute, route)) { _previewRoute = null; }
      if (!mounted || generation != _generation) { return; }
      setState(() => _previewVerified = reviewed == true);
    } catch (_) {
      if (mounted && generation == _generation) { setState(() { _resetConsent(); _previewError = true; }); }
    } finally { if (mounted && generation == _generation) { setState(() => _busy = false); } }
  }
  Future<void> _reconcile() async {
    final recovery = widget.recoveryController;
    if (_busy || recovery == null || recovery.state == InvoiceNoticeRecoveryState.invalidated) { return; }
    final generation = _generation;
    setState(() => _busy = true);
    final confirmed = await recovery.reconcile();
    if (!mounted || generation != _generation) { return; }
    setState(() {
      _busy = false; _uncertain = !confirmed;
      _receipt = confirmed ? {'invoice_id': widget.invoiceId,
        'source_revision': widget.revision, 'status': 'already_approved'} : null;
    });
  }
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start, children: [
      InvoiceApprovalReadinessNotice(
        readiness: _busy ? const InvoiceApprovalReadiness.checking()
          : InvoiceApprovalReadiness.fromServer(_receipt,
              invoiceId: widget.invoiceId, revision: widget.revision),
        isApprover: widget.isApprover, fromNotification: true, busy: _busy,
        onApprove: _consented ? _approve : null,
        onReload: _controller == null || _uncertain ? null : _load),
      if (_requiresConsent && !_uncertain && _receipt is Map && (_receipt as Map)['status'] == 'ready') ...[
        TextButton(onPressed: _busy ? null : _viewPreview, child: const Text('注文請書と登録印影を確認')),
        CheckboxListTile(value: _financialConsent, onChanged: !_busy && _previewVerified ? (value) => setState(() => _financialConsent = value == true) : null,
          title: const Text('請求書の最終承認と注文請書の内容を確認しました')),
        CheckboxListTile(value: _sealConsent, onChanged: !_busy && _previewVerified ? (value) => setState(() => _sealConsent = value == true) : null,
          title: const Text('会社に登録した自社の角印の使用を承認します')),
        if (_previewError) const Text('確認用の本文と印影を表示できません。承認は送信していません。'),
      ],
      if (_uncertain && widget.recoveryController != null &&
          widget.recoveryController!.state != InvoiceNoticeRecoveryState.invalidated)
        TextButton(onPressed: _busy ? null : _reconcile, child: const Text('保存済みの承認結果を確認')),
      if (_uncertain) const Text('承認結果を確認できません。再送せず、請求書を開き直して保存状態を確認してください。'),
    ]);
}


class _InvoiceNoticeOwnPreview extends StatefulWidget {
  const _InvoiceNoticeOwnPreview({required this.bytes, required this.current, required this.recovery});
  final Uint8List bytes;
  final bool Function() current;
  final InvoiceNoticeRecoveryController recovery;
  @override State<_InvoiceNoticeOwnPreview> createState() => _InvoiceNoticeOwnPreviewState();
}
class _InvoiceNoticeOwnPreviewState extends State<_InvoiceNoticeOwnPreview> with WidgetsBindingObserver {
  bool _active = true, _failed = false, _finished = false;
  int _generation = 0;
  final _pages = <Uint8List>[];
  final _decoded = <int>{};
  final _clock = Stopwatch();
  StreamIterator<PdfRaster>? _iterator;
  Timer? _timer;
  bool _current(int version) => mounted && _active && !_failed && version == _generation &&
      widget.current() && widget.recovery.state != InvoiceNoticeRecoveryState.invalidated &&
      _clock.elapsed < const Duration(seconds: 20);
  @override void initState() {
    super.initState(); WidgetsBinding.instance.addObserver(this);
    widget.recovery.addListener(_authChanged);
    _clock.start(); _timer = Timer(const Duration(seconds: 20), _fail);
    unawaited(_load());
  }
  void _authChanged() { if (widget.recovery.state == InvoiceNoticeRecoveryState.invalidated) { _fail(); } }
  void _fail() {
    if (!_active) { return; }
    _active = false; _failed = true; _finished = false; _generation++;
    _timer?.cancel(); _pages.clear(); _decoded.clear();
    final iterator = _iterator; _iterator = null;
    if (iterator != null) { unawaited(iterator.cancel()); }
    if (mounted) {
      if (SchedulerBinding.instance.schedulerPhase == SchedulerPhase.persistentCallbacks) {
        WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) { setState(() {}); } });
      } else { setState(() {}); }
    }
  }
  void _settleDisplay() {
    if (_finished && _pages.isNotEmpty && _decoded.length == _pages.length && _current(_generation)) {
      _clock.stop(); _timer?.cancel();
    }
  }
  @override void didChangeAppLifecycleState(AppLifecycleState state) { if (state != AppLifecycleState.resumed) { _fail(); } }
  @override void dispose() {
    widget.recovery.removeListener(_authChanged); WidgetsBinding.instance.removeObserver(this);
    _active = false; _generation++; _timer?.cancel();
    final iterator = _iterator; _iterator = null;
    if (iterator != null) { unawaited(iterator.cancel()); }
    _pages.clear(); _decoded.clear(); super.dispose();
  }
  Future<void> _load() async {
    final version = _generation;
    try {
      if (!_current(version)) { return; }
      final capabilities = await Printing.info();
      if (!_current(version) || !capabilities.canRaster) { _fail(); return; }
      // No lazy callback can return retained PDF bytes after invalidation.
      final iterator = StreamIterator(Printing.raster(widget.bytes, dpi: 96));
      _iterator = iterator; var total = 0;
      while (await iterator.moveNext()) {
        if (!_current(version)) { _fail(); return; }
        final page = iterator.current;
        if (page.width <= 0 || page.height <= 0 || page.width * page.height > 8000000 || _pages.length >= 16) { _fail(); return; }
        final bytes = await page.toPng();
        if (!_current(version)) { _fail(); return; }
        total += bytes.length;
        if (bytes.isEmpty || bytes.length > 4194304 || total > 16777216) { _fail(); return; }
        setState(() => _pages.add(bytes));
      }
      if (!_current(version) || _pages.isEmpty) { _fail(); return; }
      setState(() { _finished = true; _settleDisplay(); });
    } catch (_) { _fail(); }
  }
  void _decodedPage(int index, int version) {
    if (_decoded.contains(index)) { return; }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_current(version) && !_decoded.contains(index)) { setState(() { _decoded.add(index); _settleDisplay(); }); }
    });
  }
  @override Widget build(BuildContext context) {
    final version = _generation, valid = _current(_generation);
    final ready = valid && _finished && _pages.isNotEmpty && _decoded.length == _pages.length;
    return Scaffold(appBar: AppBar(title: const Text('注文請書と登録印影')), body: Column(children: [
      Expanded(child: !valid ? const Center(child: Text('本文と印影を表示できません')) :
        _pages.isEmpty ? const Center(child: CircularProgressIndicator()) : ListView(children: [
          for (var index = 0; index < _pages.length; index++) Image.memory(_pages[index],
            frameBuilder: (context, image, frame, synchronous) {
              if (!_current(version)) { return const SizedBox.shrink(); }
              if (frame != null) { _decodedPage(index, version); }
              return image;
            }, errorBuilder: (context, error, stack) {
              // Disable acknowledgement synchronously, then retire image data
              // outside this build frame.
              _failed = true;
              WidgetsBinding.instance.addPostFrameCallback((_) { _fail(); });
              return const Text('本文と印影を表示できません');
            }),
        ])),
      SafeArea(top: false, child: FilledButton(onPressed: ready ? () {
        if (_current(version) && _finished && _decoded.length == _pages.length) { Navigator.of(context).pop(true); }
      } : null, child: const Text('表示内容と印影を確認しました'))),
    ]));
  }
}
