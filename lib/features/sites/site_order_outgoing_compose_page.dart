import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../shared/pdf_pinch_pages.dart';
import 'site_order_outgoing_consent.dart';
import 'site_order_outgoing_consent_preview.dart';
import 'site_order_outgoing_entry_page.dart';
import 'site_order_outgoing_recovery_page.dart';
import 'site_order_workflow_repository.dart';
import 'site_order_original_review_page.dart';
import 'site_order_delivery_journal.dart';

/// Input -> server prepare -> fresh server preview -> explicit issuer consent.
/// Original registration and sharing require a separate persisted-original review.
class SiteOrderOutgoingComposePage extends StatefulWidget {
  const SiteOrderOutgoingComposePage({
    super.key,
    required this.api,
    required this.siteId,
    required this.issueDate,
    this.previewBuilder,
    this.inputBuilder,
  });
  final SiteOrderWorkflowApi api;
  final String siteId, issueDate;
  @visibleForTesting
  final Widget Function(Uint8List)? previewBuilder;
  @visibleForTesting
  final Widget Function(SiteOrderReviewedInput?)? inputBuilder;
  @override
  State<SiteOrderOutgoingComposePage> createState() =>
      _SiteOrderOutgoingComposePageState();
}

class _SiteOrderOutgoingComposePageState
    extends State<SiteOrderOutgoingComposePage>
    with WidgetsBindingObserver {
  final _scopeChanges = ValueNotifier<int>(0);
  bool _busy = true, _retired = false, _allowed = false, _pending = false;
  bool _prepareStarted = false, _decisionStarted = false, _agreed = false;
  bool _needsFreshInput = false;
  String? _preparedJobId;
  int _generation = 0;
  String? _message;
  SiteOrderReviewedInput? _input;
  SiteOrderOutgoingConsentPreview? _preview;
  SiteOrderConsentReference? _reference;
  Uint8List? _pdf;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.api.addListener(_scopeChanged);
    _admit();
  }

  Future<void> _admit() async {
    try {
      final allowed = await widget.api.canCreateOutgoing();
      final prepares = await widget.api.pendingOutgoing(widget.siteId);
      final decisions = await widget.api.pendingOutgoingConsents(widget.siteId);
      _require();
      if (!mounted) {
        return;
      }
      setState(() {
        _allowed = allowed;
        _pending = prepares.isNotEmpty || decisions.isNotEmpty;
        if (!allowed) {
          _message = '現在、注文書の新規作成は利用できません。履歴と保存状態は確認できます。';
        }
        if (_pending) {
          _message = '確認待ちの注文があります。先に保存状態を確認してください。';
        }
      });
    } catch (_) {
      if (mounted && !_retired) {
        setState(() => _message = '利用状態を確認できません。保存状態を確認して開き直してください。');
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  void _require() {
    if (_retired) {
      throw StateError('画面を開き直してください。');
    }
    widget.api.requireCurrent();
  }

  void _scopeChanged() {
    if (widget.api.invalidated) {
      _retire();
    }
  }

  void _retire() {
    if (_retired) {
      return;
    }
    _retired = true;
    _generation++;
    _scopeChanges.value++;
    _input = null;
    _preview = null;
    _pdf = null;
    _reference = null;
    _agreed = false;
    FocusManager.instance.primaryFocus?.unfocus();
    if (mounted) {
      setState(() => _message = 'ログイン・会社・現場の状態が変わりました。保存状態から確認してください。');
    }
  }

  @override
  void didUpdateWidget(covariant SiteOrderOutgoingComposePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.api != widget.api ||
        oldWidget.siteId != widget.siteId ||
        oldWidget.issueDate != widget.issueDate) {
      oldWidget.api.removeListener(_scopeChanged);
      _retire();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      _retire();
    }
  }

  Future<void> _openInput() async {
    if (_busy || _retired || !_allowed || _pending || _prepareStarted) {
      return;
    }
    final generation = ++_generation;
    setState(() => _busy = true);
    try {
      await widget.api.verify();
      if (!await widget.api.canCreateOutgoing()) {
        if (mounted) {
          setState(() {
            _allowed = false;
            _message = '現在、注文書の新規作成は利用できません。';
          });
        }
        return;
      }
      _require();
      if (!mounted) {
        return;
      }
      final result = await Navigator.push<SiteOrderReviewedInput>(
        context,
        MaterialPageRoute(
          builder: (_) =>
              widget.inputBuilder?.call(_input) ??
              SiteOrderOutgoingEntryPage(
                api: widget.api,
                siteId: widget.siteId,
                issueDate: widget.issueDate,
                initialReviewed: _input,
                previewBuilder: widget.previewBuilder,
              ),
        ),
      );
      _require();
      if (!mounted || generation != _generation || result == null) {
        return;
      }
      if (result.pending.siteId != widget.siteId) {
        throw StateError('現場が変わりました。');
      }
      final previous = _input;
      if (_needsFreshInput &&
          previous != null &&
          (result.pending.documentId == previous.pending.documentId ||
              result.pending.localId == previous.pending.localId ||
              result.pending.requestId == previous.pending.requestId)) {
        throw StateError('新しい入力確認が必要です。');
      }

      setState(() {
        _input = result;
        _needsFreshInput = false;
        _message = null;
        _preview = null;
        _pdf = null;
        _agreed = false;
      });
    } catch (_) {
      if (mounted && !_retired) {
        setState(() => _message = '入力内容を確認できません。画面を開き直してください。');
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _prepare() async {
    if (_busy ||
        _retired ||
        _input == null ||
        _prepareStarted ||
        _needsFreshInput ||
        !_allowed) {
      return;
    }
    final input = _input!;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      if (!await widget.api.canCreateOutgoing()) {
        if (mounted) {
          setState(() {
            _allowed = false;
            _message = '現在、注文書の新規作成は利用できません。';
          });
        }
        return;
      }
      _require();
      _prepareStarted = true;
      await widget.api.prepareUnsignedOutgoing(
        input.pending,
        input.body,
        input.connectionFingerprint,
      );
      _require();
      await _loadPreview();
    } catch (_) {
      if (mounted && !_retired) {
        setState(() => _message = '準備結果を確認できません。再実行せず保存状態を照会してください。');
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _loadPreview() async {
    final input = _input!, generation = _generation;
    final preview = await widget.api.previewUnsignedOutgoing(input.pending);
    _require();
    if (!preview.matchesPreparedBody(input.body)) {
      throw StateError('保存内容が入力と一致しません。');
    }
    final pdf = await widget.api.renderUnsignedOutgoing(preview);
    _require();
    if (pdf.length < 5 || ascii.decode(pdf.take(5).toList()) != '%PDF-') {
      throw StateError('表示を確認できません。');
    }
    if (!mounted || generation != _generation) {
      return;
    }
    setState(() {
      _preview = preview;
      _pdf = pdf;
      _agreed = false;
      _message = null;
    });
  }

  Future<void> _checkPrepare() async {
    if (_busy ||
        _retired ||
        _input == null ||
        !_prepareStarted ||
        _decisionStarted) {
      return;
    }
    setState(() => _busy = true);
    try {
      final state = await widget.api.inspectUnsignedForReview(_input!.pending);
      _require();
      if (state == 'prepared_review_required') {
        await _loadPreview();
      } else if (state == 'retired') {
        _resetRetired();
      } else if (mounted) {
        setState(() => _message = '結果はまだ確定できません。再実行せず記録を保持しています。');
      }
    } catch (_) {
      if (mounted && !_retired) {
        setState(() => _message = '保存状態を確認できません。再実行せず記録を保持しています。');
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  void _resetRetired() {
    if (!mounted || _retired) {
      return;
    }
    setState(() {
      _prepareStarted = false;
      _needsFreshInput = true;
      _preview = null;
      _pdf = null;
      _agreed = false;
      _message = '未確定の準備を停止しました。入力内容を引き継いで編集できます。';
    });
  }

  Future<void> _backToInput() async {
    if (_busy || _retired || _decisionStarted) {
      return;
    }
    if (!_prepareStarted) {
      await _openInput();
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      useRootNavigator: false,
      builder: (dialog) => AnimatedBuilder(
        animation: _scopeChanges,
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
                title: const Text('入力画面に戻る'),
                content: const Text(
                  '未確定の準備を停止して入力に戻ります。入力内容は引き継ぎます。送信済みの注文の取消ではありません。',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(dialog, false),
                    child: const Text('戻る'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(dialog, true),
                    child: const Text('準備を停止して入力へ'),
                  ),
                ],
              ),
      ),
    );
    if (confirmed != true || !mounted || _retired) {
      return;
    }
    setState(() => _busy = true);
    try {
      final state = await widget.api.retireOutgoing(
        _input!.pending,
        confirmed: true,
      );
      _require();
      if (state != 'retired') {
        throw StateError('準備停止を確認できません。');
      }
      _resetRetired();
    } catch (_) {
      if (mounted && !_retired) {
        setState(() {
          _preview = null;
          _pdf = null;
          _agreed = false;
          _message = '準備停止を確認できません。入力へ戻らず記録を保持しています。';
        });
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
    if (!_retired && !_prepareStarted) {
      await _openInput();
    }
  }

  Future<void> _confirm() async {
    if (_busy ||
        _retired ||
        !_agreed ||
        _preview == null ||
        _input == null ||
        _decisionStarted ||
        !_allowed) {
      return;
    }
    setState(() => _busy = true);
    try {
      if (!await widget.api.canCreateOutgoing()) {
        if (mounted && !_retired) {
          setState(() {
            _allowed = false;
            _busy = false;
            _agreed = false;
            _message = '現在、押印内容の新規確定は利用できません。';
          });
        }
        return;
      }
      _require();
    } catch (_) {
      if (mounted && !_retired) {
        setState(() {
          _busy = false;
          _agreed = false;
          _message = '利用状態を確認できません。開き直してください。';
        });
      }
      return;
    }
    if (!mounted || _retired) {
      return;
    }
    final reference = SiteOrderConsentReference.fromPreview(
      _input!.pending,
      _preview!,
      siteOrderRequestId(),
    );
    _reference = reference;
    _decisionStarted = true;
    setState(() => _busy = true);
    try {
      final result = await widget.api.confirmUnsignedOutgoing(
        reference,
        confirmed: true,
      );
      _require();
      if (mounted) {
        setState(() {
          _preparedJobId = result.jobId;
          _message = result.observed
              ? '押印内容の確認を保存しました。原本・共有の確認へ進めます。'
              : '保存結果は未確認です。再実行せず状態を照会してください。';
        });
      }
    } catch (_) {
      if (mounted && !_retired) {
        setState(() => _message = '押印確認の保存結果が不明です。再実行せず状態を照会してください。');
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _checkDecision() async {
    if (_busy || _retired || _reference == null) {
      return;
    }
    setState(() => _busy = true);
    try {
      final result = await widget.api.inspectOutgoingConsent(_reference!);
      _require();
      if (mounted) {
        setState(() {
          _preparedJobId = result.jobId;
          _message = result.observed
              ? '押印内容の確認を保存しています。原本・共有状態は次の画面で確認してください。'
              : '保存結果は未確認です。再実行せず記録を保持しています。';
        });
      }
    } catch (_) {
      if (mounted && !_retired) {
        setState(() => _message = '保存結果を確認できません。再実行せず記録を保持しています。');
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _openRecovery() async {
    if (_busy || _retired || !mounted) {
      return;
    }
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => SiteOrderOutgoingRecoveryPage(
          api: widget.api,
          siteId: widget.siteId,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _retired = true;
    _generation++;
    WidgetsBinding.instance.removeObserver(this);
    widget.api.removeListener(_scopeChanged);
    _input = null;
    _preview = null;
    _pdf = null;
    _reference = null;
    _scopeChanges.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('注文書の作成'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('閉じる'),
        ),
      ],
    ),
    body: _retired
        ? Center(child: Text(_message ?? '画面を開き直してください。'))
        : Column(
            children: [
              if (_busy) const LinearProgressIndicator(),
              if (_message != null)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(_message!),
                ),
              if (_pdf != null)
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
                )
              else
                Expanded(
                  child: Center(
                    child: Text(
                      _input == null
                          ? '工事内容を入力し、登録済み協力会社を選んでください。'
                          : '入力した内容を保存し、会社の角印を含む内容を確認します。',
                    ),
                  ),
                ),
              if (_preview != null && !_decisionStarted)
                CheckboxListTile(
                  value: _agreed,
                  onChanged: _busy || !_allowed
                      ? null
                      : (value) => setState(() => _agreed = value == true),
                  title: const Text('内容と自社の角印を確認し、この内容での押印に同意します。'),
                ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (!_prepareStarted && _allowed && !_pending)
                      FilledButton(
                        onPressed: _busy ? null : _openInput,
                        child: Text(_input == null ? '注文書を入力' : '入力画面に戻る'),
                      ),
                    if (_input != null &&
                        !_prepareStarted &&
                        !_needsFreshInput &&
                        _allowed)
                      FilledButton(
                        onPressed: _busy ? null : _prepare,
                        child: const Text('押印前の内容を確認'),
                      ),
                    if (_prepareStarted && !_decisionStarted)
                      TextButton(
                        onPressed: _busy ? null : _backToInput,
                        child: const Text('入力画面に戻る'),
                      ),
                    if (_prepareStarted &&
                        !_decisionStarted &&
                        _preview == null)
                      OutlinedButton(
                        onPressed: _busy ? null : _checkPrepare,
                        child: const Text('準備結果を照会'),
                      ),
                    if (_preview != null && !_decisionStarted)
                      FilledButton(
                        onPressed: _busy || !_allowed || !_agreed
                            ? null
                            : _confirm,
                        child: const Text('押印内容を確定'),
                      ),
                    if (_preparedJobId != null &&
                        _reference != null &&
                        _preview != null)
                      FilledButton(
                        onPressed: _busy
                            ? null
                            : () async {
                                _require();
                                final record =
                                    await Navigator.push<
                                      SiteOrderDeliveryRecord
                                    >(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) =>
                                            SiteOrderOriginalReviewPage(
                                              api: widget.api,
                                              reference: _reference!,
                                              jobId: _preparedJobId!,
                                              recipientCompanyId:
                                                  _preview!.recipientCompanyId,
                                            ),
                                      ),
                                    );
                                if (record != null && mounted && !_retired) {
                                  try {
                                    _require();
                                  } catch (_) {
                                    return;
                                  }
                                  if (jsonEncode(record.reference.toJson()) ==
                                          jsonEncode(_reference!.toJson()) &&
                                      record.jobId == _preparedJobId &&
                                      record.recipientCompanyId ==
                                          _preview!.recipientCompanyId) {
                                    Navigator.pop(this.context);
                                  }
                                }
                              },
                        child: const Text('原本保存・共有の確認'),
                      ),
                    if (_decisionStarted)
                      OutlinedButton(
                        onPressed: _busy ? null : _checkDecision,
                        child: const Text('保存結果を照会'),
                      ),
                    OutlinedButton(
                      onPressed: _busy ? null : _openRecovery,
                      child: const Text('確認待ちの注文'),
                    ),
                  ],
                ),
              ),
            ],
          ),
  );
}
