import 'package:flutter/material.dart';
import 'site_order_workflow.dart';

/// Draft confirmed -> recipient selected -> canonical sealed artifact prepared
/// for that recipient -> explicit final confirmation -> durable delivery intent.
/// Preparing must use the same saved draft CAS/request on retries; a caller
/// upload or client seal flag cannot substitute for the server adapter.
class SiteOrderSendPage extends StatefulWidget {
  const SiteOrderSendPage({super.key, required this.draftScope,
    required this.draftRevision,required this.draftTitle,required this.draftPeriod,
    required this.requireDraftCurrent,required this.prepareWorkflow,
    required this.recipients, required this.send, required this.lookupReceipt,
    required this.scopeChanges});
  final SiteOrderScope draftScope;
  final String draftRevision,draftTitle,draftPeriod;
  final VoidCallback requireDraftCurrent;
  final Future<SiteOrderSendWorkflow> Function(SiteOrderRecipient) prepareWorkflow;
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
  late final SiteOrderScope _boundScope;
  late final String _boundRevision,_boundTitle,_boundPeriod;
  SiteOrderSendWorkflow? _workflow;
  BuildContext? _confirmationContext;
  bool get _unknown => _workflow?.state == SiteOrderSendState.outcomeUnknown;
  bool get _sent => _workflow?.state == SiteOrderSendState.sent;

  @override
  void initState() {
    super.initState();_boundScope=widget.draftScope;_boundRevision=widget.draftRevision;
    _boundTitle=widget.draftTitle;_boundPeriod=widget.draftPeriod;
    widget.scopeChanges.addListener(_checkScope);_checkScope();
  }
  void _requireCurrent() {
    if(_retired || !_boundScope.valid || _boundRevision.isEmpty ||
      !_boundScope.sameAs(widget.draftScope) || widget.draftRevision!=_boundRevision ||
      widget.draftTitle!=_boundTitle || widget.draftPeriod!=_boundPeriod) {
      throw StateError('下書きの対象が変わりました。');
    }
    widget.requireDraftCurrent();_workflow?.verify();
  }
  @override
  void didUpdateWidget(covariant SiteOrderSendPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if(oldWidget.scopeChanges!=widget.scopeChanges) {
      oldWidget.scopeChanges.removeListener(_checkScope);widget.scopeChanges.addListener(_checkScope);
    }
    _checkScope();
  }
  void _checkScope() {
    try { _requireCurrent(); } catch (_) {
      _workflow?.retire();
      if (mounted) setState(() => _retired = true);
      final dialog = _confirmationContext;
      final route=dialog!=null && dialog.mounted ? ModalRoute.of(dialog) : null;
      if (route != null && route.isActive) {
        route.navigator?.removeRoute(route);
      }
    }
  }
  @override
  void dispose() { widget.scopeChanges.removeListener(_checkScope); super.dispose(); }

  void _back() {
    try {
      _requireCurrent();_workflow?.returnToEditor();
      Navigator.of(context).pop(false);
    } catch (_) { setState(() {
      _retired = _retired || _workflow?.state == SiteOrderSendState.retired;
      _error = '送信状態を確認してから入力画面に戻ってください。';
    }); }
  }

  Future<void> _share() async {
    if (_busy || _unknown || _sent) return;
    setState(() { _busy = true; _error = null; });
    try {
      final recipient = widget.recipients.singleWhere((r) => r.tradeCompanyId == _selected);
      _requireCurrent();
      final workflow=_workflow??await widget.prepareWorkflow(recipient);
      if(!mounted) { workflow.retire();return; }
      _requireCurrent();
      final current=widget.recipients.where((r)=>r.tradeCompanyId==recipient.tradeCompanyId).toList();
      if(!workflow.scope.sameAs(_boundScope) || workflow.artifact.title!=_boundTitle ||
        workflow.artifact.period!=_boundPeriod || current.length!=1 ||
        current.single.fingerprint!=recipient.fingerprint) {
        workflow.retire();throw StateError('原本・送信先の対象が一致しません。');
      }
      try { workflow.select(recipient); }
      catch (_) { workflow.retire();rethrow; }
      _workflow=workflow;
      final intent = workflow.confirm();
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
      _requireCurrent();await workflow.send(widget.send);_requireCurrent();
      if (!mounted) return;
      setState(() {});
    } catch (_) {
      _checkScope();
      if (mounted) { setState(() {
        _retired = _retired || _workflow?.state == SiteOrderSendState.retired;
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
      _requireCurrent();await _workflow!.resolve(widget.lookupReceipt);_requireCurrent();
      if (mounted) { setState(() => _error = _unknown
        ? 'まだ送信結果が確定していません。新しい送信は行わず、再度照合してください。' : null); }
    } catch (_) {
      _checkScope();
      if (mounted) { setState(() {
        _retired = _retired || _workflow?.state == SiteOrderSendState.retired;
        _error = '送信結果の照合を完了できません。時間をおいて再度確認してください。';
      }); }
    } finally { if (mounted) setState(() => _busy = false); }
  }

  Future<void> _closePending() async {
    if (_busy || !_unknown) return;
    // The required durable intent remains available to the recovery adapter.
    // Retiring this presentation never deletes it or marks delivery successful.
    _workflow!.retire();
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
        Text(_boundTitle, style: Theme.of(context).textTheme.titleLarge),
        Text(_boundPeriod), const SizedBox(height: 16),
        DropdownButtonFormField<String>(initialValue: _selected,
          isExpanded: true, decoration: const InputDecoration(labelText: '登録している協力会社'),
          items: widget.recipients.map((r) => DropdownMenuItem(value: r.tradeCompanyId,
            child: Text(r.name))).toList(),
          onChanged: _busy || _unknown || _sent ? null : (v) => setState(() {
            if(_selected!=v) {_workflow?.retire();_workflow=null;}
            _selected = v;
          })),
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
