import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../shared/pdf_pinch_pages.dart';
import 'site_order_original_review.dart';
import 'site_order_delivery_journal.dart';
import 'site_order_outgoing_consent.dart';
import 'site_order_outgoing_execution.dart';
import 'site_order_workflow_repository.dart';

class SiteOrderOriginalReviewPage extends StatefulWidget {
  const SiteOrderOriginalReviewPage({
    super.key,
    required this.api,
    required this.reference,
    required this.jobId,
    required this.recipientCompanyId,
    this.previewBuilder,
  });
  final SiteOrderWorkflowApi api;
  final SiteOrderConsentReference reference;
  final String jobId, recipientCompanyId;
  @visibleForTesting
  final Widget Function(Uint8List)? previewBuilder;
  @override
  State<SiteOrderOriginalReviewPage> createState() =>
      _SiteOrderOriginalReviewPageState();
}

class _SiteOrderOriginalReviewPageState
    extends State<SiteOrderOriginalReviewPage>
    with WidgetsBindingObserver {
  bool _busy = true,
      _invalid = false,
      _hidden = false,
      _allowed = false,
      _agreed = false;
  bool _registerStarted = false, _shareStarted = false;
  int _generation = 0;
  final _dialogScope = ValueNotifier<int>(0);
  String _message = '保存状態を確認しています。';
  SiteOrderExecutionObservation? _status;
  SiteOrderOriginalReview? _review;
  Uint8List? _bytes;
  @override
  void initState() {
    super.initState();
    widget.api.addListener(_scope);
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void didUpdateWidget(covariant SiteOrderOriginalReviewPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.api != widget.api ||
        jsonEncode(oldWidget.reference.toJson()) !=
            jsonEncode(widget.reference.toJson()) ||
        oldWidget.jobId != widget.jobId ||
        oldWidget.recipientCompanyId != widget.recipientCompanyId) {
      oldWidget.api.removeListener(_scope);
      // Never adopt another purpose/API into an existing preview or dialog.
      _generation++;
      _invalid = true;
      _review = null;
      _status = null;
      _bytes = null;
      _agreed = false;
      _allowed = false;
      _dialogScope.value++;
    }
  }

  @override
  void dispose() {
    widget.api.removeListener(_scope);
    _dialogScope.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _scope() {
    try {
      widget.api.requireCurrent();
    } catch (_) {
      if (mounted) {
        setState(() {
          _generation++;
          _invalid = true;
          _dialogScope.value++;
          _review = null;
          _bytes = null;
          _status = null;
          _agreed = false;
        });
      }
    }
  }

  void _current(int generation) {
    widget.api.requireCurrent();
    if (!mounted || _invalid || _hidden || generation != _generation) {
      throw StateError('scope retired');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      if (mounted) {
        setState(() {
          _generation++;
          _hidden = true;
          _dialogScope.value++;
          _review = null;
          _bytes = null;
          _agreed = false;
        });
      }
    } else if (mounted && !_invalid) {
      setState(() => _hidden = false);
      _load();
    }
  }

  Future<void> _load() async {
    final generation = ++_generation;
    if (mounted) {
      setState(() {
        _busy = true;
        _agreed = false;
        _review = null;
        _bytes = null;
      });
    }
    try {
      final status = await widget.api.inspectOutgoingExecution(
        widget.reference,
        jobId: widget.jobId,
        recipientCompanyId: widget.recipientCompanyId,
      );
      _current(generation);
      SiteOrderOriginalReview? review;
      Uint8List? bytes;
      if (status.originalSaved) {
        review = await widget.api.reviewOutgoingOriginal(
          widget.reference,
          jobId: widget.jobId,
          recipientCompanyId: widget.recipientCompanyId,
        );
        _current(generation);
        bytes = await widget.api.outgoingOriginalBytes(
          widget.reference,
          review,
        );
        _current(generation);
        // The immutable metadata and returned bytes must agree before display.
        bytes = review.verifyBytes(bytes);
      }
      final allowed = await widget.api.canMutateOutgoingReference(
        widget.reference,
      );
      _current(generation);
      setState(() {
        _status = review?.status ?? status;
        _review = review;
        _bytes = bytes;
        _allowed = allowed;
        _message = (_status!.recipientStored)
            ? '相手会社の受信箱に保存されています。相手の承認は未確認です。'
            : _status!.unresolved
            ? '共有結果が未解決です。再送せず状態を照会してください。'
            : _status!.originalSaved
            ? '保存済み原本と共有先・条件を確認してください。'
            : '原本はまだ確認できません。';
      });
    } catch (_) {
      if (mounted && !_invalid && generation == _generation) {
        setState(() {
          _status = null;
          _review = null;
          _bytes = null;
          _agreed = false;
          _allowed = false;
          _message = '保存状態を確認できません。再送せず照会してください。';
        });
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _register() async {
    if (_busy ||
        _invalid ||
        _hidden ||
        !_allowed ||
        _registerStarted ||
        _status?.originalSaved != false) {
      return;
    }
    final generation = _generation;
    setState(() {
      _busy = true;
      _registerStarted = true;
      _agreed = false;
    });
    try {
      if (!await widget.api.canMutateOutgoingReference(widget.reference)) {
        throw StateError('disabled');
      }
      _current(generation);
      await widget.api.registerOutgoingOriginal(
        widget.reference,
        jobId: widget.jobId,
        recipientCompanyId: widget.recipientCompanyId,
        confirmed: true,
      );
      _current(generation);
      await _load();
    } catch (_) {
      if (mounted && !_invalid) {
        setState(() => _message = '原本保存の結果を照会してください。同じ処理は再実行しません。');
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Widget _summary(Map<String, dynamic> body) {
    final rows = (body['form_fields'] is Map
        ? (body['form_fields'] as Map)['rows']
        : null);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('工事名称：${body['work_name'] ?? '確認できません'}'),
        Text(
          '工期：${body['period_start'] ?? '未設定'} ～ ${body['period_end'] ?? '未設定'}',
        ),
        Text('共有先：${(body['counterparty'] as Map)['name'] ?? '確認できません'}'),
        Text(body['total_amount_yen'] is int && (body['total_amount_yen'] as int) >= 0
          ? '発注金額（総額）：${_money(body['total_amount_yen'])}円'
          : '発注金額（総額）：未設定（送信できません）'),
        if (rows is List)
          for (final row in rows.whereType<Map>().where(
            (r) =>
                [
                  'item',
                  'quantity',
                  'unit',
                  'note',
                ].any((k) => '${r[k] ?? ''}'.trim().isNotEmpty) ||
                r['unit_price_yen'] != null ||
                r['amount_yen'] != null,
          ))
            Text(
              '単価：${row['unit_price_yen'] ?? '未設定'}円 ／ ${row['unit'] ?? '未設定'}　数量：${row['quantity'] ?? '未設定'}',
            ),
        if (rows is! List) const Text('単価・単位：原本で確認してください。'),
      ],
    );
  }

  String _money(Object? value) => value is int && value >= 0
      ? value.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',')
      : '確認できません';

  String _sendQuestion(Map<String, dynamic> body) =>
      '${body['work_name']}を${(body['counterparty'] as Map)['name']}へ'
      '${_money(body['total_amount_yen'])}円で送りますが良いですか？';

  bool get _completeTerms {
    final body = _review?.body;
    if (body == null || body['form_fields'] is! Map ||
        body['work_name'] is! String || (body['work_name'] as String).trim().isEmpty ||
        body['counterparty'] is! Map ||
        (body['counterparty'] as Map)['name'] is! String ||
        ((body['counterparty'] as Map)['name'] as String).trim().isEmpty ||
        body['total_amount_yen'] is! int || (body['total_amount_yen'] as int) < 0) {
      return false;
    }
    final rows = (body['form_fields'] as Map)['rows'];
    if (rows is! List || rows.isEmpty || rows.any((r) => r is! Map)) {
      return false;
    }
    final active = rows
        .where(
          (r) =>
              [
                'item',
                'quantity',
                'unit',
                'note',
              ].any((k) => '${r[k] ?? ''}'.trim().isNotEmpty) ||
              r['unit_price_yen'] != null ||
              r['amount_yen'] != null,
        )
        .toList();
    if (active.isEmpty) {
      return false;
    }
    return active.every(
      (row) =>
          row is Map &&
          row['unit_price_yen'] is int &&
          (row['unit_price_yen'] as int) >= 0 &&
          row['unit'] is String &&
          (row['unit'] as String).trim().isNotEmpty &&
          num.tryParse('${row['quantity']}') != null &&
          num.parse('${row['quantity']}') > 0,
    );
  }

  Future<void> _share() async {
    if (_busy ||
        _invalid ||
        _hidden ||
        !_allowed ||
        !_agreed ||
        !_completeTerms ||
        _shareStarted ||
        _review?.sameSession != true ||
        _bytes == null ||
        _status?.sharingState != 'not_observed') {
      return;
    }
    final generation = _generation, review = _review!;
    setState(() => _agreed = false);
    final confirmed = await showDialog<bool>(
      context: context,
      useRootNavigator: false,
      builder: (dialog) => AnimatedBuilder(
        animation: Listenable.merge([widget.api, _dialogScope]),
        builder: (_, __) => _invalid || _hidden || generation != _generation
            ? AlertDialog(
                title: const Text('表示を閉じました'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(dialog, false),
                    child: const Text('閉じる'),
                  ),
                ],
              )
            : AlertDialog(
                title: const Text('送信内容の最終確認'),
                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_sendQuestion(review.body),
                        key: const Key('site-order-send-question'),
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 12),
                      _summary(review.body),
                      const SizedBox(height: 12),
                      const Text('送る協力会社と金額があっていればこのまま送ります。\n現場情報と保存済みの押印注文書をセットで送ります。'),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(dialog, false),
                    child: const Text('原本の確認に戻る'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(dialog, true),
                    child: const Text('この会社・金額で送る'),
                  ),
                ],
              ),
      ),
    );
    if (confirmed != true ||
        !mounted ||
        _invalid ||
        _hidden ||
        generation != _generation) {
      return;
    }
    setState(() {
      _busy = true;
      _shareStarted = true;
      _agreed = false;
    });
    try {
      if (!await widget.api.canMutateOutgoingReference(widget.reference)) {
        throw StateError('disabled');
      }
      _current(generation);
      await widget.api.shareOutgoingOriginal(
        widget.reference,
        jobId: widget.jobId,
        recipientCompanyId: widget.recipientCompanyId,
        confirmed: true,
      );
      _current(generation);
      await _load();
    } catch (_) {
      if (mounted && !_invalid) {
        setState(() => _message = '共有結果が未確認です。再送せず状態を照会してください。');
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _recordDelivery() async {
    if (_busy ||
        _invalid ||
        _hidden ||
        _status?.recipientStored != true ||
        _bytes == null) {
      return;
    }
    final generation = _generation;
    setState(() => _busy = true);
    try {
      final record = await widget.api.recordOutgoingDelivery(
        widget.reference,
        jobId: widget.jobId,
        recipientCompanyId: widget.recipientCompanyId,
      );
      _current(generation);
      if (mounted) {
        Navigator.pop<SiteOrderDeliveryRecord>(context, record);
      }
    } catch (_) {
      if (mounted && !_invalid) {
        setState(() => _message = '共有結果の保管が未確認です。原記録を保持し、状態を再照会してください。');
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(_review?.body['work_name']?.toString() ?? '注文書の原本・共有確認'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('閉じる'),
        ),
      ],
    ),
    body: _invalid || _hidden
        ? const Center(child: Text('表示を閉じています。会社・ログイン状態を確認してください。'))
        : Column(
            children: [
              Padding(padding: const EdgeInsets.all(12), child: Text(_message)),
              if (_review != null)
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: _summary(_review!.body),
                ),
              if (_bytes != null)
                Expanded(
                  child:
                      widget.previewBuilder?.call(_bytes!) ??
                      PdfPreview.builder(
                        build: (_) async {
                          _current(_generation);
                          return _bytes!;
                        },
                        canChangeOrientation: false,
                        canChangePageFormat: false,
                        allowPrinting: false,
                        allowSharing: false,
                        canDebug: false,
                        pagesBuilder: (context, pages) =>
                            PdfPinchPages(pages: pages),
                      ),
                )
              else
                const Spacer(),
              if (_review != null &&
                  _review!.sameSession &&
                  _allowed &&
                  _status?.sharingState == 'not_observed' &&
                  !_shareStarted)
                CheckboxListTile(
                  value: _agreed,
                  onChanged: _busy
                      ? null
                      : (v) => setState(() => _agreed = v == true),
                  title: const Text('押印原本、工期、単価・単位、共有先を確認しました。'),
                ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (_status?.originalSaved == false &&
                        _allowed &&
                        !_registerStarted)
                      FilledButton(
                        onPressed: _busy ? null : _register,
                        child: const Text('確認済み内容の原本を保存'),
                      ),
                    if (_review?.sameSession == true &&
                        _allowed &&
                        _status?.sharingState == 'not_observed' &&
                        !_shareStarted)
                      FilledButton(
                        onPressed: _busy || !_agreed || !_completeTerms
                            ? null
                            : _share,
                        child: const Text('共有内容を最終確認'),
                      ),
                    if (_status?.recipientStored == true && _bytes != null)
                      FilledButton(
                        onPressed: _busy ? null : _recordDelivery,
                        child: const Text('共有結果を保管して閉じる'),
                      ),
                    OutlinedButton(
                      onPressed: _busy ? null : _load,
                      child: const Text('保存・共有結果を照会'),
                    ),
                  ],
                ),
              ),
              if (_review != null && !_completeTerms)
                const Padding(
                  padding: EdgeInsets.all(8),
                  child: Text('単価・単位・数量を確認できないため共有できません。正規の修正・再確認が必要です。'),
                ),
              if (_busy) const LinearProgressIndicator(),
            ],
          ),
  );
}
