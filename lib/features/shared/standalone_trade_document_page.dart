import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:printing/printing.dart';

import '../../data/supabase_backend.dart';
import '../../domain/trade_document_form_draft.dart';
import '../../domain/trade_document_terms_snapshot.dart';
import 'trade_document_form_session.dart';
import 'trade_document_form_renderer.dart';
import 'trade_document_output_layout.dart';
import 'trade_document_output_selector.dart';
import 'trade_document_touch_editor_page.dart';
import 'standalone_trade_document_operation_gate.dart';
import 'standalone_trade_document.dart';
import 'standalone_trade_document_repository.dart';
import 'standalone_trade_document_print_scope.dart';

/// Registration-context, standalone PDF. No contract or financial save occurs.
class StandaloneTradeDocumentPage extends StatefulWidget {
  const StandaloneTradeDocumentPage({
    super.key,
    required this.tradeCompanyId,
    required this.acceptance,
    this.clientOverride,this.sessionOverride,this.repositoryOverride,this.operationGate,
  });
  final String tradeCompanyId;
  final bool acceptance;
  final SupabaseClient? clientOverride;
  final TradeDocumentFormSession? sessionOverride;
  final StandaloneTradeDocumentRepository? repositoryOverride;
  final StandaloneTradeDocumentOperationGate? operationGate;

  @override
  State<StandaloneTradeDocumentPage> createState() => _StandaloneState();
}

class _StandaloneState extends State<StandaloneTradeDocumentPage>
    with WidgetsBindingObserver {
  StandaloneTradeDocumentRepository? _repository;
  TradeDocumentFormSession? _session;
  TradeDocumentFormDraft? _draft;
  final _controllers = <String, TextEditingController>{};
  StreamSubscription<dynamic>? _auth;
  late final StandaloneTradeDocumentPrintScope _printScope;
  late final StandaloneTradeDocumentOperationGate? _operationGate;
  late final Listenable _operationChanges;
  final ValueNotifier<int> _retirementChanges=ValueNotifier<int>(0);
  Map<String, dynamic>? _context;
  Uint8List? _bytes,_canonicalBytes;
  Map<String,dynamic>? _renderedPayload;
  TradeDocumentOutputLayout _layout=TradeDocumentOutputLayout.a4TwoPages;
  String? _error;
  bool _loading = true, _busy = false, _revoked = false;
  int _generation = 0;
  String get _title => widget.acceptance ? '注文請書を作成' : '注文書を作成';

  @override
  void initState() {
    super.initState();
    final client=widget.clientOverride??(SupabaseBackend.isInitialized?SupabaseBackend.client:null);
    if(client!=null){
      _session=widget.sessionOverride??TradeDocumentFormSession(client,target:'${widget.tradeCompanyId}:${widget.acceptance}',currentTarget:()=>'${widget.tradeCompanyId}:${widget.acceptance}');
      if(!_session!.belongsTo(client))throw ArgumentError('Foreign contract session');
      _repository=widget.repositoryOverride??StandaloneTradeDocumentRepository(client,session:_session,managedCompanyId:widget.operationGate?.companyId);
      if(!_repository!.isBoundTo(_session!))throw ArgumentError('Unbound contract repository');
      if(widget.operationGate!=null&&!_repository!.isManagedFor(widget.operationGate!.companyId))throw ArgumentError('Unbound managed registration context');
      _session!.addListener(_invalidate);
    }
    _printScope = StandaloneTradeDocumentPrintScope(
      verifyScope: _verify,
      currentBytes: () => _bytes,
      currentTarget: () => '${widget.tradeCompanyId}:${widget.acceptance}',
      onRevoke: _invalidate,
    );
    _operationGate=widget.operationGate;
    _operationChanges=Listenable.merge([_session,_operationGate,_retirementChanges]);
    _operationGate?.addListener(_gateChanged);
    WidgetsBinding.instance.addObserver(this);
    if (WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
      _invalidate();
      return;
    }
    if (SupabaseBackend.isInitialized) {
      _auth = SupabaseBackend.client.auth.onAuthStateChange.listen(
        (_) {
          try {
            _verify();
          } catch (_) {
            _invalidate();
          }
        },
        onError: (Object _) => _invalidate(),
        onDone: _invalidate,
      );
    }
    _load();
  }

  @override
  void didUpdateWidget(covariant StandaloneTradeDocumentPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tradeCompanyId != widget.tradeCompanyId ||
        oldWidget.acceptance != widget.acceptance ||
        !identical(oldWidget.operationGate,widget.operationGate)) {
      _invalidate();
    }
  }

  void _verify() {
    if (_revoked || _repository == null) {
      throw StateError(widget.operationGate==null?'会社詳細から開き直してください。':'注文・請書を開き直してください。');
    }
    _repository!.verify();
    final gate=_operationGate;
    if(gate!=null){
      try{
        gate.requireCurrent();
        if(gate.companyId.isEmpty || gate.tradeCompanyId!=widget.tradeCompanyId ||
          gate.acceptance!=widget.acceptance || (_context!=null&&gate.companyId!=_context!['company_id'])) {
          throw StateError('書類の会社・作成対象を確認できません。');
        }
      }catch(_){_invalidate('書類の作成・保存を利用できません。注文・請書を開き直してください。');rethrow;}
    }
  }

  void _gateChanged(){try{_verify();}catch(_){_invalidate();}}

  Future<void> _refreshOperationGate()async{
    _verify();
    try{await _operationGate?.refresh();_verify();}
    catch(_){_invalidate('書類の作成・保存を利用できません。注文・請書を開き直してください。');rethrow;}
  }

  void _invalidate([String? message]) {
    _repository?.invalidate();
    if (_revoked) {
      return;
    }
    _revoked = true;
    _printScope.invalidate();
    _generation++;
    _bytes = null;_canonicalBytes=null;_renderedPayload=null;
    _context = null;
    _draft=null;
    for (final controller in _controllers.values) {
      controller.clear();
    }
    _retirementChanges.value++;
    if (mounted) {
      setState(() {
        _busy = false;
        _loading = false;
        _error = message ?? (widget.operationGate==null?'ログイン状態が変わりました。会社詳細から開き直してください。':'ログイン状態が変わりました。注文・請書を開き直してください。');
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    try {
      _printScope.visibilityChanged(switch (state) {
        AppLifecycleState.resumed => StandalonePrintVisibility.resumed,
        AppLifecycleState.inactive => StandalonePrintVisibility.inactive,
        AppLifecycleState.hidden => StandalonePrintVisibility.hidden,
        AppLifecycleState.paused => StandalonePrintVisibility.paused,
        AppLifecycleState.detached => StandalonePrintVisibility.detached,
      });
    } catch (_) {
      _invalidate();
    }
  }

  Future<void> _load() async {
    try {
      await _session?.ready();
      await _refreshOperationGate();
      final value = await _repository!.load(
        tradeCompanyId: widget.tradeCompanyId,
        acceptance: widget.acceptance,
      );
      await _refreshOperationGate();
      if (value['trade_company_id'] != widget.tradeCompanyId ||
          value['acceptance'] != widget.acceptance ||
          (_operationGate!=null&&value['company_id']!=_operationGate.companyId)) {
        throw StateError(widget.operationGate==null?'対象会社が変わりました。会社詳細から開き直してください。':'対象会社が変わりました。注文・請書を開き直してください。');
      }
      if (!mounted) {
        return;
      }
      final template = Map<String, dynamic>.from(value['template'] as Map);
      final initial = <String, String>{
        'work_name': template['work_name']?.toString() ?? '',
        'work_address': template['work_address']?.toString() ?? '',
        'issue_date': '',
        'order_date': '',
        if (!widget.acceptance) ...{
          'period_start': '',
          'period_end': '',
          'total_amount_yen': '',
          'tax_amount_yen': '',
        },
        'intro_text': template['intro_text']?.toString() ??
            '発注者（以下「甲」という）は、受注者（以下「乙」という）に対し、下記の通り工事を発注します。',
        'acceptance_text': template['acceptance_text']?.toString() ??
            '乙は、貴殿から受領した{order_date}付の注文書記載の条件通り、本工事を請け負うことを承諾いたします。',
        'payment_conditions': template['payment_conditions']?.toString() ??
            '工事完了確認後、乙の指定口座に振り込む。',
        'notes': template['notes']?.toString() ?? '',
      };
      for (final party in ['issuer', 'counterparty']) {
        final data = Map<String, dynamic>.from(value[party] as Map);
        for (final key in ['address', 'corporate_number', 'representative_name']) {
          initial['$party.$key'] = data[key]?.toString() ?? '';
        }
      }
      for (final entry in initial.entries) {
        _controllers[entry.key] = TextEditingController(text: entry.value);
      }
      final now=DateTime.now();
      final payload=TradeDocumentTermsSnapshot.initialize({
        'version':1,'kind':widget.acceptance?'acceptance':'order',
        'month':'${now.year.toString().padLeft(4,'0')}-${now.month.toString().padLeft(2,'0')}',
        for(final key in ['issuer','counterparty','company_seal_snapshot','company_seal_enabled','counterparty_bank'])if(value.containsKey(key))key:value[key],
        for(final entry in initial.entries)if(!entry.key.contains('.'))entry.key:entry.value,
      });
      _draft=TradeDocumentFormDraft.fromPayload(payload,allowAmountEditing:true,initializeExtendedFields:true,initializeDefaults:true);
      setState(() {
        _context = value;
        _loading = false;
      });
    } catch (error) {
      if (mounted && !_revoked) {
        setState(() {
          _loading = false;
          _error = error is StateError
              ? error.message.toString()
              : (widget.operationGate==null?'登録会社の情報を確認できません。会社詳細から開き直してください。':'登録会社の情報を確認できません。注文・請書を開き直してください。');
        });
      }
    }
  }

  Map<String,dynamic> _validatedPayload(Map<String,dynamic> payload,Map<String,dynamic> registered){
    final attachment=standaloneTradeDocument(context:registered,fields:{
      for(final entry in payload.entries)if(entry.value is String||entry.value is int)entry.key:entry.value.toString(),
    });
    return {...attachment.payload,'form_fields':TradeDocumentFormFields.fromJson(payload['form_fields']).toJson()};
  }
  Future<void> _edit()async {
    if(_busy||_revoked||_draft==null)return;
    setState(()=>_busy=true);
    try{
      await _refreshOperationGate();
      if(!mounted)return;
      await Navigator.of(context).push<bool>(MaterialPageRoute(builder:(_)=>TradeDocumentTouchEditorPage(
        initial:_draft!,allowExtendedFields:true,requireScope:_verify,scopeChanges:_operationChanges,canEdit:true,
        buildPreview:(payload)async{await _refreshOperationGate();final bytes=await TradeDocumentFormRenderer.canonical(_validatedPayload(payload,_context!));await _refreshOperationGate();return bytes;},
        onSave:(payload)async{
          await _refreshOperationGate();final validated=_validatedPayload(payload,_context!);
          final next=TradeDocumentFormDraft.fromPayload(validated,allowAmountEditing:true);next.validateForSave();
          await _refreshOperationGate();setState((){_draft=next;_bytes=null;_canonicalBytes=null;_renderedPayload=null;_generation++;});
        },
      )));
      await _refreshOperationGate();
    }catch(error){if(mounted&&!_revoked)setState(()=>_error=error.toString());}
    finally{if(mounted&&!_revoked)setState(()=>_busy=false);}
  }

  Future<void> _generate() async {
    final context = _context;
    if (_busy || context == null || _revoked) {
      return;
    }
    final generation = ++_generation;
    setState(() {
      _busy = true;
      _bytes = null;
      _error = null;
    });
    try {
      await _refreshOperationGate();
      final draft=_draft;if(draft==null)throw StateError('入力内容を確認してください。');
      draft.validateForSave();
      final payload=_validatedPayload(draft.payload,context);
      final canonical=await TradeDocumentFormRenderer.canonical(payload);
      await _refreshOperationGate();
      final bytes=await TradeDocumentFormRenderer.output(payload,layout:_layout,canonicalBytes:canonical);
      await _refreshOperationGate();
      if (!mounted || generation != _generation) {
        return;
      }
      setState(() {_bytes = bytes;_canonicalBytes=canonical;_renderedPayload=payload;});
    } catch (error) {
      if (mounted && !_revoked) {
        setState(() {
          _error = error is StateError
              ? error.message.toString()
              : '帳票を作成できません。入力内容を確認してください。';
        });
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _changeLayout(TradeDocumentOutputLayout next)async {
    if(_busy||_revoked)return;
    try{await _refreshOperationGate();}catch(_){return;}
    final canonical=_canonicalBytes,payload=_renderedPayload;
    if(canonical==null||payload==null){setState(()=>_layout=next);return;}
    final generation=++_generation;setState(()=>_busy=true);
    try{_verify();final bytes=await TradeDocumentFormRenderer.output(payload,layout:next,canonicalBytes:canonical);await _refreshOperationGate();
      if(mounted&&generation==_generation)setState((){_layout=next;_bytes=bytes;});
    }catch(error){if(mounted&&!_revoked)setState(()=>_error=error.toString());}
    finally{if(mounted&&generation==_generation)setState(()=>_busy=false);}
  }

  Future<void> _print({bool share=false}) async {
    final bytes = _bytes;
    if (_busy || bytes == null || _revoked) {
      return;
    }
    setState(() => _busy = true);
    try {
      await _refreshOperationGate();
      _printScope.begin(bytes);
      if(share){_printScope.layout();await Printing.sharePdf(bytes:bytes,filename:widget.acceptance?'請書.pdf':'注文書.pdf');}
      else{await Printing.layoutPdf(
        name: widget.acceptance ? '注文請書.pdf' : '注文書.pdf',
        format: _layout==TradeDocumentOutputLayout.a3Landscape?PdfPageFormat.a3.landscape:PdfPageFormat.a4,
        onLayout: (_) async {await _refreshOperationGate();return _printScope.layout();},
      );}
      await _refreshOperationGate();
    } catch (_) {
      if (mounted && !_revoked) {
        setState(() => _error = '印刷を完了できません。状態を確認してください。');
      }
    } finally {
      _printScope.end();
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _revoked = true;
    _printScope.invalidate();
    _repository?.invalidate();
    _auth?.cancel();
    _repository?.dispose();
    _operationGate?.removeListener(_gateChanged);
    _retirementChanges.dispose();
    _session?.removeListener(_invalidate);
    if(widget.sessionOverride==null)_session?.dispose();
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bytes = _bytes;
    return Scaffold(
      appBar: AppBar(title: Text(_title)),
      body: SafeArea(child: _loading
        ? const Center(child: CircularProgressIndicator())
        : ListView(padding: const EdgeInsets.all(16), children: [
          if (_error != null) Padding(padding: const EdgeInsets.only(bottom: 12),
            child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
          if (!_revoked && _context != null) ...[
            const Text('帳票をタップして工事内容・日付・明細を入力してください。会社の不足情報は会社登録から修正してください。'),
            ExpansionTile(leading: const Icon(Icons.help_outline),
              title: const Text('作成について'),
              children: const [Padding(padding: EdgeInsets.all(12), child: Text(
                '登録会社名は変更できません。文面の初期値を必要に応じて編集し、帳票を確認してください。\n'
                'この画面では請求書・支払証明書・金融データを保存しません。\n'
                '自社で内容を確認する単体帳票です。相手会社の承認・印影はまだ付いていません。双方の承認済み共有帳票としては利用できません。\n'
                '注文書の請負代金・消費税額は実額を手入力してください。日付はYYYY-MM-DDで入力します。\n'
                '入力を変えた場合は帳票を作り直してください。画面を離れたり認証が変わった場合は会社詳細から開き直してください。'))]),
            const SizedBox(height: 12),
            FilledButton.icon(onPressed:_busy?null:_edit,icon:const Icon(Icons.touch_app_outlined),
              label:Text(widget.acceptance?'請書の入力・設定':'注文書の入力・設定')),
            const Padding(padding:EdgeInsets.symmetric(vertical:8),child:Text('会社情報は登録データを使用します。入力の確定はこの画面の下書きだけに反映されます。')),
            const SizedBox(height: 12),
              TradeDocumentOutputSelector(key:ValueKey(_layout),value:_layout,enabled:!_busy,onChanged:_changeLayout),
              const SizedBox(height:12),
            FilledButton.icon(onPressed: _busy ? null : _generate,
              icon: const Icon(Icons.picture_as_pdf_outlined),
              label: const Text('帳票を確認')),
            if (_busy) const LinearProgressIndicator(),
            if (bytes != null) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(onPressed: _busy ? null : ()=>_print(),
                icon: const Icon(Icons.print_outlined), label: const Text('印刷')),
              TextButton.icon(onPressed:_busy?null:()=>_print(share:true),icon:const Icon(Icons.save_alt),label:const Text('保存・共有')),
              SizedBox(height: 520, child: PdfPreview(
                build: (_) async {
                  await _refreshOperationGate();
                  if (!identical(bytes, _bytes)) {
                    throw StateError('入力内容が更新されました。帳票を作り直してください。');
                  }
                  return bytes;
                },
                initialPageFormat: _layout==TradeDocumentOutputLayout.a3Landscape?PdfPageFormat.a3.landscape:PdfPageFormat.a4,
                canChangePageFormat: false,
                canChangeOrientation: false,
                allowPrinting: false,
                allowSharing: false,
              )),
            ],
          ],
        ])),
    );
  }
}
