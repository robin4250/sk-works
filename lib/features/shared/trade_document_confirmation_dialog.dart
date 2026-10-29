import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import '../../international/language_controller.dart';
import 'trade_document_confirmation_approved_pdf.dart';
import 'trade_document_confirmation_controller.dart';
import 'trade_document_confirmation_model.dart';
import 'trade_document_confirmation_pending_store.dart';
import 'trade_document_confirmation_repository.dart';
import 'trade_document_output_page.dart';
import 'trade_document_form_session.dart';

enum TradeConfirmationFlowOutcome { legacy, confirmed, cancelled }

class TradeConfirmationAction extends StatefulWidget {
  const TradeConfirmationAction({super.key, required this.kind, required this.parentId,
    required this.sourceRevision, required this.label, this.inspectOnly = false});
  final String kind, parentId, sourceRevision, label;
  final bool inspectOnly;
  @override State<TradeConfirmationAction> createState() => _TradeConfirmationActionState();
}
class _TradeConfirmationActionState extends State<TradeConfirmationAction> {
  late final SupabaseTradeConfirmationRepository? _repository;
  late final Future<bool> _available;
  bool _opening = false;
  @override void initState() {
    super.initState(); _repository = SupabaseTradeConfirmationRepository.maybeCreate();
    _available = _repository?.available() ?? Future.value(false);
  }
  Future<void> _open() async {
    if (_opening) return;
    setState(() => _opening = true);
    try {
      await openTradeDocumentConfirmation(context, kind: widget.kind, parentId: widget.parentId,
        sourceRevision: widget.sourceRevision, inspectOnly: widget.inspectOnly);
    } finally { if (mounted) setState(() => _opening = false); }
  }
  @override void dispose() { _repository?.dispose(); super.dispose(); }
  @override Widget build(BuildContext context) {
    SkoLanguageController.watch(context);
    return FutureBuilder<bool>(future: _available, builder: (context, snapshot) => snapshot.data == true
      ? TextButton(onPressed: _opening ? null : _open, child: Text(SkoLanguageController.tr(widget.label)))
      : const SizedBox.shrink());
  }
}

Future<TradeConfirmationFlowOutcome> openTradeDocumentConfirmation(BuildContext context, {
  required String kind, required String parentId, required String sourceRevision,
  bool inspectOnly = false,
}) async {
  final repository = SupabaseTradeConfirmationRepository.maybeCreate();
  if (repository == null) return TradeConfirmationFlowOutcome.cancelled;
  try {
    return await Navigator.of(context).push<TradeConfirmationFlowOutcome>(MaterialPageRoute(builder: (_) =>
      TradeDocumentConfirmationPage(kind: kind, parentId: parentId, sourceRevision: sourceRevision,
        repository: repository, inspectOnly: inspectOnly))) ?? TradeConfirmationFlowOutcome.cancelled;
  } finally { await repository.dispose(); }
}

/// One issued-page operation. A recipient uses the separate received page and
/// never sees these two approval checkboxes or the unapproved issuer asset.
class TradeDocumentConfirmationPage extends StatefulWidget {
  const TradeDocumentConfirmationPage({super.key, required this.kind, required this.parentId,
    required this.sourceRevision, required this.repository, this.pendingStore, this.inspectOnly = false});
  final String kind, parentId, sourceRevision;
  final TradeConfirmationRepository repository;
  final TradeConfirmationPendingStore? pendingStore;
  final bool inspectOnly;
  @override State<TradeDocumentConfirmationPage> createState() => _TradeDocumentConfirmationPageState();
}

class _TradeDocumentConfirmationPageState extends State<TradeDocumentConfirmationPage> with WidgetsBindingObserver {
  late final TradeConfirmationController _controller;
  late final String? _actor, _token;
  StreamSubscription<String?>? _subscription;
  bool _busy = false, _revoked = false, _active = true, _reload = false;
  bool _content = false, _seal = false, _approved = false;
  bool _printing = false;
  Map<String, dynamic>? _archiveScope;
  bool _archived = false;
  AppLifecycleState _visibility = AppLifecycleState.resumed;
  int _generation = 0;
  String? _error;
  TradeConfirmationPreview? _preview;
  Uint8List? _bytes;
  Map<String,dynamic>? _outputPayload;
  final _outputChanges=ValueNotifier<int>(0);
  TradeDocumentFormSession? _outputScope;
  Map<String,dynamic>? _outputDescriptor;
  String tr(String text) => SkoLanguageController.tr(text);
  bool _current(int generation) => mounted && _active && !_revoked && generation == _generation &&
    widget.repository.actorId == _actor && widget.repository.sessionKey == _token;
  @override void initState() {
    super.initState(); _actor = widget.repository.actorId; _token = widget.repository.sessionKey;
    final repository=widget.repository;if(repository is SupabaseTradeConfirmationRepository)repository.outputAdmissionChanges.addListener(_admissionChanged);
    _controller = TradeConfirmationController(repository: widget.repository, kind: widget.kind,
      parentId: widget.parentId, store: widget.pendingStore ??
        FileTradeConfirmationPendingStore(currentActor: () => widget.repository.actorId));
    _subscription = widget.repository.sessionChanges.listen((token) {
      if (token != _token || widget.repository.actorId != _actor) _revoke();
    }, onError: (Object _) => _revoke());
    WidgetsBinding.instance.addObserver(this);
    _visibility = WidgetsBinding.instance.lifecycleState ?? AppLifecycleState.resumed;
    _active = _visibility == AppLifecycleState.resumed;
    if (_active) unawaited(_load());
  }
  @override void didUpdateWidget(covariant TradeDocumentConfirmationPage old){super.didUpdateWidget(old);if(old.kind!=widget.kind||old.parentId!=widget.parentId||old.sourceRevision!=widget.sourceRevision||!identical(old.repository,widget.repository)){final repository=old.repository;if(repository is SupabaseTradeConfirmationRepository)repository.outputAdmissionChanges.removeListener(_admissionChanged);_revoke();}}
  void _admissionChanged(){final repository=widget.repository;if(repository is SupabaseTradeConfirmationRepository){try{repository.requireOutputAdmission();}catch(_){_revoke();}}}
  Future<void> _bindOutput(Map<String,dynamic> evidence,Map<String,dynamic> descriptor,{bool archive=false})async {
    if(!mounted||_revoked||_visibility!=AppLifecycleState.resumed)throw StateError('書類を開き直してください。');
    final repository=widget.repository;
    _outputScope?.dispose();_outputScope=null;
    final captured=Map<String,dynamic>.unmodifiable(descriptor);_outputDescriptor=captured;
    if(repository is! SupabaseTradeConfirmationRepository)return; // Existing injected repository tests do not establish an Auth lease.
    final session=await repository.createConfirmedOutputScope(captured,evidence:evidence,currentScope:()=>mounted&&!_revoked&&(_visibility==AppLifecycleState.resumed||(_printing&&_visibility==AppLifecycleState.inactive))?_outputDescriptor:null,archive:archive);
    if(!mounted||_revoked||!identical(captured,_outputDescriptor)){session.dispose();throw StateError('書類を開き直してください。');}
    _outputScope=session;
  }
  void _requireOutput(){final repository=widget.repository;
    if(repository is SupabaseTradeConfirmationRepository){repository.requireOutputAdmission();if(_outputScope==null)throw StateError('書類を開き直してください。');_outputScope!.requireScope();}
  }
  void _revoke() {
    if (!mounted || _revoked) return;
    _outputDescriptor=null;_generation++;
    setState(() { _revoked = true; _bytes = null; _preview = null;
      _error = 'ログイン情報が変わりました。書類を開き直してください。'; });
    _outputChanges.value++;
  }
  @override void didChangeAppLifecycleState(AppLifecycleState state) {
    _visibility = state;
    _active = state == AppLifecycleState.resumed;
    if (state == AppLifecycleState.inactive && _printing && _approved) return;
    if (!_active) {
      _revoke();
    } else if (!_revoked) {
      if (_busy) { _reload = true; }
      else { unawaited(_load()); }
    }
  }
  void _finish() {
    if (!mounted) return;
    setState(() => _busy = false);
    if (_reload && _active && !_revoked) { _reload = false; unawaited(_load()); }
  }
  Future<void> _load() async {
    if (_busy || !_active || _revoked) return;
    final generation = ++_generation;
    setState(() { _busy = true; _bytes = null; _preview = null;
      _approved = false; _archived = false; _archiveScope = null; _content = false; _seal = false; _error = null; });
    try {
      await _controller.load();
      if (!mounted || !_current(generation)) return;
      final available = await widget.repository.available();
      if (!mounted || !_current(generation)) return;
      if (!available) {
        if (widget.inspectOnly || _controller.pending != null) {
          setState(() => _error = '書類の角印確認機能はまだ利用できません。');
        } else { Navigator.of(context).pop(TradeConfirmationFlowOutcome.legacy); }
        return;
      }
      // A result lost on a prior attempt must be read using its original
      // descriptor before any workspace can propose another document revision.
      if (_controller.pending != null) return;
      if (widget.inspectOnly) {
        final saved = await widget.repository.resolve(widget.kind, widget.parentId);
        if (!mounted || !_current(generation)) return;
        if (saved['can_render_current'] != true) {
          setState(() {
            if (saved['can_render_archive'] == true) {
              _archiveScope = tradeConfirmationRenderScope(saved);
            }
            _error = saved['can_render_archive'] == true
              ? '書類の内容が変わっています。過去の承認済み書類を開くことができます。'
              : 'この書類の角印使用はまだ承認されていません。';
          });
          return;
        }
        final scope = tradeConfirmationRenderScope(saved);
        final evidence = await widget.repository.render(scope);
        if (!mounted || !_current(generation)) return;
        final bytes = await TradeConfirmationPdf.approved(evidence, scope, _actor!);
        if (!mounted || !_current(generation)) return;
        await _bindOutput(evidence,scope);if(!mounted||!_current(generation))return;
        setState(() { _bytes = bytes; _outputPayload=TradeConfirmationPdf.approvedAttachment(evidence,scope,_actor).payload; _approved = true; }); return;
      }
      final workspace = await widget.repository.workspace(widget.kind, widget.parentId, widget.sourceRevision);
      if (!mounted || !_current(generation)) return;
      if (!workspace.integrationRequired && !widget.inspectOnly) {
        Navigator.of(context).pop(TradeConfirmationFlowOutcome.legacy); return;
      }
      if (!workspace.canConfirm) {
        final scope = workspace.value['can_render'] == true ? tradeConfirmationRenderScope(workspace.value) : workspace.scope;
        if (workspace.value['can_render'] == true && tradeConfirmationUuid(scope['p_local_document_id']) &&
            scope['p_document_revision'] is int) {
          final evidence = await widget.repository.render(scope);
          if (!mounted || !_current(generation)) return;
          final bytes = await TradeConfirmationPdf.approved(evidence, scope, _actor!);
          if (!mounted || !_current(generation)) return;
          await _bindOutput(evidence,scope);if(!mounted||!_current(generation))return;
        setState(() { _bytes = bytes; _outputPayload=TradeConfirmationPdf.approvedAttachment(evidence,scope,_actor).payload; _approved = true; });
        } else { setState(() => _error = _reason(workspace.unavailableReason)); }
        return;
      }
      final preview = await widget.repository.preview(workspace);
      if (!mounted || !_current(generation)) return;
      final bytes = await TradeConfirmationPdf.ownPreview(preview);
      if (!mounted || !_current(generation)) return;
      setState(() { _preview = preview; _bytes = bytes; });
    } catch (_) {
      if (_current(generation)) setState(() => _error = '書類の確認状態を取得できません。再読み込みしてください。');
    } finally { _finish(); }
  }
  String _reason(String? code) => switch (code) {
    'attachment_missing' => '先に注文書・注文請書の内容を保存してください。',
    'other_approvals_pending' || 'prior_confirmations_pending' => '他の担当者の確認が終わってから、もう一度開いてください。',
    'seal_permission_required' => '自社の角印を使用できる管理者の確認が必要です。',
    _ => '書類・会社連携・承認権限を確認して、もう一度開いてください。',
  };
  Future<void> _confirm() async {
    final preview = _preview, generation = _generation;
    if (_busy || !_current(generation) || !_content || !_seal || preview == null || _bytes == null) return;
    setState(() => _busy = true);
    try {
      await _controller.confirm(preview.expected);
      if (!mounted || !_current(generation)) return;
      Navigator.of(context).pop(TradeConfirmationFlowOutcome.confirmed);
    } catch (_) {
      if (_current(generation)) {
        setState(() { _error = _controller.pending != null
          ? '確認結果が不明です。「結果を確認」で同じ申請の結果を確認してください。'
          : '確認を保存できませんでした。書類を再読み込みしてください。'; _content = false; _seal = false; });
      }
    } finally { _finish(); }
  }
  Future<void> _lookup() async {
    final generation = _generation;
    if (_busy || !_current(generation) || _controller.pending == null) return;
    setState(() => _busy = true);
    try {
      final result = await _controller.lookup();
      if (!mounted || !_current(generation)) return;
      if (result != null) { Navigator.of(context).pop(TradeConfirmationFlowOutcome.confirmed); }
      else { setState(() => _error = 'まだ結果を確認できません。同じ申請を保持しています。'); }
    } catch (_) {
      if (_current(generation)) setState(() => _error = '結果を確認できません。同じ申請を保持しています。');
    } finally { _finish(); }
  }
  Future<void> _archive() async {
    final scope = _archiveScope, generation = _generation;
    if (_busy || !_current(generation) || scope == null) return;
    setState(() => _busy = true);
    try {
      final raw = await widget.repository.render(scope, archive: true);
      if (!mounted || !_current(generation)) return;
      final bytes = await TradeConfirmationPdf.approved(raw, scope, _actor!, archive: true);
      if (!mounted || !_current(generation)) return;
      await _bindOutput(raw,scope,archive:true);if(!mounted||!_current(generation))return;
      setState(() { _bytes = bytes;_outputPayload=TradeConfirmationPdf.approvedAttachment(raw,scope,_actor,archive:true).payload; _approved = true; _archived = true; _error = null; });
    } catch (_) {
      if (_current(generation)) setState(() => _error = '過去の承認済み書類を取得できません。');
    } finally { _finish(); }
  }
  void _verifyPrint(Uint8List bytes) {
    _requireOutput();
    if (!mounted || _revoked || !_approved || !identical(bytes, _bytes) ||
        widget.repository.actorId != _actor || widget.repository.sessionKey != _token ||
        !const {AppLifecycleState.resumed, AppLifecycleState.inactive}.contains(_visibility)) {
      throw StateError('印刷状態が変わりました。書類を開き直してください。');
    }
  }
  Future<void> _print({bool share = false}) async {
    final bytes = _bytes;
    if (_busy || !_active || !_approved || bytes == null || _revoked) return;
    setState(() { _busy = true; _printing = true; });
    try {
      _verifyPrint(bytes);
      final name = widget.kind == 'invoice' ? '注文請書.pdf' : '注文書.pdf';
      if (share) { await Printing.sharePdf(bytes: bytes, filename: name); }
      else { await Printing.layoutPdf(name: name, onLayout: (_) async { _verifyPrint(bytes); return bytes; }); }
      _verifyPrint(bytes);
    } catch (_) {
      if (mounted && !_revoked) setState(() => _error = '印刷・共有を完了できません。書類を再読み込みしてください。');
    } finally { _printing = false;if(_visibility!=AppLifecycleState.resumed)_revoke(); _finish(); }
  }
  @override void dispose() { final repository=widget.repository;if(repository is SupabaseTradeConfirmationRepository)repository.outputAdmissionChanges.removeListener(_admissionChanged);_outputDescriptor=null;_outputScope?.dispose();_revoked=true;_outputChanges.value++;_outputChanges.dispose();_generation++; WidgetsBinding.instance.removeObserver(this); _subscription?.cancel(); super.dispose(); }
  Future<void> _formats()async {
    final bytes=_bytes,payload=_outputPayload;
    if(_busy||!_active||!_approved||bytes==null||payload==null||_revoked)return;
    final changes=Listenable.merge([_outputChanges,if(_outputScope!=null)_outputScope!]);
    setState(()=>_busy=true);
    try{_verifyPrint(bytes);await Navigator.of(context).push<void>(MaterialPageRoute(builder:(_)=>TradeDocumentOutputPage(payload:payload,canonicalBytes:bytes,onNativeOutputChanged:(active){_printing=active;if(!active&&_visibility!=AppLifecycleState.resumed)_revoke();},scopeChanges:changes,requireScope:()=>_verifyPrint(bytes))));}
    catch(_){if(mounted&&!_revoked)setState(()=>_error='書類を開き直してください。');}
    finally{_printing=false;_finish();}
  }
  @override Widget build(BuildContext context) {
    SkoLanguageController.watch(context);
    final enabled = !_busy && _active && !_revoked;
    return Scaffold(appBar: AppBar(title: Text(tr(widget.kind == 'invoice' ? '注文請書の確認' : '注文書の確認'))),
      body: Column(children: [
        if (_busy) const LinearProgressIndicator(),
        if (_archived) Padding(padding: const EdgeInsets.all(12), child: Text(tr('過去の承認済み書類です。現在の内容とは異なる場合があります。'))),
        if (_error != null) Padding(padding: const EdgeInsets.all(12), child: Text(tr(_error!))),
        if (_controller.pending != null) Padding(padding: const EdgeInsets.all(12), child: Column(children: [
          Text(tr('前の確認申請を保持しています。新しい申請は送信しません。')),
          TextButton(onPressed: enabled ? _lookup : null, child: Text(tr('結果を確認'))),
        ])),
        if (_bytes != null) Expanded(child: PdfPreview(build: (_) async => _bytes ?? (throw StateError('書類を再読み込みしてください。')),
          canChangePageFormat: false, canChangeOrientation: false, allowPrinting: false,
          allowSharing: false, pdfFileName: widget.kind == 'invoice' ? '注文請書.pdf' : '注文書.pdf'))
        else const Spacer(),
        if(_approved&&_outputPayload!=null)TextButton(onPressed:enabled?_formats:null,child:Text(tr('形式を選んで保存・印刷'))),
        if (_approved) SafeArea(top: false, child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          OutlinedButton(onPressed: enabled ? () => _print() : null, child: Text(tr('印刷'))),
          TextButton(onPressed: enabled ? () => _print(share: true) : null, child: Text(tr('共有'))),
        ])),
        if (_archiveScope != null && !_archived) TextButton(onPressed: enabled ? _archive : null,
          child: Text(tr('過去の承認済み書類を開く'))),
        if (_preview != null && _controller.pending == null) SafeArea(top: false, child: Column(children: [
          ExpansionTile(title: Text(tr('確認する内容')), children: [Padding(padding: const EdgeInsets.all(12), child: Text(tr(
            widget.kind == 'invoice' ? '請求書の最終承認と注文請書への自社角印の使用を、一度の操作で記録します。'
              : '支払証明書・注文書の内容確認と自社角印の使用を記録します。支払確定は行いません。')))]),
          CheckboxListTile(value: _content, onChanged: enabled ? (value) => setState(() => _content = value == true) : null,
            title: Text(tr(widget.kind == 'invoice' ? '請求書の最終承認と注文請書の内容を確認しました' : '支払証明書と注文書の内容を確認しました'))),
          CheckboxListTile(value: _seal, onChanged: enabled ? (value) => setState(() => _seal = value == true) : null,
            title: Text(tr('会社に登録した自社の角印の使用を承認します'))),
          FilledButton(onPressed: enabled && _content && _seal ? _confirm : null, child: Text(tr('確認して承認'))),
        ])),
        if (_error != null && _controller.pending == null) TextButton(onPressed: enabled ? _load : null,
          child: Text(tr('再読み込み'))),
      ]));
  }
}

Future<void> openReceivedTradeDocuments(BuildContext context, String tradeCompanyId, String companyName) async {
  final repository = SupabaseTradeConfirmationRepository.maybeCreate();
  if (repository == null) return;
  try {
    await Navigator.of(context).push<void>(MaterialPageRoute(builder: (_) =>
      ReceivedTradeDocumentsPage(tradeCompanyId: tradeCompanyId, companyName: companyName, repository: repository)));
  } finally { await repository.dispose(); }
}

class ReceivedTradeDocumentsPage extends StatefulWidget {
  const ReceivedTradeDocumentsPage({super.key, required this.tradeCompanyId, required this.companyName, required this.repository});
  final String tradeCompanyId, companyName;
  final TradeConfirmationRepository repository;
  @override State<ReceivedTradeDocumentsPage> createState() => _ReceivedTradeDocumentsPageState();
}
class _ReceivedTradeDocumentsPageState extends State<ReceivedTradeDocumentsPage> {
  List<Map<String, dynamic>> _items = const [];
  bool _busy = false, _revoked = false;
  String? _error;
  late final String? _actor, _token;
  StreamSubscription<String?>? _subscription;
  String tr(String value) => SkoLanguageController.tr(value);
  bool get _same => mounted && !_revoked && widget.repository.actorId == _actor && widget.repository.sessionKey == _token;
  @override void initState() {
    super.initState(); _actor = widget.repository.actorId; _token = widget.repository.sessionKey;
    final repository=widget.repository;if(repository is SupabaseTradeConfirmationRepository)repository.outputAdmissionChanges.addListener(_admissionChanged);
    _subscription = widget.repository.sessionChanges.listen((token) {
      if (token != _token || widget.repository.actorId != _actor) {
        if (mounted) setState(() { _revoked = true; _items = const []; _error = 'ログイン情報が変わりました。書類を開き直してください。'; });
      }
    }, onError: (Object _) { if (mounted) setState(() { _revoked = true; _items = const []; }); });
    unawaited(_load());
  }
  void _admissionChanged(){final repository=widget.repository;
    if(repository is! SupabaseTradeConfirmationRepository)return;
    try{repository.requireOutputAdmission();}catch(_){_retireList();}
  }
  void _retireList(){if(!mounted||_revoked)return;setState((){_revoked=true;_busy=false;_items=const [];_error='ログイン情報が変わりました。書類を開き直してください。';});}
  @override void didUpdateWidget(covariant ReceivedTradeDocumentsPage old){super.didUpdateWidget(old);
    if(old.tradeCompanyId!=widget.tradeCompanyId||!identical(old.repository,widget.repository)){
      final repository=old.repository;if(repository is SupabaseTradeConfirmationRepository)repository.outputAdmissionChanges.removeListener(_admissionChanged);_retireList();
    }
  }
  Future<void> _load() async {
    if (_busy || !_same) return;
    setState(() { _busy = true; _error = null; _items = const []; });
    try {
      if (!await widget.repository.available()) {
        if (_same) setState(() => _error = '書類の角印確認機能はまだ利用できません。'); return;
      }
      final raw = await widget.repository.received(widget.tradeCompanyId);
      if (!_same) return;
      if ((raw['items'] as List).length > 200) throw const FormatException('受領した書類が多すぎます');
      final items = <Map<String, dynamic>>[], identities = <String>{};
      for (final entry in raw['items'] as List) {
        if (entry is! Map || !tradeConfirmationUuid(entry['document_id']) ||
            entry['document_revision'] is! int || (entry['document_revision'] as int) <= 0 ||
            !const {'invoice', 'payment_certificate'}.contains(entry['kind']) ||
            !tradeConfirmationUuid(entry['issuer_company_id']) || entry['issuer_name'] is! String ||
            entry['month'] is! String || !RegExp(r'^\d{4}-(0[1-9]|1[0-2])$').hasMatch(entry['month'] as String) ||
            entry['body_hash'] is! String || !RegExp(r'^[0-9a-f]{64}$').hasMatch(entry['body_hash'] as String) ||
            entry['is_current'] is! bool ||
            !identities.add('${entry['document_id']}/${entry['document_revision']}')) {
          throw const FormatException('受領した書類の一覧が一致しません');
        }
        items.add(Map<String, dynamic>.from(entry));
      }
      setState(() => _items = items);
    } catch (_) { if (_same) setState(() => _error = '受領した書類を取得できません。再読み込みしてください。'); }
    finally { if (mounted) setState(() => _busy = false); }
  }
  Future<void> _open(Map<String, dynamic> item) async {
    if (_busy || !_same) return;
    setState(() => _busy = true);
    try {
      final own = await widget.repository.receive(widget.tradeCompanyId, item['document_id'] as String, item['document_revision'] as int);
      if (!mounted || !_same) return;
      final scope = tradeConfirmationRenderScope(own);
      final archive = own['can_render_current'] != true;
      if (archive) {
        final accepted = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
          title: Text(tr('過去の承認済み書類を開く')),
          content: Text(tr('現在の書類内容とは異なる承認時点の書類です。')),
          actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: Text(tr('戻る'))),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(tr('開く')))]));
        if (!mounted || !_same || accepted != true) return;
      }
      await Navigator.of(context).push<void>(MaterialPageRoute(builder: (_) =>
        TradeApprovedDocumentPage(repository: widget.repository, scope: scope, archive: archive)));
    } catch (_) { if (_same) setState(() => _error = '受領した書類を開けません。承認状態を再確認してください。'); }
    finally { if (mounted) setState(() => _busy = false); }
  }
  @override void dispose() {final repository=widget.repository;if(repository is SupabaseTradeConfirmationRepository)repository.outputAdmissionChanges.removeListener(_admissionChanged);_revoked=true;_subscription?.cancel();super.dispose();}
  @override Widget build(BuildContext context) {
    SkoLanguageController.watch(context);
    return Scaffold(appBar: AppBar(title: Text(tr('受領した承認済み書類'))), body: Column(children: [
      Padding(padding: const EdgeInsets.all(12), child: Text(widget.companyName)),
      if (_busy) const LinearProgressIndicator(),
      if (_error != null) Padding(padding: const EdgeInsets.all(12), child: Text(tr(_error!))),
      if (!_busy && _error == null && _items.isEmpty) Padding(padding: const EdgeInsets.all(12), child: Text(tr('受領した承認済み書類はありません。'))),
      Expanded(child: ListView(children: [for (final item in _items) ListTile(
        title: Text(tr(item['kind'] == 'invoice' ? '注文請書' : '注文書')),
        subtitle: Text('${item['month']} / ${SkoLanguageController.trParams('第{revision}版', {'revision': item['document_revision']})}'
          '${item['is_current'] == false ? ' / ${tr('過去の承認済み書類')}' : ''}'),
        trailing: const Icon(Icons.chevron_right), onTap: _busy || _revoked ? null : () => _open(item))])),
      TextButton(onPressed: _busy || _revoked ? null : _load, child: Text(tr('再読み込み'))),
    ]));
  }
}

/// Received or issued immutable evidence. This page has no confirmation API.
class TradeApprovedDocumentPage extends StatefulWidget {
  TradeApprovedDocumentPage({super.key, required this.repository, required Map<String, dynamic> scope, this.archive = false})
    : scope = Map<String, dynamic>.unmodifiable(Map<String, dynamic>.from(scope));
  final TradeConfirmationRepository repository;
  final Map<String, dynamic> scope;
  final bool archive;
  @override State<TradeApprovedDocumentPage> createState() => _TradeApprovedDocumentPageState();
}
class _TradeApprovedDocumentPageState extends State<TradeApprovedDocumentPage> with WidgetsBindingObserver {
  Uint8List? _bytes;
  Map<String,dynamic>? _outputPayload;
  final _outputChanges=ValueNotifier<int>(0);
  TradeDocumentFormSession? _outputScope;
  Map<String,dynamic>? _outputDescriptor;
  late final String? _actor, _token;
  StreamSubscription<String?>? _subscription;
  bool _busy = false, _revoked = false, _printing = false;
  AppLifecycleState _visibility = AppLifecycleState.resumed;
  String? _error;
  String tr(String value) => SkoLanguageController.tr(value);
  void _verify() {
    if (!mounted || _revoked || widget.repository.actorId != _actor || widget.repository.sessionKey != _token ||
        !const {AppLifecycleState.resumed, AppLifecycleState.inactive}.contains(_visibility)) {
      throw StateError('書類の閲覧状態が変わりました。開き直してください。');
    }
  }
  @override void initState() {
    super.initState(); _actor = widget.repository.actorId; _token = widget.repository.sessionKey;
    final repository=widget.repository;if(repository is SupabaseTradeConfirmationRepository)repository.outputAdmissionChanges.addListener(_admissionChanged);
    _subscription = widget.repository.sessionChanges.listen((token) {
      if (token != _token || widget.repository.actorId != _actor) _revoke();
    }, onError: (Object _) => _revoke());
    WidgetsBinding.instance.addObserver(this); unawaited(_load());
  }
  @override void didUpdateWidget(covariant TradeApprovedDocumentPage old){super.didUpdateWidget(old);if(old.archive!=widget.archive||!identical(old.repository,widget.repository)||old.scope.toString()!=widget.scope.toString()){final repository=old.repository;if(repository is SupabaseTradeConfirmationRepository)repository.outputAdmissionChanges.removeListener(_admissionChanged);_revoke();}}
  void _admissionChanged(){final repository=widget.repository;if(repository is SupabaseTradeConfirmationRepository){try{repository.requireOutputAdmission();}catch(_){_revoke();}}}
  Future<void> _bindOutput(Map<String,dynamic> evidence,Map<String,dynamic> descriptor,{bool archive=false})async {
    if(!mounted||_revoked||_visibility!=AppLifecycleState.resumed)throw StateError('書類を開き直してください。');
    final repository=widget.repository;
    _outputScope?.dispose();_outputScope=null;
    final captured=Map<String,dynamic>.unmodifiable(descriptor);_outputDescriptor=captured;
    if(repository is! SupabaseTradeConfirmationRepository)return; // Existing injected repository tests do not establish an Auth lease.
    final session=await repository.createConfirmedOutputScope(captured,evidence:evidence,currentScope:()=>mounted&&!_revoked&&(_visibility==AppLifecycleState.resumed||(_printing&&_visibility==AppLifecycleState.inactive))?widget.scope:null,archive:archive);
    if(!mounted||_revoked||!identical(captured,_outputDescriptor)){session.dispose();throw StateError('書類を開き直してください。');}
    _outputScope=session;
  }
  void _requireOutput(){final repository=widget.repository;
    if(repository is SupabaseTradeConfirmationRepository){repository.requireOutputAdmission();if(_outputScope==null)throw StateError('書類を開き直してください。');_outputScope!.requireScope();}
  }
  void _revoke() {
    if(!mounted||_revoked)return;_outputDescriptor=null;
    setState(() { _revoked = true; _bytes = null; _error = '書類の閲覧状態が変わりました。開き直してください。'; });
    _outputChanges.value++;
  }
  @override void didChangeAppLifecycleState(AppLifecycleState state) {
    _visibility = state;
    if (state != AppLifecycleState.resumed && !(state == AppLifecycleState.inactive && _printing)) _revoke();
  }
  Future<void> _load() async {
    if (_busy || _revoked) return;
    setState(() { _busy = true; _bytes = null; _error = null; });
    try {
      _verify(); final raw = await widget.repository.render(widget.scope, archive: widget.archive); _verify();
      final bytes = await TradeConfirmationPdf.approved(raw, widget.scope, _actor!, archive: widget.archive); _verify();
      await _bindOutput(raw,widget.scope,archive:widget.archive);_verify();
      setState(() {_bytes = bytes;_outputPayload=TradeConfirmationPdf.approvedAttachment(raw,widget.scope,_actor,archive:widget.archive).payload;});
    } catch (_) {
      if (mounted && !_revoked) setState(() => _error = '承認済み書類を取得できません。現在の承認状態を確認してください。');
    } finally { if (mounted) setState(() => _busy = false); }
  }
  Future<void> _print({bool share = false}) async {
    final bytes = _bytes;
    if (_busy || bytes == null || _revoked || _visibility != AppLifecycleState.resumed) return;
    setState(() { _busy = true; _printing = true; });
    try {
      _verify();_requireOutput(); final name = widget.scope['p_kind'] == 'invoice' ? '注文請書.pdf' : '注文書.pdf';
      if (share) { await Printing.sharePdf(bytes: bytes, filename: name); }
      else { await Printing.layoutPdf(name: name, onLayout: (_) async {
        _verify();_requireOutput(); if (!identical(bytes, _bytes)) throw StateError('書類が更新されています'); return bytes;
      }); }
      _verify();_requireOutput();
    } catch (_) { if (mounted && !_revoked) setState(() => _error = '印刷・共有を完了できません。書類を再読み込みしてください。'); }
    finally { _printing = false;if(_visibility!=AppLifecycleState.resumed)_revoke(); if (mounted) setState(() => _busy = false); }
  }
  Future<void> _formats()async{
    final bytes=_bytes,payload=_outputPayload;if(_busy||_revoked||bytes==null||payload==null||_visibility!=AppLifecycleState.resumed)return;
    final changes=Listenable.merge([_outputChanges,if(_outputScope!=null)_outputScope!]);
    setState(()=>_busy=true);
    try{_verify();_requireOutput();await Navigator.of(context).push<void>(MaterialPageRoute(builder:(_)=>TradeDocumentOutputPage(payload:payload,canonicalBytes:bytes,onNativeOutputChanged:(active){_printing=active;if(!active&&_visibility!=AppLifecycleState.resumed)_revoke();},scopeChanges:changes,requireScope:(){_verify();_requireOutput();if(!identical(bytes,_bytes))throw StateError('書類を開き直してください。');})));}
    catch(_){if(mounted&&!_revoked)setState(()=>_error='書類を開き直してください。');}
    finally{_printing=false;if(mounted)setState(()=>_busy=false);}
  }
  @override void dispose() { final repository=widget.repository;if(repository is SupabaseTradeConfirmationRepository)repository.outputAdmissionChanges.removeListener(_admissionChanged);_outputDescriptor=null;_outputScope?.dispose();_revoked=true;_outputChanges.value++;_outputChanges.dispose();_subscription?.cancel(); WidgetsBinding.instance.removeObserver(this); super.dispose(); }
  @override Widget build(BuildContext context) {
    SkoLanguageController.watch(context);
    final enabled = !_busy && !_revoked && _visibility == AppLifecycleState.resumed;
    return Scaffold(appBar: AppBar(title: Text(tr('承認済み書類'))), body: Column(children: [
      if (widget.archive) Padding(padding: const EdgeInsets.all(12), child: Text(tr('過去の承認済み書類です。現在の内容とは異なる場合があります。'))),
      if (_busy) const LinearProgressIndicator(),
      if (_error != null) Padding(padding: const EdgeInsets.all(12), child: Text(tr(_error!))),
      if (_bytes != null) Expanded(child: PdfPreview(build: (_) async => _bytes ?? (throw StateError('書類を開き直してください。')),
        canChangePageFormat: false, canChangeOrientation: false, allowPrinting: false, allowSharing: false))
      else const Spacer(),
      if(_outputPayload!=null)TextButton(onPressed:enabled?_formats:null,child:Text(tr('形式を選んで保存・印刷'))),
      SafeArea(top: false, child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        OutlinedButton(onPressed: enabled && _bytes != null ? () => _print() : null, child: Text(tr('印刷'))),
        TextButton(onPressed: enabled && _bytes != null ? () => _print(share: true) : null, child: Text(tr('共有'))),
        if (_error != null) TextButton(onPressed: enabled ? _load : null, child: Text(tr('再読み込み'))),
      ])),
    ]));
  }
}
