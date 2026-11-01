import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:printing/printing.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../../domain/company_seal_snapshot.dart';
import 'company_seal_pdf.dart';
import '../../domain/trade_document_form_draft.dart';
import '../../domain/trade_document_terms_snapshot.dart';
import 'trade_document_form_geometry.dart';

/// Input-only surface. Trusted identity and persistence belong to the caller.
class TradeDocumentTouchEditorPage extends StatefulWidget {
  const TradeDocumentTouchEditorPage({super.key, required this.initial,
    required this.requireScope, required this.buildPreview, required this.onSave,
    required this.canEdit, this.scopeChanges, this.onEditOwnCompany,
    this.onEditCounterparty, this.allowExtendedFields = false, this.onRefreshOwnCompany});
  final TradeDocumentFormDraft initial;
  final VoidCallback requireScope;
  final Future<Uint8List> Function(Map<String, dynamic>) buildPreview;
  final Future<void> Function(Map<String, dynamic>) onSave;
  final bool canEdit;
  final bool allowExtendedFields;
  final Future<TradeDocumentFormDraft> Function(TradeDocumentFormDraft)? onRefreshOwnCompany;
  final Listenable? scopeChanges;
  final VoidCallback? onEditOwnCompany, onEditCounterparty;
  @override State<TradeDocumentTouchEditorPage> createState() => _TouchEditorState();
}

class _TouchEditorState extends State<TradeDocumentTouchEditorPage> with WidgetsBindingObserver {
  final _navigator = GlobalKey<NavigatorState>();
  final _transform = TransformationController();
  final _pointers = <int>{};
  TradeDocumentFormDraft? _draft;
  Size _viewport = Size.zero;
  Offset? _down;
  bool _gestureMoved = false, _busy = false, _revoked = false, _saveUncertain = false;
  int _generation = 0;
  int _page = 0;
  String? _error;
  static const _paper = Size(595.2755905511812, 841.8897637795277);

  @override void initState() {
    super.initState();
    _draft = widget.initial;
    WidgetsBinding.instance.addObserver(this);
    widget.scopeChanges?.addListener(_scopeChanged);
    _scopeChanged();
  }
  @override void didUpdateWidget(covariant TradeDocumentTouchEditorPage old) {
    super.didUpdateWidget(old);
    if (old.scopeChanges != widget.scopeChanges) {
      old.scopeChanges?.removeListener(_scopeChanged);
      widget.scopeChanges?.addListener(_scopeChanged);
    }
    if (!identical(old.initial, widget.initial) || !widget.canEdit) {
      _invalidate();
    } else {
      _scopeChanged();
    }
  }
  void _scopeChanged() { try { _check(); } catch (_) { _invalidate(); } }
  void _check() {
    if (_revoked || !widget.canEdit || _draft == null ||
        WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
      throw StateError('入力画面を開き直してください。');
    }
    try { widget.requireScope(); } catch (_) { _invalidate(); rethrow; }
  }
  void _invalidate() {
    if (_revoked) return;
    _revoked = true; _generation++; _draft = null; _error = null; _busy = false;
    FocusManager.instance.primaryFocus?.unfocus();
    if (mounted) setState(() {});
  }
  @override void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _invalidate();
  }
  @override void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.scopeChanges?.removeListener(_scopeChanged);
    _transform.dispose(); _draft = null;
    super.dispose();
  }
  double get _fitScale => math.min((_viewport.width - 16) / _paper.width,
      (_viewport.height - 16) / _paper.height).clamp(.1, 2.0).toDouble();
  void _fit() {
    if (!mounted || _viewport.isEmpty) return;
    final scale = _fitScale;
    _transform.value = Matrix4.identity()
      ..setEntry(0, 0, scale)..setEntry(1, 1, scale)
      ..setEntry(0, 3, (_viewport.width - _paper.width * scale) / 2)
      ..setEntry(1, 3, (_viewport.height - _paper.height * scale) / 2);
  }
  String _message(Object error) => error is FormatException ? error.message
      : error.toString().replaceFirst('Bad state: ', '');

  Future<void> _open(_Target target) async {
    if (_busy || _revoked || _saveUncertain) return;
    try { _check(); } catch (_) { _invalidate(); return; }
    final generation = _generation, context = _navigator.currentContext;
    if (context == null) return;
    if (target.company != null) {
      await showModalBottomSheet<void>(context: context, useRootNavigator: false,
        isScrollControlled: true, useSafeArea: true,
        builder: (sheet) => _CompanySheet(title: target.title,
          data: Map<String, dynamic>.from(_draft!.payload[target.company] as Map),
          onEdit: target.company == 'issuer' ? widget.onEditOwnCompany : widget.onEditCounterparty,
          requireScope: _check, onRefresh: target.company=='issuer'&&widget.onRefreshOwnCompany!=null ? () => unawaited(_refreshCompany()) : null, onTitle: target.company=='issuer'&&widget.allowExtendedFields ? () => unawaited(_open(
            const _Target('issuer_title','代表者の役職',Rect.zero,[
              _Spec('form.issuer_representative_title','役職（この書類の表示）',max:32)]))) : null));
      return;
    }
    if(target.id=='amount'&&widget.allowExtendedFields) {
      target=_Target(target.id,target.title,target.rect,[...target.specs,const _Spec('form.amount_description','発注金額の文面',max:240)]);
    }
    if (target.specs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('元の書類に登録された金額です。この入力画面では変更しません。')));
      return;
    }
    final draft = _draft!;
    final confirmed = await showModalBottomSheet<TradeDocumentFormDraft>(
      context: context, useRootNavigator: false, isScrollControlled: true,
      useSafeArea: true, builder: (_) => _FieldSheet(title: target.title,
        specs: target.specs, payload: draft.payload,
        allowExtendedFields: widget.allowExtendedFields, confirm: (values) {
          _check();
          if (generation != _generation) throw StateError('入力画面を開き直してください。');
          final form = Map<String, dynamic>.from(draft.payload['form_fields'] as Map);
          final changes = <String, Object?>{};
          var formChanged = false;
          for (final spec in target.specs) {
            final value = values[spec.path];
            if (spec.path.startsWith('base.')) {
              changes[spec.path.substring(5)] = value;
            } else {
              _writePath(form, spec.path.substring(5).split('.'), value);
              formChanged = true;
            }
          }
          if (formChanged) {
            if(form['progress_cutoff_day']=='month_end'||values.containsKey('form.issuer_representative_title')||values.containsKey('form.amount_description')) {
              if(!widget.allowExtendedFields)throw StateError('この書類では末日・役職の入力を利用できません。');
              form['schema']=2;form.putIfAbsent('issuer_representative_title',()=> '');form.putIfAbsent('amount_description',()=> '下記「施工単価内訳書」による');
            }
            changes['form_fields'] = form;
          }
          return draft.withChanges(changes);
        }));
    if (confirmed == null || !mounted) return;
    try {
      _check();
      if (generation != _generation) return;
      FocusManager.instance.primaryFocus?.unfocus();
      setState(() { _draft = confirmed; _generation++; _error = null; });
      WidgetsBinding.instance.addPostFrameCallback((_) => _fit());
    } catch (_) { _invalidate(); }
  }
  Future<void> _refreshCompany() async {
    if(_busy||_revoked||_saveUncertain||widget.onRefreshOwnCompany==null)return;
    final generation=_generation;
    try {
      _check();
      final confirmed=await showDialog<bool>(context: _navigator.currentContext!,useRootNavigator:false,
        builder:(context)=>AlertDialog(title:const Text('会社データを反映'),
          content:const Text('登録中の電話・FAX・代表者名をこの下書きに反映します。現在の表示内容を置き換えますが、保存するまでは書類へ登録しません。'),
          actions:[TextButton(onPressed:()=>Navigator.pop(context,false),child:const Text('キャンセル')),
            FilledButton(onPressed:()=>Navigator.pop(context,true),child:const Text('反映'))]));
      if(confirmed!=true)return;
      _check();if(generation!=_generation)return;
      setState(()=>_busy=true);
      final next=await widget.onRefreshOwnCompany!(_draft!);
      _check();if(!mounted||generation!=_generation)return;
      setState((){_draft=next;_generation++;_error=null;});
    }catch(error){if(mounted&&!_revoked)setState(()=>_error=_message(error));}
    finally{if(mounted&&!_revoked)setState(()=>_busy=false);}
  }
  Future<void> _preview() async {
    if (_busy || _saveUncertain) return;
    try {
      _check(); _draft!.validateForSave();
      final generation = _generation, payload = _draft!.payload;
      setState(() { _busy = true; _error = null; });
      final bytes = await widget.buildPreview(payload);
      _check();
      if (!mounted || generation != _generation) return;
      if (bytes.isEmpty) throw StateError('PDFを確認できませんでした。');
      await _navigator.currentState!.push<void>(MaterialPageRoute(builder: (_) => Scaffold(
        appBar: AppBar(title: const Text('正式PDFの確認')),
        body: PdfPreview(build: (_) async { _check(); return bytes; },
          canChangePageFormat: false, canChangeOrientation: false,
          allowPrinting: false, allowSharing: false))));
    } catch (error) {
      if (mounted && !_revoked) setState(() => _error = _message(error));
    } finally { if (mounted && !_revoked) setState(() => _busy = false); }
  }
  Future<void> _save() async {
    if (_busy || _saveUncertain) return;
    var submitted = false;
    try {
      _check(); _draft!.validateForSave();
      final generation = _generation, payload = _draft!.payload;
      FocusManager.instance.primaryFocus?.unfocus();
      setState(() { _busy = true; _error = null; });
      submitted = true;
      await widget.onSave(payload);
      _check();
      if (!mounted || generation != _generation) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted && !_revoked) {
        setState(() {
          _saveUncertain = submitted;
          _error = submitted ? '保存結果を確認できません。元の画面に戻って登録状態を確認してください。' : _message(error);
        });
      }
    } finally { if (mounted && !_revoked) setState(() => _busy = false); }
  }
  // Pure preview guard: never schedule parent state changes from a child build.
  void _verifySealPreview() {
    if (!mounted || _revoked || _draft == null ||
        WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
      throw StateError('入力画面を開き直してください。');
    }
    widget.requireScope();
  }
  void _tap(TapUpDetails details) {
    if (_page != 0 || _gestureMoved || _busy || _revoked || _saveUncertain) return;
    final point = _transform.toScene(details.localPosition);
    for (final target in _targets(_draft!, _paper)) {
      if (target.rect.contains(point)) { unawaited(_open(target)); return; }
    }
  }
  @override Widget build(BuildContext context) {
    if (_revoked) {
      return Scaffold(appBar: AppBar(title: const Text('書類入力')),
        body: const Center(child: Text('入力を停止しました。元の画面から開き直してください。')));
    }
    return Navigator(key: _navigator, pages: [MaterialPage<void>(child: Scaffold(resizeToAvoidBottomInset: false,
      appBar: AppBar(title: Text(_draft!.isOrder ? '注文書の入力' : '請書の入力'),
        leading: BackButton(onPressed: _busy ? null : () => Navigator.of(context).pop(false)),
        actions: [IconButton(key: const Key('trade-touch-fit'), tooltip: '全体を見る',
          onPressed: _fit, icon: const Icon(Icons.fit_screen))]),
      body: Column(children: [
        const Padding(padding: EdgeInsets.symmetric(vertical: 6),
          child: Text('枠をタップして入力・指で拡大縮小できます', style: TextStyle(fontSize: 12))),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: Row(children: [
          for (final page in [0, 1]) Expanded(child: TextButton(
            key: ValueKey('trade-touch-page-$page'),
            onPressed: _busy ? null : () {
              try { _check(); } catch (_) { _invalidate(); return; }
              setState(() => _page = page);
              WidgetsBinding.instance.addPostFrameCallback((_) => _fit());
            },
            child: Text(page == 0 ? '1 / 2 帳票' : '2 / 2 契約条項',
              style: TextStyle(fontWeight: _page == page ? FontWeight.bold : FontWeight.normal)),
          )),
        ])),
        if (_error != null) Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
          child: Text(_error!, key: const Key('trade-touch-error'), style: const TextStyle(color: Colors.red))),
        Expanded(child: LayoutBuilder(builder: (context, constraints) {
          final size = Size(constraints.maxWidth, constraints.maxHeight);
          if (size != _viewport) {
            _viewport = size;
            WidgetsBinding.instance.addPostFrameCallback((_) => _fit());
          }
          return Listener(onPointerDown: (event) {
            if (_pointers.isEmpty) { _gestureMoved = false; _down = event.localPosition; }
            _pointers.add(event.pointer);
            if (_pointers.length > 1) _gestureMoved = true;
          }, onPointerMove: (event) {
            if (_down != null && (event.localPosition - _down!).distance > 8) _gestureMoved = true;
          }, onPointerUp: (event) => _pointers.remove(event.pointer),
          onPointerCancel: (event) { _pointers.remove(event.pointer); _gestureMoved = true; },
          child: GestureDetector(behavior: HitTestBehavior.opaque, onTapUp: _tap,
            child: InteractiveViewer(key: const Key('trade-touch-viewport'),
              transformationController: _transform, constrained: false,
              minScale: .1, maxScale: 5, boundaryMargin: const EdgeInsets.all(200),
              child: _page == 0
                ? _Paper(draft: _draft!, size: _paper, requireScope: _verifySealPreview,
                    onTarget: (target) => unawaited(_open(target)))
                : _TermsPaper(snapshot: _draft!.payload['contract_terms'], size: _paper))));
        })),
      ]),
      bottomNavigationBar: SafeArea(top: false, child: Padding(padding: const EdgeInsets.all(12),
        child: Row(children: [OutlinedButton(onPressed: _busy || _saveUncertain ? null : _preview,
          child: const Text('PDF確認')), const SizedBox(width: 12),
          Expanded(child: FilledButton(key: const Key('trade-touch-save'),
            onPressed: _busy || _saveUncertain ? null : _save,
            child: Text(_busy ? '確認しています…' : '書類に保存')))]))),
    ))], onDidRemovePage: (_) {});
  }
}

Object? _readPath(Map<String, dynamic> payload, String path) {
  dynamic value = path.startsWith('base.') ? payload : payload['form_fields'];
  for (final key in path.substring(5).split('.')) {
    value = value is List ? value[int.parse(key)] : (value as Map)[key];
  }
  return value;
}
void _writePath(Map<String, dynamic> map, List<String> path, Object? value) {
  dynamic current = map;
  for (final key in path.take(path.length - 1)) {
    current = current is List ? current[int.parse(key)] : (current as Map)[key];
  }
  if (current is List) { current[int.parse(path.last)] = value; }
  else { (current as Map)[path.last] = value; }
}

enum _InputKind { text, integer, decimal, date, choice, month, closingDay }
class _Spec {
  const _Spec(this.path, this.label, {this.kind = _InputKind.text,
    this.max = 240, this.lines = 1, this.nullable = false});
  final String path, label;
  final _InputKind kind;
  final int max, lines;
  final bool nullable;
}
class _Target {
  const _Target(this.id, this.title, this.rect, this.specs, {this.company});
  final String id, title;
  final Rect rect;
  final List<_Spec> specs;
  final String? company;
}
List<_Target> _targets(TradeDocumentFormDraft draft, Size paper) {
  final order = draft.isOrder, g = tradeDocumentFormGeometry[order ? 'order' : 'acceptance']!;
  final ys = (g['ys'] as List).cast<num>().map((n) => n.toDouble()).toList();
  const left = 34.0, right = 561.2755905511812;
  final width = right - left, scale = width / (order ? 1217 : 1183);
  double x(double px) => left + (px - (order ? 164 : 239)) * scale;
  final a = x(order ? 301 : 377), m = x(order ? 810 : 876), n = x(order ? 984 : 1046);
  Rect row(int high, int low, [double l = left, double r = right]) =>
      Rect.fromLTRB(l, paper.height - ys[high], r, paper.height - ys[low]);
  final targets = <_Target>[
    _Target('issue_date', order ? '発行日' : '承諾日', const Rect.fromLTWH(415, 20, 146, 30),
      [const _Spec('base.issue_date', '日付', kind: _InputKind.date)]),
    _Target('counterparty', order ? '受注者の登録情報' : '注文者の登録情報',
      Rect.fromLTWH(36, 84, 250, math.min(76.0, paper.height - ys[0] - 126)),
      const [], company: 'counterparty'),
    _Target('issuer', order ? '注文者の登録情報' : '受注者の登録情報',
      Rect.fromLTWH(315, 84, 246, paper.height - ys[0] - 88), const [], company: 'issuer'),
    _Target('intro', order ? '注文の文面' : '承諾の文面',
      Rect.fromLTWH(36, paper.height - ys[0] - 37, 258, 34),
      [order ? const _Spec('base.intro_text', '注文の文面', max: 400, lines: 3)
        : const _Spec('base.acceptance_text', '承諾の文面（必須）', max: 400, lines: 3),
       const _Spec('base.order_date', '注文書の日付', kind: _InputKind.date)]),
    _Target('work_name', '工事名称', row(0, 1, a, m),
      [const _Spec('base.work_name', '工事名称（必須）')]),
    _Target('work_content', '工事内容', row(0, 1, n),
      [const _Spec('form.work_content', '工事内容', lines: 3)]),
    _Target('work_address', '工事場所', row(1, 2, a, m),
      [const _Spec('base.work_address', '工事場所（必須）')]),
    _Target('period', '工期', row(1, 2, n), [
      const _Spec('base.period_start', '着手日', kind: _InputKind.date),
      const _Spec('base.period_end', '完成日', kind: _InputKind.date)]),
    _Target('amount', '発注金額', row(2, 3, a), draft.allowAmountEditing ? [
      const _Spec('base.total_amount_yen', '発注金額（円・必須）', kind: _InputKind.integer),
      const _Spec('base.tax_amount_yen', 'うち消費税等（円・必須）', kind: _InputKind.integer)] : const []),
    _Target('cutoffs', '締切日・支払日', row(6, 7), [
      const _Spec('form.progress_cutoff_day', '出来高締切日（毎月）', kind: _InputKind.closingDay),
      const _Spec('form.invoice_cutoff_day', '請求書締切日（毎月）', kind: _InputKind.integer),
      const _Spec('form.payment_month_offset', '支払月', kind: _InputKind.month),
      const _Spec('form.payment_day', '支払日', kind: _InputKind.integer)]),
    _Target('ratios', '支払条件', row(7, 8), [
      const _Spec('base.payment_conditions', '支払条件', max: 400, lines: 3),
      const _Spec('form.cash_ratio_percent', '現金比率（%）', kind: _InputKind.decimal, nullable: true),
      const _Spec('form.bill_ratio_percent', '手形比率（%）', kind: _InputKind.decimal, nullable: true),
      const _Spec('form.bill_months', '手形決済までの月数', kind: _InputKind.integer)]),
    _Target('supplies', '支給品', row(8, 9, a),
      [const _Spec('form.supplies', '支給品', max: 400, lines: 3)]),
    _Target('notes', '特記事項', row(20, 21),
      [const _Spec('base.notes', '特記事項', max: 600, lines: 4)]),
  ];
  for (var i = 0; i < 3; i++) {
    final key = ['advance', 'partial', 'completion'][i];
    targets.add(_Target('payment_$key', ['前金払', '部分払', '完成払'][i], row(3 + i, 4 + i), [
      _Spec('form.payments.$key.choice', '有無', kind: _InputKind.choice),
      _Spec('form.payments.$key.date', '支払時期', kind: _InputKind.date, nullable: true),
      _Spec('form.payments.$key.amount_yen', '支払額（円）', kind: _InputKind.integer)]));
  }
  for (var i = 0; i < 9; i++) {
    targets.add(_Target('row_$i', '明細 ${i + 1}行目', row(11 + i, 12 + i), [
      _Spec('form.rows.$i.item', '項目', max: 120, lines: 2),
      _Spec('form.rows.$i.quantity', '数量', kind: _InputKind.decimal, max: 16),
      _Spec('form.rows.$i.unit', '単位', max: 16),
      _Spec('form.rows.$i.unit_price_yen', '単価（円）', kind: _InputKind.integer),
      _Spec('form.rows.$i.amount_yen', '金額（円・手入力）', kind: _InputKind.integer),
      _Spec('form.rows.$i.note', '備考', max: 80, lines: 2)]));
  }
  return targets;
}

String _shown(Object? value) {
  if (value == null || value == '') return '';
  if (value == 'yes') return '有';
  if (value == 'no') return '無';
  if (value == 'unspecified') return '未選択';
  if (value is int) return value.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
  return value.toString();
}
// A template token is replaced for display only. The actual stored draft and
// its validation still require the user-entered date; never invent one here.
String _shownInputValue(Map<String, dynamic> payload, String path) {
  final value = _shown(_readPath(payload, path));
  if (path != 'base.acceptance_text') return value;
  final date = payload['order_date']?.toString().trim() ?? '';
  return value.replaceAll('{order_date}', date.isEmpty ? '（注文書日を入力）' : date);
}

/// An input-surface preview of the exact saved issuer seal, not a counterparty
/// approval stamp. PDF rendering and persisted seal metadata are unchanged.
class _InputSealPreview extends StatefulWidget {
  const _InputSealPreview({super.key, required this.snapshot,
    required this.issuerName, required this.requireScope});
  final Object? snapshot;
  final String issuerName;
  final VoidCallback requireScope;
  @override State<_InputSealPreview> createState() => _InputSealPreviewState();
}

class _InputSealPreviewState extends State<_InputSealPreview> {
  late final Future<Uint8List> _png = _render();
  Future<Uint8List> _render() async {
    widget.requireScope();
    final seal = CompanySealSnapshot.fromJson(widget.snapshot);
    if (seal.name.isEmpty || seal.name != widget.issuerName) {
      throw StateError('登録角印の会社が一致しません。');
    }
    // Build the seal through the same font/style/hash-checked PDF component as
    // the final form. No live company lookup, synthetic text stamp or network.
    final font = await CompanySealPdf.loadStyleFont(seal.style);
    widget.requireScope();
    final fallback = await CompanySealPdf.loadFont();
    widget.requireScope();
    final document = pw.Document();
    document.addPage(pw.Page(pageFormat: const PdfPageFormat(42, 42),
      margin: pw.EdgeInsets.zero, build: (_) => CompanySealPdf.build(seal.name,
        font: font, fallbackFont: fallback, companyId: seal.companyId,
        uploadedPng: seal.uploadedPng, style: seal.style, size: 42)));
    final bytes = await document.save();
    widget.requireScope();
    final raster = await Printing.raster(bytes, pages: const [0], dpi: 144).first
        .timeout(const Duration(seconds: 10));
    widget.requireScope();
    final png = await raster.toPng();
    widget.requireScope();
    return png;
  }
  @override Widget build(BuildContext context) => FutureBuilder<Uint8List>(
    future: _png, builder: (context, snapshot) {
      if (snapshot.hasData) {
        return Semantics(container: true, label: '自社登録角印のプレビュー・相手の承認印ではありません', image: true,
          child: Image.memory(snapshot.data!, key: const Key('trade-input-own-seal'),
            fit: BoxFit.contain, excludeFromSemantics: true));
      }
      return Text(snapshot.hasError ? '角印を確認できません' : '角印確認中',
        key: const Key('trade-input-seal-status'), style: const TextStyle(fontSize: 6));
    });
}

/// The immutable second page is available even before required front inputs.
class _TermsPaper extends StatelessWidget {
  const _TermsPaper({required this.snapshot, required this.size});
  final Object? snapshot;
  final Size size;
  @override Widget build(BuildContext context) {
    final terms = TradeDocumentTermsSnapshot.fromJson(snapshot);
    final paragraphs = <String>[];
    for (var i = 0; i < terms.articles.length; i++) {
      final article = terms.articles[i];
      paragraphs.add('（${article.$1}）');
      for (var j = 0; j < article.$2.length; j++) {
        paragraphs.add('${j == 0 ? '第${i + 1}条　' : '　　　　'}${article.$2[j]}');
      }
    }
    return Container(key: const Key('trade-touch-terms-paper'), width: size.width,
      height: size.height, color: Colors.white,
      padding: const EdgeInsets.fromLTRB(34, 34, 34, 34),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text(TradeDocumentTermsSnapshot.title,
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Expanded(child: FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.topLeft,
          child: SizedBox(width: size.width - 68,
            child: Text(paragraphs.join('\n'), key: const Key('trade-touch-terms-text'),
              style: const TextStyle(fontSize: 6.5, height: 8.14 / 6.5, color: Colors.black)))),
        ),
      ]));
  }
}

/// Keep the saved issuer stamp centered over the visible company-name end.
class _InputCompanyName extends StatelessWidget {
  const _InputCompanyName({required this.name, required this.enabled,
    required this.snapshot, required this.requireScope});
  final String name;
  final bool enabled;
  final Object? snapshot;
  final VoidCallback requireScope;
  @override Widget build(BuildContext context) => LayoutBuilder(builder: (context, constraints) {
    const sealSize = 22.0;
    final available = constraints.maxWidth;
    final natural = TextPainter(text: TextSpan(text: name,
      style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold)),
      textDirection: TextDirection.ltr, textScaler: MediaQuery.textScalerOf(context))..layout();
    final maximum = available - (enabled ? sealSize / 2 : 0);
    final ratio = natural.width > maximum ? maximum / natural.width : 1.0;
    final printed = natural.width * ratio;
    final sealLeft = (printed - sealSize / 2).clamp(0.0, available - sealSize).toDouble();
    natural.dispose();
    return SizedBox(height: sealSize, child: Stack(clipBehavior: Clip.none, children: [
      Positioned(left: 0, top: 0, width: printed, height: sealSize,
        child: FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft,
          child: Text(name, key: const Key('trade-input-issuer-name'),
            style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold)))),
      if (enabled) Positioned(left: sealLeft, top: 0, width: sealSize, height: sealSize,
        child: IgnorePointer(key: const Key('trade-input-seal-position'),
          child: _InputSealPreview(
            key: ValueKey(crypto.sha256.convert(utf8.encode(jsonEncode([snapshot, name]))).toString()),
            snapshot: snapshot, issuerName: name, requireScope: requireScope))),
    ]));
  });
}

class _Paper extends StatelessWidget {
  const _Paper({required this.draft, required this.size, required this.onTarget, required this.requireScope});
  final TradeDocumentFormDraft draft;
  final Size size;
  final ValueChanged<_Target> onTarget;
  final VoidCallback requireScope;
  @override Widget build(BuildContext context) {
    final payload = draft.payload, targets = _targets(draft, size);
    Widget text(Rect rect, String value, {double font = 8, bool bold = false,
        Color color = Colors.black, int lines = 2, TextAlign align = TextAlign.left}) =>
      Positioned.fromRect(rect: rect.deflate(3), child: Align(alignment: Alignment.centerLeft,
        child: Text(value, maxLines: lines, overflow: TextOverflow.ellipsis,
          textAlign: align, style: TextStyle(fontSize: font, height: 1.25,
            color: color, fontWeight: bold ? FontWeight.w700 : FontWeight.normal))));
    final children = <Widget>[CustomPaint(size: size, painter: _PaperLines(draft.isOrder))];
    children.add(text(const Rect.fromLTWH(205, 35, 200, 38), draft.isOrder ? '注　文　書' : '請　書',
      font: 20, bold: true, align: TextAlign.center));
    for (final target in targets) {
      String value;
      if (target.company != null) {
        final party = Map<String, dynamic>.from(payload[target.company] as Map);
        value = '${target.title}\n\n${party['name'] ?? ''}\n${party['address'] ?? ''}\n${target.company=='issuer' ? (payload['form_fields'] as Map)['issuer_representative_title'] ?? '' : ''} ${party['representative_name'] ?? ''}';
        if (target.company == 'issuer') {
          value += '\nTEL ${party['phone'] ?? ''}　FAX ${party['fax'] ?? ''}';
        }
      } else if (target.id.startsWith('row_')) {
        final columns = (tradeDocumentFormGeometry[draft.isOrder ? 'order' : 'acceptance']!['grid_columns'] as List).cast<num>();
        for (var i = 0; i < target.specs.length; i++) {
          final spec = target.specs[i], shown = _shown(_readPath(payload, spec.path));
          children.add(text(Rect.fromLTRB(columns[i].toDouble(), target.rect.top,
            columns[i + 1].toDouble(), target.rect.bottom), shown, font: 8));
        }
        if (target.specs.every((s) => _shown(_readPath(payload, s.path)).isEmpty)) {
          children.add(text(target.rect, '${int.parse(target.id.substring(4)) + 1}　タップして入力',
            font: 7, color: Colors.blueGrey));
        }
        value = '';
      } else if (target.id.startsWith('payment_')) {
        value = '${target.title}　${target.specs.map((s) => _shown(_readPath(payload, s.path))).where((s) => s.isNotEmpty).join('　')}';
      } else {
        final values = target.specs.map((s) => _shownInputValue(payload, s.path)).where((s) => s.isNotEmpty);
        value = values.join('　');
        if (target.id == 'amount' && !draft.allowAmountEditing) {
          value = '${_shown(payload['total_amount_yen'])} 円（元書類の金額）';
        }
      }
      if (target.company == 'issuer') {
        final party = Map<String, dynamic>.from(payload['issuer'] as Map);
        children.add(Positioned.fromRect(rect: target.rect.deflate(3),
          child: Align(alignment: Alignment.centerLeft, child: FittedBox(
            fit: BoxFit.scaleDown, alignment: Alignment.centerLeft,
            child: SizedBox(width: target.rect.width - 6, child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(target.title, style: const TextStyle(fontSize: 9, height: 1.25, fontWeight: FontWeight.bold)),
              const SizedBox(key: Key('trade-input-issuer-heading-gap'), height: 11.25),
              _InputCompanyName(name: party['name']?.toString() ?? '',
                enabled: payload['company_seal_enabled'] == true,
                snapshot: payload['company_seal_snapshot'], requireScope: requireScope),
              for (final line in [party['address']?.toString() ?? '',
                '${(payload['form_fields'] as Map)['issuer_representative_title'] ?? ''} ${party['representative_name'] ?? ''}',
                'TEL ${party['phone'] ?? ''}　FAX ${party['fax'] ?? ''}'])
                Text(line, style: const TextStyle(fontSize: 9, height: 1.25, fontWeight: FontWeight.bold)),
            ])),
          ))));
      } else if (!target.id.startsWith('row_') && !target.id.startsWith('payment_') &&
          !const ['cutoffs', 'ratios'].contains(target.id)) {
        children.add(text(target.rect, value.isEmpty ? 'タップして入力' : value,
          font: target.company != null ? 9 : 8, lines: target.company != null ? 6 : 3,
          bold: target.company != null, color: value.isEmpty ? Colors.blueGrey : Colors.black));
      }
      children.add(Positioned.fromRect(rect: target.rect, child: Semantics(
        key: ValueKey('trade-touch-target-${target.id}'), label: target.title,
        button: true, onTap: () => onTarget(target), child: DecoratedBox(
          decoration: BoxDecoration(border: Border.all(width: .35,
            color: target.company != null ? Colors.transparent : Colors.blue.withAlpha(38)))))));
    }
    final g = tradeDocumentFormGeometry[draft.isOrder ? 'order' : 'acceptance']!;
    final ys = (g['ys'] as List).cast<num>();
    final a = 34 + ((draft.isOrder ? 301 : 377) - (draft.isOrder ? 164 : 239)) * 527.2755905511812 / (draft.isOrder ? 1217 : 1183);
    final cols = (g['grid_columns'] as List).cast<num>();
    for (final label in [(0, 1, '工事名称'), (1, 2, '工事場所'), (2, 3, '発注金額'), (8, 9, '支給品')]) {
      children.add(text(Rect.fromLTRB(34, size.height - ys[label.$1], a,
        size.height - ys[label.$2]), label.$3, bold: true, align: TextAlign.center));
    }
    const left = 34.0, right = 561.2755905511812;
    final scale = 527.2755905511812 / (draft.isOrder ? 1217 : 1183);
    double xx(double px) => left + (px - (draft.isOrder ? 164 : 239)) * scale;
    final m = xx(draft.isOrder ? 810 : 876), n = xx(draft.isOrder ? 984 : 1046);
    final spine = xx(draft.isOrder ? 210 : 285), choice = xx(draft.isOrder ? 465 : 536);
    final when = xx(draft.isOrder ? 595 : 663), paylabel = xx(draft.isOrder ? 882 : 945);
    Rect cell(double l, double r, int high, int low) =>
      Rect.fromLTRB(l, size.height - ys[high], r, size.height - ys[low]);
    children.add(text(cell(m, n, 0, 1), '工事内容', bold: true));
    children.add(text(cell(m, n, 1, 2), '工期', bold: true));
    children.add(text(cell(left, spine, 3, 6), '支\n払\n方\n法', bold: true));
    final form = Map<String, dynamic>.from(payload['form_fields'] as Map);
    final payments = form['payments'] as Map;
    for (var i = 0; i < 3; i++) {
      final payment = payments[['advance', 'partial', 'completion'][i]] as Map;
      for (final value in [
        (spine, a, ['前金払', '部分払', '完成払'][i]),
        (a, choice, _shown(payment['choice'])), (choice, when, '支払時期'),
        (when, paylabel, _shown(payment['date'])), (paylabel, n, '支払額'),
        (n, right, _shown(payment['amount_yen'])),
      ]) { children.add(text(cell(value.$1, value.$2, 3 + i, 4 + i), value.$3, font: 7.5)); }
    }
    final month = {0: '当月', 1: '翌月', 2: '翌々月'}[form['payment_month_offset']] ?? '';
    for (final value in [
      (left, a, '出来高締切日'), (a, choice, '毎月 ${tradeDocumentClosingDay(form['progress_cutoff_day'])}${form['progress_cutoff_day']=='month_end'?'':' 日'}'),
      (choice, when, '請求書締切日'), (when, m, '毎月 ${_shown(form['invoice_cutoff_day'])} 日'),
      (m, n, '支払日'), (n, right, '$month ${_shown(form['payment_day'])} 日'),
    ]) { children.add(text(cell(value.$1, value.$2, 6, 7), value.$3, font: 7.5)); }
    for (final value in [
      (left, a, '支払条件'), (a, choice, '現金比率'),
      (choice, when, '${_shown(form['cash_ratio_percent'])} %'), (when, m, '手形比率'),
      (m, n, '${_shown(form['bill_ratio_percent'])} %'),
      (n, right, '決済まで ${_shown(form['bill_months'])} ヶ月'),
    ]) { children.add(text(cell(value.$1, value.$2, 7, 8), value.$3, font: 7.5)); }
    children.add(text(Rect.fromLTRB(34, size.height - ys[9], 561.2755905511812,
      size.height - ys[10]), draft.isOrder ? '施工単価内訳書' : '工事費内訳書', bold: true, align: TextAlign.center));
    for (var i = 0; i < 6; i++) {
      children.add(text(Rect.fromLTRB(cols[i].toDouble(), size.height - ys[10],
        cols[i + 1].toDouble(), size.height - ys[11]),
        ['項目', '数量', '単位', '単価', '金額', '備考'][i], bold: true));
    }
    return SizedBox(width: size.width, height: size.height,
      child: ColoredBox(color: Colors.white, child: Stack(children: children)));
  }
}
class _PaperLines extends CustomPainter {
  const _PaperLines(this.order);
  final bool order;
  @override void paint(Canvas canvas, Size size) {
    final g = tradeDocumentFormGeometry[order ? 'order' : 'acceptance']!;
    final ys = (g['ys'] as List).cast<num>(), cols = (g['grid_columns'] as List).cast<num>();
    final paint = Paint()..color = Colors.black..strokeWidth = .5;
    void line(double x1, num high, double x2, num low) =>
      canvas.drawLine(Offset(x1, size.height - high), Offset(x2, size.height - low), paint);
    const left = 34.0, right = 561.2755905511812;
    for (var i = 0; i < ys.length; i++) { if (i != 4 && i != 5) line(left, ys[i], right, ys[i]); }
    line(left, ys.first, left, ys.last); line(right, ys.first, right, ys.last);
    final scale = (right - left) / (order ? 1217 : 1183);
    double x(double px) => left + (px - (order ? 164 : 239)) * scale;
    final a = x(order ? 301 : 377), m = x(order ? 810 : 876), n = x(order ? 984 : 1046);
    for (final xx in [a, m, n]) { line(xx, ys[0], xx, ys[2]); }
    line(a, ys[2], a, ys[3]);
    final spine = x(order ? 210 : 285);
    for (final xx in [spine, a, x(order ? 465 : 536), x(order ? 595 : 663), x(order ? 882 : 945), n]) {
      line(xx, ys[3], xx, ys[6]);
    }
    line(spine, ys[4], right, ys[4]); line(spine, ys[5], right, ys[5]);
    for (final xx in [a, x(order ? 465 : 536), x(order ? 595 : 663), m, n]) {
      line(xx, ys[6], xx, ys[8]);
    }
    line(a, ys[8], a, ys[9]);
    for (final xx in cols.skip(1).take(5)) { line(xx.toDouble(), ys[10], xx.toDouble(), ys[20]); }
  }
  @override bool shouldRepaint(covariant _PaperLines old) => old.order != order;
}

class _FieldSheet extends StatefulWidget {
  const _FieldSheet({required this.title, required this.specs, required this.payload,
    required this.confirm, required this.allowExtendedFields});
  final String title;
  final bool allowExtendedFields;
  final List<_Spec> specs;
  final Map<String, dynamic> payload;
  final TradeDocumentFormDraft Function(Map<String, Object?>) confirm;
  @override State<_FieldSheet> createState() => _FieldSheetState();
}
class _FieldSheetState extends State<_FieldSheet> {
  final _controllers = <String, TextEditingController>{};
  final _scroll = ScrollController();
  String? _error;
  @override void initState() {
    super.initState();
    for (final spec in widget.specs) {
      _controllers[spec.path] = TextEditingController(text: _readPath(widget.payload, spec.path)?.toString() ?? '');
    }
  }
  @override void dispose() {
    for (final c in _controllers.values) { c.clear(); c.dispose(); }
    _scroll.dispose(); super.dispose();
  }
  void _confirm() {
    try {
      final values = <String, Object?>{};
      for (final spec in widget.specs) {
        final text = _controllers[spec.path]!.text;
        values[spec.path] = switch (spec.kind) {
          _InputKind.closingDay => text=='month_end' ? 'month_end' : text.isEmpty ? null : int.tryParse(text) ?? (throw const FormatException('1〜31の日付または末日を選択してください。')),
          _InputKind.integer || _InputKind.month => text.isEmpty ? null :
            int.tryParse(text) ?? (throw const FormatException('数値は整数で入力してください。')),
          _InputKind.date => text.isEmpty && spec.nullable ? null : text,
          _InputKind.decimal => text.isEmpty && spec.nullable ? null : text,
          _ => text,
        };
      }
      final result = widget.confirm(values);
      FocusManager.instance.primaryFocus?.unfocus();
      Navigator.of(context).pop(result);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error is FormatException ? error.message : '入力内容を確認してください。');
      if (_scroll.hasClients) _scroll.jumpTo(0);
    }
  }
  Future<void> _date(_Spec spec) async {
    FocusManager.instance.primaryFocus?.unfocus();
    final initial = DateTime.tryParse(_controllers[spec.path]!.text) ?? DateTime.now();
    final result = await showDatePicker(context: context, useRootNavigator: false,
      initialDate: initial, firstDate: DateTime(1), lastDate: DateTime(9999, 12, 31),
      helpText: '日付を選択', cancelText: '戻る', confirmText: '決定');
    if (result != null && mounted) setState(() => _controllers[spec.path]!.text = result.toIso8601String().substring(0, 10));
  }
  bool _disabled(_Spec spec) {
    if (!spec.path.startsWith('form.payments.') || spec.kind == _InputKind.choice) return false;
    final prefix = spec.path.substring(0, spec.path.lastIndexOf('.'));
    return _controllers['$prefix.choice']?.text == 'no';
  }
  Widget _field(_Spec spec, bool first) {
    final controller = _controllers[spec.path]!;
    if (spec.kind == _InputKind.closingDay) {
      final monthEnd=controller.text=='month_end';
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(spec.label),
        Wrap(spacing: 8, children: [
          ChoiceChip(label: const Text('日付を指定'), selected: !monthEnd,
            onSelected: (_) => setState(() { if(monthEnd)controller.clear(); })),
          ChoiceChip(label: const Text('末日'), selected: monthEnd,
            onSelected: widget.allowExtendedFields ? (_) => setState(() { FocusManager.instance.primaryFocus?.unfocus();controller.text='month_end'; }) : null),
        ]),
        if(!monthEnd)TextField(key: ValueKey('trade-touch-input-${spec.path}'), controller: controller,
          keyboardType: TextInputType.number, inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(labelText: '日付（1〜31日）', border: OutlineInputBorder()),
          textInputAction: TextInputAction.done, onEditingComplete: () => FocusManager.instance.primaryFocus?.unfocus()),
        if(!widget.allowExtendedFields)const Text('末日の設定は、会社の書類設定を更新後に利用できます。', style: TextStyle(fontSize: 12)),
      ]);
    }
    if (spec.kind == _InputKind.date) {
      return ListTile(contentPadding: EdgeInsets.zero, title: Text(spec.label),
        subtitle: Text(controller.text.isEmpty ? '日付を選択してください' : controller.text),
        onTap: _disabled(spec) ? null : () => _date(spec),
        trailing: controller.text.isEmpty ? const Icon(Icons.calendar_month) : IconButton(
          tooltip: '日付を空欄に戻す', onPressed: _disabled(spec) ? null : () => setState(controller.clear),
          icon: const Icon(Icons.clear)));
    }
    if (spec.kind == _InputKind.choice || spec.kind == _InputKind.month) {
      final choices = spec.kind == _InputKind.choice
          ? {'unspecified': '未選択', 'yes': '有', 'no': '無'}
          : {'': '未選択', '0': '当月', '1': '翌月', '2': '翌々月'};
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(spec.label),
        Wrap(spacing: 8, children: [for (final entry in choices.entries) ChoiceChip(
          label: Text(entry.value), selected: controller.text == entry.key,
          onSelected: (_) => setState(() {
            controller.text = entry.key;
            if (spec.kind == _InputKind.choice && entry.key == 'no') {
              final prefix = spec.path.substring(0, spec.path.lastIndexOf('.'));
              _controllers['$prefix.date']?.clear(); _controllers['$prefix.amount_yen']?.clear();
            }
          }))]),
        if (spec.kind == _InputKind.choice) const Text('無の場合は、この行の支払時期と金額を空欄にします。', style: TextStyle(fontSize: 12)),
      ]);
    }
    return TextField(key: ValueKey('trade-touch-input-${spec.path}'), controller: controller,
      autofocus: first, enabled: !_disabled(spec), maxLength: spec.max,
      maxLengthEnforcement: MaxLengthEnforcement.none,
      maxLines: spec.lines, textInputAction: TextInputAction.done,
      keyboardType: spec.kind == _InputKind.integer ? TextInputType.number
          : spec.kind == _InputKind.decimal ? const TextInputType.numberWithOptions(decimal: true)
          : spec.lines > 1 ? TextInputType.multiline : TextInputType.text,
      decoration: InputDecoration(labelText: spec.label, border: const OutlineInputBorder()),
      onEditingComplete: () => FocusManager.instance.primaryFocus?.unfocus());
  }
  @override Widget build(BuildContext context) {
    final media = MediaQuery.of(context), available = math.max(64.0,
      media.size.height - media.viewInsets.bottom - media.padding.top - 12);
    final height = math.min(560.0, available);
    return Padding(padding: EdgeInsets.only(bottom: media.viewInsets.bottom), child: SizedBox(
      height: height, child: Column(children: [
        if (height >= 180) Padding(padding: const EdgeInsets.all(16),
          child: Text(widget.title, style: Theme.of(context).textTheme.titleMedium)),
        Expanded(child: SingleChildScrollView(controller: _scroll, padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(children: [
            if (_error != null) Padding(padding: const EdgeInsets.only(bottom: 12),
              child: Text(_error!, key: const Key('trade-touch-field-error'), style: const TextStyle(color: Colors.red))),
            for (var i = 0; i < widget.specs.length; i++) Padding(padding: const EdgeInsets.only(bottom: 12),
              child: _field(widget.specs[i], i == 0)),
          ]))),
        SafeArea(top: false, child: Padding(padding: const EdgeInsets.fromLTRB(16, 4, 16, 8), child: Row(children: [
          TextButton(onPressed: () { FocusManager.instance.primaryFocus?.unfocus(); Navigator.of(context).pop(); }, child: const Text('戻る')),
          const Spacer(), FilledButton(key: const Key('trade-touch-field-confirm'),
            onPressed: _confirm, child: const Text('入力を確定')),
        ]))),
      ])));
  }
}
class _CompanySheet extends StatelessWidget {
  const _CompanySheet({required this.title, required this.data, required this.requireScope, this.onEdit, this.onTitle, this.onRefresh});
  final String title;
  final Map<String, dynamic> data;
  final VoidCallback requireScope;
  final VoidCallback? onEdit, onTitle, onRefresh;
  @override Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final height = math.min(520.0, math.max(64.0,
      media.size.height - media.viewInsets.bottom - media.padding.top - 16));
    const labels = {'name': '会社名', 'address': '住所', 'representative_name': '代表者名',
      'phone': '電話', 'fax': 'FAX', 'corporate_number': '法人番号'};
    return Padding(padding: EdgeInsets.only(bottom: media.viewInsets.bottom), child: SizedBox(
      height: height, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (height >= 180) Padding(padding: const EdgeInsets.all(16),
          child: Text(title, style: Theme.of(context).textTheme.titleMedium)),
        Expanded(child: SingleChildScrollView(padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            for (final entry in labels.entries)
              if (data[entry.key]?.toString().isNotEmpty == true) Padding(
                padding: const EdgeInsets.only(bottom: 12), child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(entry.value, style: const TextStyle(fontWeight: FontWeight.bold)),
                    Text(data[entry.key].toString()),
                  ])),
            const Text('登録会社の情報です。この書類の入力欄では変更しません。'),
            if(onRefresh!=null)TextButton(onPressed: () {requireScope();Navigator.of(context).pop();onRefresh!();}, child: const Text('会社データを反映')),
            if(onTitle!=null)TextButton(onPressed: () {requireScope();Navigator.of(context).pop();onTitle!();}, child: const Text('代表者の役職を入力')),
          ]))),
        SafeArea(top: false, child: Padding(padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Row(children: [
            if (onEdit != null) Expanded(child: TextButton(onPressed: () {
              try { requireScope(); } catch (_) { return; }
              Navigator.of(context).pop(); onEdit!();
            }, child: const Text('会社情報の画面を開く', maxLines: 2, textAlign: TextAlign.center)))
            else const Spacer(),
            const SizedBox(width: 8),
            TextButton(key: const Key('trade-touch-company-close'),
              onPressed: () => Navigator.of(context).pop(), child: const Text('閉じる')),
          ]))),
      ])));
  }
}
