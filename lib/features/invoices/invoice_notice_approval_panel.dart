import 'dart:typed_data';
import 'package:flutter/material.dart';
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
        _InvoiceNoticeOwnPreview(bytes: bytes, current: () => mounted && generation == _generation));
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
  const _InvoiceNoticeOwnPreview({required this.bytes, required this.current});
  final Uint8List bytes;
  final bool Function() current;
  @override State<_InvoiceNoticeOwnPreview> createState() => _InvoiceNoticeOwnPreviewState();
}
class _InvoiceNoticeOwnPreviewState extends State<_InvoiceNoticeOwnPreview> {
  bool _failed = false;
  @override Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('注文請書と登録印影')),
    body: Column(children: [
      Expanded(child: PdfPreview(build: (_) async => widget.bytes,
        canChangePageFormat: false, canChangeOrientation: false, allowPrinting: false, allowSharing: false,
        onError: (context, error) {
          _failed = true;
          WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) { setState(() {}); } });
          return const Center(child: Text('本文と印影を表示できません'));
        })),
      SafeArea(top: false, child: FilledButton(onPressed: _failed ? null : () {
        if (!_failed && widget.current()) { Navigator.of(context).pop(true); }
      }, child: const Text('表示内容と印影を確認しました'))),
    ]));
}
