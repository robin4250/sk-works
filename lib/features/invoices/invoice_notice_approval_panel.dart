import 'package:flutter/material.dart';
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
  InvoiceNoticeTicketController? get _controller => widget.recoveryController?.tickets ?? widget.controller;
  void _recoveryChanged() {
    if (widget.recoveryController?.state != InvoiceNoticeRecoveryState.invalidated) { return; }
    _generation++;
    if (mounted) { setState(() { _receipt = null; _busy = false; _submitting = false; _uncertain = true; }); }
  }
  void _invalidate(InvoiceNoticeApprovalPanel panel) {
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
    if (_busy || _uncertain || controller == null || !widget.isApprover) { return; }
    final generation = _generation;
    setState(() { _busy = true; _submitting = true; _receipt = null; });
    final result = await controller.approve();
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
        onApprove: _approve,
        onReload: _controller == null || _uncertain ? null : _load),
      if (_uncertain && widget.recoveryController != null &&
          widget.recoveryController!.state != InvoiceNoticeRecoveryState.invalidated)
        TextButton(onPressed: _busy ? null : _reconcile, child: const Text('保存済みの承認結果を確認')),
      if (_uncertain) const Text('承認結果を確認できません。再送せず、請求書を開き直して保存状態を確認してください。'),
    ]);
}
