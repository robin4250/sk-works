import 'package:flutter/material.dart';
import 'invoice_approval_readiness.dart';
import 'invoice_notice_ticket_controller.dart';

/// Candidate-only screen binding. No controller means OFF and no RPC call.
/// Server must return revision-bound readiness and atomically recheck approval.
class InvoiceNoticeApprovalPanel extends StatefulWidget {
  const InvoiceNoticeApprovalPanel({super.key, required this.controller,
    required this.notificationId, required this.invoiceId, required this.revision,
    required this.isApprover, required this.confirmSavedApproval});
  final InvoiceNoticeTicketController? controller;
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
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }
  @override
  void didUpdateWidget(covariant InvoiceNoticeApprovalPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller ||
        oldWidget.notificationId != widget.notificationId ||
        oldWidget.invoiceId != widget.invoiceId || oldWidget.revision != widget.revision) {
      oldWidget.controller?.invalidate();
      _load();
    }
  }
  @override
  void dispose() {
    _generation++;
    widget.controller?.invalidate();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      _generation++;
      widget.controller?.invalidate();
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
    final controller = widget.controller;
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
    final controller = widget.controller;
    if (_busy || _uncertain || controller == null || !widget.isApprover) { return; }
    final generation = _generation;
    setState(() { _busy = true; _submitting = true; _receipt = null; });
    final result = await controller.approve();
    if (!mounted || generation != _generation) { return; }
    var confirmed = false;
    if (result == InvoiceNoticeApprovalResult.confirmed) {
      try { confirmed = await widget.confirmSavedApproval(); } catch (_) {}
    }
    if (!mounted || generation != _generation) { return; }
    setState(() {
      _busy = false; _submitting = false;
      _uncertain = result != InvoiceNoticeApprovalResult.notSubmitted && !confirmed;
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
        onReload: widget.controller == null || _uncertain ? null : _load),
      if (_uncertain) const Text('承認結果を確認できません。再送せず、請求書を開き直して保存状態を確認してください。'),
    ]);
}
