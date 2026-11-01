import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../../domain/trade_document_form_draft.dart';
import '../../domain/trade_document_terms_snapshot.dart';
import '../shared/pdf_pinch_pages.dart';
import '../shared/trade_document_form_renderer.dart';
import '../shared/trade_document_touch_editor_page.dart';
import 'site_order_outgoing_body_factory.dart';
import 'site_order_outgoing_entries.dart';
import 'site_order_outgoing_journal.dart';
import 'site_order_workflow_repository.dart';

/// Returned RAM input is not an approved/sent order. A future guarded writer
/// must persist IDs, stage once, fetch the server body and obtain fresh consent.
class SiteOrderReviewedInput {
  SiteOrderReviewedInput(
    this.pending,
    Map<String, dynamic> body,
    this.connectionFingerprint,
  ) : _body = jsonEncode(body);
  final SiteOrderPendingPrepare pending;
  final String connectionFingerprint;
  final String _body;
  Map<String, dynamic> get body =>
      Map<String, dynamic>.from(jsonDecode(_body) as Map);
}

/// Source-only input/review route. No main entry, prepare, sign or send API.
/// Targets must come from a verified read-only registered directory; selection
/// is revalidated by the actual outgoingContext gateway before any preview.
class SiteOrderOutgoingEntryPage extends StatefulWidget {
  const SiteOrderOutgoingEntryPage({
    super.key,
    required this.api,
    required this.siteId,
    required this.issueDate,
    this.targets,
    this.initial = const {},
    this.initialReviewed,
    this.previewBuilder,
    this.render,
  });
  final SiteOrderWorkflowApi api;
  final String siteId, issueDate;
  @visibleForTesting
  final List<SiteOrderRegisteredTarget>? targets;
  final Map<String, String> initial;

  /// RAM-only return-to-input contents; all document/request IDs are regenerated.
  final SiteOrderReviewedInput? initialReviewed;
  @visibleForTesting
  final Widget Function(Uint8List)? previewBuilder;
  @visibleForTesting
  final Future<Uint8List> Function(Map<String, dynamic>)? render;
  @override
  State<SiteOrderOutgoingEntryPage> createState() =>
      _SiteOrderOutgoingEntryPageState();
}

class _SiteOrderOutgoingEntryPageState extends State<SiteOrderOutgoingEntryPage>
    with WidgetsBindingObserver {
  final _controllers = <String, TextEditingController>{};
  final _retirementChanges = ValueNotifier<int>(0);
  List<SiteOrderRegisteredTarget> _targets = const [];
  final _document = siteOrderRequestId(),
      _local = siteOrderRequestId(),
      _request = siteOrderRequestId();
  int _step = 0, _generation = 0;
  bool _busy = true, _retired = false, _confirming = false;
  String? _error, _trade;
  SiteOrderOutgoingEntries? _entries;
  Map<String, Object?>? _paperEdits;
  TradeDocumentFormDraft? _draft;
  SiteOrderOutgoingBodyFactory? _factory;
  SiteOrderReviewedInput? _reviewed;
  Uint8List? _pdf;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.api.addListener(_scopeChanged);
    _targets = List.unmodifiable(widget.targets ?? const []);
    final previous = widget.initialReviewed?.body;
    final firstRow = previous == null
        ? null
        : ((previous['form_fields'] as Map)['rows'] as List).first as Map;
    if (previous != null) {
      _trade = widget.initialReviewed!.pending.tradeId;
      _paperEdits = {
        for (final key in [
          'issue_date',
          'order_date',
          'work_name',
          'work_address',
          'period_start',
          'period_end',
          'payment_conditions',
          'notes',
          'intro_text',
          'acceptance_text',
          'form_fields',
          'total_amount_yen',
          'tax_amount_yen',
        ])
          key: previous[key],
      };
    }
    for (final key in SiteOrderOutgoingEntries.labels.keys) {
      final Object? previousValue;
      if (previous == null) {
        previousValue = null;
      } else if (key == 'unit_price') {
        previousValue = firstRow?['unit_price_yen'];
      } else if (key == 'quantity' || key == 'unit') {
        previousValue = firstRow?[key];
      } else {
        previousValue = previous[key];
      }
      _controllers[key] = TextEditingController(
        text:
            previousValue?.toString() ??
            widget.initial[key] ??
            (key == 'quantity'
                ? '1'
                : key == 'unit'
                ? '人日'
                : ''),
      );
    }
    try {
      if (!SiteOrderPendingPrepare.validId(widget.siteId)) {
        throw StateError('現場を確認してください。');
      }
      _validateTargets(_targets);
      _admit();
    } catch (_) {
      _retire();
    }
  }

  Future<void> _admit() async {
    try {
      await widget.api.verify();
      _require();
      if (mounted) setState(() => _busy = false);
    } catch (_) {
      _retire();
    }
  }

  void _validateTargets(List<SiteOrderRegisteredTarget> targets) {
    final ids = <String>{};
    for (final target in targets) {
      if (!SiteOrderPendingPrepare.validId(target.id) ||
          target.name.trim().isEmpty ||
          target.name.runes.length > 240 ||
          !ids.add(target.id)) {
        throw StateError('登録会社を確認してください。');
      }
    }
  }

  void _scopeChanged() {
    if (widget.api.invalidated) _retire();
  }

  void _retire() {
    if (_retired) return;
    _retired = true;
    _generation++;
    _retirementChanges.value++;
    _entries = null;
    _paperEdits = null;
    _draft = null;
    _factory = null;
    _reviewed = null;
    _pdf = null;
    for (final controller in _controllers.values) {
      controller.clear();
    }
    FocusManager.instance.primaryFocus?.unfocus();
    if (mounted) setState(() => _error = 'ログイン・会社・現場を確認して開き直してください。');
  }

  void _require() {
    if (_retired) throw StateError('入力画面を開き直してください。');
    widget.api.requireCurrent();
  }

  @override
  void didUpdateWidget(covariant SiteOrderOutgoingEntryPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.api != widget.api ||
        oldWidget.siteId != widget.siteId ||
        oldWidget.issueDate != widget.issueDate ||
        !identical(oldWidget.targets, widget.targets) ||
        !identical(oldWidget.initialReviewed, widget.initialReviewed)) {
      oldWidget.api.removeListener(_scopeChanged);
      _retire();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _retire();
  }

  Future<void> _toTargets() async {
    if (_busy || _retired) return;
    final generation = ++_generation;
    setState(() => _busy = true);
    try {
      _require();
      final entry = SiteOrderOutgoingEntries({
        for (final e in _controllers.entries) e.key: e.value.text,
      });
      entry.validate();
      FocusManager.instance.primaryFocus?.unfocus();
      await widget.api.verify();
      _require();
      final targets = widget.targets == null
          ? await widget.api.registeredOutgoingTargets(widget.siteId)
          : _targets;
      _require();
      _validateTargets(targets);
      if (!mounted || generation != _generation) return;
      setState(() {
        _targets = List.unmodifiable(targets);
        if (!_targets.any((t) => t.id == _trade)) _trade = null;
        _entries = entry;
        _step = 1;
        _error = null;
      });
    } catch (error) {
      if (mounted && !_retired) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _backToInput() {
    if (_busy || _retired) return;
    final draft = _draft;
    if (draft != null) {
      final body = draft.payload,
          row =
              ((draft.payload['form_fields'] as Map)['rows'] as List).first
                  as Map;
      _paperEdits = {
        for (final key in [
          'issue_date',
          'order_date',
          'work_name',
          'work_address',
          'period_start',
          'period_end',
          'payment_conditions',
          'notes',
          'intro_text',
          'acceptance_text',
          'form_fields',
          'total_amount_yen',
          'tax_amount_yen',
        ])
          key: body[key],
      };
      for (final key in [
        'work_name',
        'work_address',
        'period_start',
        'period_end',
        'total_amount_yen',
        'tax_amount_yen',
      ]) {
        _controllers[key]!.text = body[key]?.toString() ?? '';
      }
      _controllers['quantity']!.text = row['quantity']?.toString() ?? '';
      _controllers['unit']!.text = row['unit']?.toString() ?? '';
      _controllers['unit_price']!.text =
          row['unit_price_yen']?.toString() ?? '';
    }
    setState(() {
      _generation++;
      _step = 0;
      _draft = null;
      _factory = null;
      _reviewed = null;
      _pdf = null;
      _error = null;
    });
  }

  Future<void> _bindAndPreview() async {
    if (_busy || _retired || _trade == null || _entries == null) return;
    final generation = ++_generation, trade = _trade!, entries = _entries!;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.api.verify();
      _require();
      final context = await widget.api.outgoingContext(widget.siteId, trade);
      _require();
      if (!mounted || generation != _generation) return;
      final pending = SiteOrderPendingPrepare(
        siteId: widget.siteId,
        documentId: _document,
        localId: _local,
        tradeId: trade,
        requestId: _request,
        sessionId: context['session_id'] as String,
      );
      final factory = SiteOrderOutgoingBodyFactory(
        verifiedContext: context,
        actorId: context['actor_id'] as String,
        companyId: context['company_id'] as String,
        pending: pending,
        termsSnapshot: TradeDocumentTermsSnapshot.reference,
      );
      final draft = entries.applyTo(
        factory
            .newEditor(issueDate: widget.issueDate)
            .withChanges(_paperEdits ?? {}),
      );
      final canonical = factory.canonicalForPrepare(draft);
      final bytes =
          await (widget.render ?? TradeDocumentFormRenderer.canonical)(
            draft.payload,
          );
      await widget.api.verify();
      _require();
      if (!mounted || generation != _generation) return;
      if (bytes.length < 5 ||
          ascii.decode(bytes.sublist(0, 5), allowInvalid: true) != '%PDF-') {
        throw StateError('PDFを確認できません。');
      }
      setState(() {
        _factory = factory;
        _draft = draft;
        _pdf = bytes;
        _step = 2;
        _reviewed = SiteOrderReviewedInput(
          pending,
          canonical,
          context['connection_fingerprint'] as String,
        );
      });
    } catch (error) {
      if (mounted && !_retired && generation == _generation) {
        setState(() => _error = error.toString());
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _editPaper() async {
    if (_busy || _retired || _draft == null || _factory == null) return;
    final factory = _factory!, reviewed = _reviewed!, generation = _generation;
    setState(() => _busy = true);
    try {
      await widget.api.verify();
      _require();
      if (!mounted) return;
      await Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (_) => TradeDocumentTouchEditorPage(
            initial: _draft!,
            requireScope: _require,
            scopeChanges: widget.api,
            canEdit: true,
            allowExtendedFields: true,
            buildPreview: (body) async {
              _require();
              factory.canonicalForPrepare(
                TradeDocumentFormDraft.fromPayload(
                  body,
                  allowAmountEditing: true,
                ),
              );
              final bytes =
                  await (widget.render ?? TradeDocumentFormRenderer.canonical)(
                    body,
                  );
              _require();
              return bytes;
            },
            onSave: (body) async {
              _require();
              if (generation != _generation) throw StateError('入力を確認してください。');
              final draft = TradeDocumentFormDraft.fromPayload(
                    body,
                    allowAmountEditing: true,
                  ),
                  canonical = factory.canonicalForPrepare(draft);
              _requirePrice(canonical);
              final bytes =
                  await (widget.render ?? TradeDocumentFormRenderer.canonical)(
                    draft.payload,
                  );
              await widget.api.verify();
              _require();
              if (!mounted || generation != _generation) return;
              setState(() {
                _draft = draft;
                _pdf = bytes;
                _reviewed = SiteOrderReviewedInput(
                  reviewed.pending,
                  canonical,
                  reviewed.connectionFingerprint,
                );
              });
            },
          ),
        ),
      );
      _require();
    } catch (error) {
      if (mounted && !_retired) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirmReview() async {
    if (_busy || _retired || _reviewed == null || _draft == null) return;
    final reviewed = _reviewed!, body = reviewed.body;
    final form = body['form_fields'] as Map,
        row = (form['rows'] as List).first as Map;
    try {
      _requirePrice(body);
    } catch (error) {
      setState(() => _error = error.toString());
      return;
    }
    setState(() {
      _busy = true;
      _confirming = true;
    });
    final confirmed = await showDialog<bool>(
      context: context,
      useRootNavigator: false,
      builder: (dialog) => AnimatedBuilder(
        animation: _retirementChanges,
        builder: (_, __) => _retired
            ? AlertDialog(
                title: const Text('画面を開き直してください。'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(dialog, false),
                    child: const Text('閉じる'),
                  ),
                ],
              )
            : AlertDialog(
                title: const Text('注文内容の確認'),
                content: Text(
                  '${body['work_name']}\n${(body['counterparty'] as Map)['name']}\n単価 ${row['unit_price_yen']}円／${row['unit']}\n発注金額 ${body['total_amount_yen']}円',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(dialog, false),
                    child: const Text('入力画面に戻る'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(dialog, true),
                    child: const Text('内容を確認'),
                  ),
                ],
              ),
      ),
    );
    if (!mounted || _retired) return;
    setState(() => _confirming = false);
    if (confirmed != true) {
      setState(() => _busy = false);
      _backToInput();
      return;
    }
    try {
      await widget.api.verify();
      _require();
      if (mounted) Navigator.pop(context, reviewed);
    } catch (_) {
      _retire();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _requirePrice(Map<String, dynamic> body) {
    final row = ((body['form_fields'] as Map)['rows'] as List).first as Map;
    if (row['unit_price_yen'] is! int ||
        row['unit'] is! String ||
        (row['unit'] as String).trim().isEmpty) {
      throw const FormatException('単価・単位を入力してください。');
    }
  }

  @override
  void dispose() {
    _retired = true;
    _generation++;
    WidgetsBinding.instance.removeObserver(this);
    widget.api.removeListener(_scopeChanged);
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    _entries = null;
    _paperEdits = null;
    _draft = null;
    _factory = null;
    _reviewed = null;
    _pdf = null;
    _retirementChanges.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('注文書の入力'),
      actions: [
        if (_step == 0)
          IconButton(
            tooltip: 'キーボードを閉じる',
            onPressed: () => FocusManager.instance.primaryFocus?.unfocus(),
            icon: const Icon(Icons.keyboard_hide_outlined),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('閉じる'),
        ),
      ],
    ),
    body: _retired
        ? Center(child: Text(_error ?? '開き直してください。'))
        : Column(
            children: [
              if (_busy && !_confirming) const LinearProgressIndicator(),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(_error!),
                ),
              Expanded(
                child: _step == 0
                    ? GestureDetector(
                        onTap: () =>
                            FocusManager.instance.primaryFocus?.unfocus(),
                        child: ListView(
                          padding: const EdgeInsets.all(16),
                          children: [
                            for (final entry
                                in SiteOrderOutgoingEntries.labels.entries)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: TextField(
                                  key: ValueKey('outgoing-input:${entry.key}'),
                                  controller: _controllers[entry.key],
                                  enabled: !_busy,
                                  decoration: InputDecoration(
                                    labelText: entry.value,
                                  ),
                                  textInputAction: TextInputAction.done,
                                  keyboardType:
                                      const {
                                        'unit_price',
                                        'total_amount_yen',
                                        'tax_amount_yen',
                                        'quantity',
                                      }.contains(entry.key)
                                      ? TextInputType.number
                                      : TextInputType.text,
                                  onSubmitted: (_) => FocusManager
                                      .instance
                                      .primaryFocus
                                      ?.unfocus(),
                                ),
                              ),
                            FilledButton(
                              onPressed: _busy ? null : _toTargets,
                              child: const Text('入力を確定'),
                            ),
                          ],
                        ),
                      )
                    : _step == 1
                    ? ListView(
                        padding: const EdgeInsets.all(16),
                        children: [
                          if (_targets.isEmpty)
                            const Text('共有先に使える連携済み協力会社はありません。'),
                          DropdownButtonFormField<String>(
                            initialValue: _trade,
                            decoration: const InputDecoration(
                              labelText: '登録済み協力会社',
                            ),
                            items: [
                              for (final target in _targets)
                                DropdownMenuItem(
                                  value: target.id,
                                  child: Text(target.name),
                                ),
                            ],
                            onChanged: _busy
                                ? null
                                : (value) => setState(() => _trade = value),
                          ),
                          const SizedBox(height: 16),
                          FilledButton(
                            onPressed: _busy || _trade == null
                                ? null
                                : _bindAndPreview,
                            child: const Text('注文書を確認'),
                          ),
                          TextButton(
                            onPressed: _busy ? null : _backToInput,
                            child: const Text('入力画面に戻る'),
                          ),
                        ],
                      )
                    : Column(
                        children: [
                          Expanded(
                            child:
                                widget.previewBuilder?.call(_pdf!) ??
                                PdfPreview.builder(
                                  build: (_) async {
                                    _require();
                                    return _pdf!;
                                  },
                                  canChangeOrientation: false,
                                  canChangePageFormat: false,
                                  allowPrinting: false,
                                  allowSharing: false,
                                  canDebug: false,
                                  pagesBuilder: (context, pages) =>
                                      PdfPinchPages(pages: pages),
                                ),
                          ),
                          Wrap(
                            spacing: 8,
                            children: [
                              TextButton(
                                onPressed: _busy ? null : _backToInput,
                                child: const Text('入力画面に戻る'),
                              ),
                              TextButton(
                                onPressed: _busy ? null : _editPaper,
                                child: const Text('プレビューを編集'),
                              ),
                              FilledButton(
                                onPressed: _busy ? null : _confirmReview,
                                child: const Text('注文内容を確認'),
                              ),
                            ],
                          ),
                        ],
                      ),
              ),
            ],
          ),
  );
}
