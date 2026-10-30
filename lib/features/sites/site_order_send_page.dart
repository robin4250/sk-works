import 'package:flutter/material.dart';
import 'site_order_workflow.dart';

/// The editor opens this page only after the server has persisted the sealed
/// artifact. No PDF or financial payload is sent through the ordinary site API.
class SiteOrderSendPage extends StatefulWidget {
  const SiteOrderSendPage({super.key, required this.workflow,
    required this.recipients, required this.send, required this.lookupReceipt,
    required this.scopeChanges});
  final SiteOrderSendWorkflow workflow;
  final List<SiteOrderRecipient> recipients;
  final Future<SiteOrderDeliveryReceipt> Function(SiteOrderDeliveryIntent) send;
  final Future<SiteOrderDeliveryReceipt?> Function(SiteOrderDeliveryIntent) lookupReceipt;
  final Listenable scopeChanges;
  @override
  State<SiteOrderSendPage> createState() => _SiteOrderSendPageState();
}

class _SiteOrderSendPageState extends State<SiteOrderSendPage> {
  String? _selected;
  String? _error;
  bool _busy = false;
  bool _retired = false;
  BuildContext? _confirmationContext;
  bool get _unknown => widget.workflow.state == SiteOrderSendState.outcomeUnknown;
  bool get _sent => widget.workflow.state == SiteOrderSendState.sent;

  @override
  void initState() { super.initState(); widget.scopeChanges.addListener(_checkScope); }
  void _checkScope() {
    try { widget.workflow.verify(); } catch (_) {
      if (mounted) setState(() => _retired = true);
      final dialog = _confirmationContext;
      if (dialog != null && dialog.mounted && ModalRoute.of(dialog)?.isCurrent == true) {
        Navigator.of(dialog).pop(false);
      }
    }
  }
  @override
  void dispose() { widget.scopeChanges.removeListener(_checkScope); super.dispose(); }

  void _back() {
    try {
      widget.workflow.returnToEditor();
      Navigator.of(context).pop(false);
    } catch (_) { setState(() {
      _retired = widget.workflow.state == SiteOrderSendState.retired;
      _error = '送信状態を確認してから入力画面に戻ってください。';
    }); }
  }

  Future<void> _share() async {
    if (_busy || _unknown || _sent) return;
    setState(() { _busy = true; _error = null; });
    try {
      final recipient = widget.recipients.singleWhere((r) => r.tradeCompanyId == _selected);
      widget.workflow.select(recipient);
      final intent = widget.workflow.confirm();
      final confirmed = await showDialog<bool>(context: context,
        barrierDismissible: false, builder: (dialogContext) {
          _confirmationContext = dialogContext;
          return AlertDialog(
          title: const Text('注文書を共有送信しますか？'),
          content: SingleChildScrollView(child: Column(
            mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start,
            children: [Text(intent.artifact.title), Text(intent.artifact.period),
              const SizedBox(height: 12),
              for (final price in intent.artifact.prices)
                Text('${price.item}\n単価 ${price.unitPriceYen}円／${price.unit}'),
              const SizedBox(height: 12),
              Text('上記の内容を「${intent.recipient.name}」に共有送信します。よろしいですか？'),
            ])),
          actions: [TextButton(onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('入力画面に戻る')),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('確認して共有送信'))],
        ); });
      _confirmationContext = null;
      if (!mounted) return;
      if (confirmed != true) { _back(); return; }
      await widget.workflow.send(widget.send);
      if (!mounted) return;
      setState(() {});
    } catch (_) {
      if (mounted) { setState(() {
        _retired = widget.workflow.state == SiteOrderSendState.retired;
        _error = _unknown
        ? '送信結果を確認できません。同じ送信の保存結果を照合してください。'
        : '共有送信を開始できませんでした。内容と送信先を確認して再度お試しください。';
      }); }
    } finally { if (mounted) setState(() => _busy = false); }
  }

  Future<void> _resolve() async {
    if (_busy || !_unknown) return;
    setState(() { _busy = true; _error = null; });
    try {
      await widget.workflow.resolve(widget.lookupReceipt);
      if (mounted) { setState(() => _error = _unknown
        ? 'まだ送信結果が確定していません。新しい送信は行わず、再度照合してください。' : null); }
    } catch (_) {
      if (mounted) { setState(() {
        _retired = widget.workflow.state == SiteOrderSendState.retired;
        _error = '送信結果の照合を完了できません。時間をおいて再度確認してください。';
      }); }
    } finally { if (mounted) setState(() => _busy = false); }
  }

  Future<void> _closePending() async {
    if (_busy || !_unknown) return;
    // The required durable intent remains available to the recovery adapter.
    // Retiring this presentation never deletes it or marks delivery successful.
    widget.workflow.retire();
    setState(() => _retired = true);
    await WidgetsBinding.instance.endOfFrame;
    if (mounted) Navigator.of(context).pop(false);
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: _retired || (!_busy && !_unknown),
    child: Scaffold(appBar: AppBar(title: const Text('協力会社に注文書を共有')),
      body: SafeArea(child: _retired
        ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('ログイン・会社・注文書の状態が変わりました。開き直してください。'),
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('閉じる')),
          ]))
        : ListView(padding: const EdgeInsets.all(16), children: [
        Text(widget.workflow.artifact.title, style: Theme.of(context).textTheme.titleLarge),
        Text(widget.workflow.artifact.period), const SizedBox(height: 16),
        DropdownButtonFormField<String>(initialValue: _selected,
          isExpanded: true, decoration: const InputDecoration(labelText: '登録している協力会社'),
          items: widget.recipients.map((r) => DropdownMenuItem(value: r.tradeCompanyId,
            child: Text(r.name))).toList(),
          onChanged: _busy || _unknown || _sent ? null : (v) => setState(() => _selected = v)),
        const SizedBox(height: 16),
        if (_error != null) Text(_error!, key: const Key('site-order-send-error')),
        if (_sent) ...[const Text('共有送信の保存を確認しました。'),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('閉じる'))]
        else if (_unknown) ...[
          FilledButton(onPressed: _busy ? null : _resolve,
            child: const Text('この送信の保存結果を確認')),
          TextButton(onPressed: _busy ? null : _closePending,
            child: const Text('閉じて後で確認')),
        ]
        else ...[
          FilledButton(onPressed: _busy || _selected == null ? null : _share,
            child: const Text('共有送信')),
          TextButton(onPressed: _busy ? null : _back, child: const Text('入力画面に戻る')),
        ],
      ])),
    ));
}
