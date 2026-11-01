import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../shared/pdf_pinch_pages.dart';
import 'site_order_workflow_pdf_page.dart';
import 'site_order_saved_preview_pager.dart';
import 'site_order_workflow_repository.dart';
import 'site_order_outgoing_recovery_page.dart';
import 'site_order_outgoing_compose_page.dart';

class SiteOrderWorkflowPage extends StatefulWidget {
  const SiteOrderWorkflowPage({
    super.key,
    this.initialPackageId,
    this.api,
    this.previewBuilder,
    this.siteId,
    this.siteName,
    this.historyTitle,
  }) : assert(initialPackageId == null || siteId == null);
  final String? siteId, siteName, historyTitle;
  final String? initialPackageId;
  @visibleForTesting
  final Widget Function(Uint8List)? previewBuilder;
  @visibleForTesting
  final SiteOrderWorkflowApi? api;
  @override
  State<SiteOrderWorkflowPage> createState() => _SiteOrderWorkflowPageState();
}

class _SiteOrderWorkflowPageState extends State<SiteOrderWorkflowPage> {
  SiteOrderWorkflowApi? _api;
  final _rows = <Map<String, dynamic>>[];
  bool _loading = true, _more = true, _opening = false;
  String? _error;
  late final String? _siteId;
  bool _scopeRetired = false, _canCreate = false;
  final _scopeChanges = ValueNotifier<int>(0);
  @override
  void initState() {
    super.initState();
    _siteId = widget.siteId;
    _api = widget.api ?? SiteOrderWorkflowRepository.maybeCreate();
    _api?.addListener(_changed);
    if (_api == null) {
      _loading = false;
      _error = 'ログイン状態を確認してください。';
    } else if (widget.initialPackageId == null) {
      _load();
    }
  }

  @override
  void didUpdateWidget(covariant SiteOrderWorkflowPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.siteId != _siteId || widget.initialPackageId != oldWidget.initialPackageId) {
      _scopeRetired = true;
      _rows.clear();
      _error = '現場が変わりました。一覧から開き直してください。';
      _scopeChanges.value++;
    }
  }

  Future<List<Map<String, dynamic>>> _history(
    SiteOrderWorkflowApi api, {
    String? before,
    String? beforeId,
  }) {
    if (_scopeRetired) { throw StateError('現場を開き直してください。'); }
    final site = _siteId;
    return site == null
        ? api.history(before: before, beforeId: beforeId)
        : api.historyForSite(site, before: before, beforeId: beforeId);
  }

  void _changed() {
    if (!mounted) return;
    if (_api?.invalidated == true) _rows.clear();
    setState(() {});
  }

  Future<void> _load({bool more = false}) async {
    final api = _api;
    if (api == null || _scopeRetired) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'ログイン状態を確認してください。';
        });
      }
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final last = more && _rows.isNotEmpty ? _rows.last : null;
      final result = await _history(api,
        before: last?['created_at']?.toString(),
        beforeId: last?['package_id']?.toString(),
      );
      final canCreate = _siteId != null && !more ? await api.canCreateOutgoing() : _canCreate;
      if (!mounted || api.invalidated || _scopeRetired) return;
      setState(() {
        _canCreate = canCreate;
        if (!more) _rows.clear();
        _rows.addAll(result);
        _more = result.length == 50;
      });
    } catch (_) {
      if (mounted) setState(() => _error = '履歴を確認できません。画面を開き直してください。');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  SiteOrderSavedEntry _entry(Map<String, dynamic> row) => SiteOrderSavedEntry(
    packageId: row['package_id'].toString(),
    title: row['work_name']?.toString() ?? '',
    startsOn: row['period_start']?.toString() ?? '',
    endsOn: row['period_end']?.toString() ?? '',
    pdfSha256: row['pdf_sha256'].toString(),
  );
  Future<void> _openArchive(int index) async {
    final api = _api;
    if (api == null || _scopeRetired || _opening || _loading) return;
    setState(() => _opening = true);
    try {
      await api.verify();
      final entries = _rows.map(_entry).toList(growable: false);
      if (!mounted || api.invalidated || _scopeRetired) return;
      await Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (_) => SiteOrderSavedPreviewPager(
            entries: entries,
            initialIndex: index,
            hasMore: _more,
            requireScope: () {
              if (_scopeRetired) { throw StateError('現場を開き直してください。'); }
              api.requireCurrent();
            },
            scopeChanges: Listenable.merge([api, _scopeChanges]),
            loadPdf: (entry) => api.original(entry.packageId, 'order'),
            loadMore: () async {
              final last = _rows.last;
              final values = await _history(api,
                before: last['created_at'].toString(),
                beforeId: last['package_id'].toString(),
              );
              final result = values.map(_entry).toList(growable: false);
              if (!mounted || api.invalidated || _scopeRetired) throw StateError('開き直してください。');
              setState(() {
                _rows.addAll(values);
                _more = values.length == 50;
              });
              return result;
            },
            openOutput: (entry) => Navigator.push<void>(
              context,
              MaterialPageRoute(
                builder: (_) => SiteOrderWorkflowPdfPage(
                  api: api,
                  packageId: entry.packageId,
                  title: entry.displayTitle,
                  previewBuilder: widget.previewBuilder,
                ),
              ),
            ),
          ),
        ),
      );
    } catch (_) {
      if (mounted) setState(() => _error = '原本の保存情報を確認できません。履歴を開き直してください。');
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  void dispose() {
    _api?.removeListener(_changed);
    if (widget.api == null) _api?.dispose();
    _scopeChanges.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final api = _api;
    if (api != null && widget.initialPackageId != null) {
      return SiteOrderPackagePage(
        key: ValueKey(widget.initialPackageId),
        api: api,
        previewBuilder: widget.previewBuilder,
        packageId: widget.initialPackageId!,
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.historyTitle ?? (_siteId == null ? '過去の注文書・請書' : '${widget.siteName?.trim().isNotEmpty == true ? widget.siteName : '現場'}の注文履歴')),
        actions: [
          if (_siteId != null && api != null && _canCreate) IconButton(
            tooltip: '注文書を作る',
            onPressed: _loading || _scopeRetired || api.invalidated ? null : () => Navigator.push<void>(context,
              MaterialPageRoute(builder: (_) => SiteOrderOutgoingComposePage(api: api, siteId: _siteId,
                issueDate: DateTime.now().toIso8601String().substring(0, 10), previewBuilder: widget.previewBuilder))),
            icon: const Icon(Icons.note_add_outlined),
          ),
          if (_siteId != null && api != null) IconButton(
            tooltip: '注文の準備結果',
            onPressed: _scopeRetired || api.invalidated ? null : () => Navigator.push<void>(context,
              MaterialPageRoute(builder: (_) => SiteOrderOutgoingRecoveryPage(api: api, siteId: _siteId))),
            icon: const Icon(Icons.pending_actions_outlined),
          ),
          IconButton(
            tooltip: '更新',
            onPressed: _loading ? null : () => _load(),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: api?.invalidated == true
          ? const Center(child: Text('ログイン・会社の状態が変わりました。開き直してください。'))
          : _error != null
          ? Center(child: Text(_error!))
          : _rows.isEmpty && _loading
          ? const Center(child: CircularProgressIndicator())
          : _rows.isEmpty
          ? const Center(child: Text('保存された注文・請書はありません。'))
          : ListView(
              padding: const EdgeInsets.all(12),
              children: [
                for (final row in _rows)
                  Card(
                    child: ListTile(
                      title: Text(row['work_name']?.toString() ?? '工事名称未設定'),
                      subtitle: Text(
                        '${row['period_start'] ?? ''} ～ ${row['period_end'] ?? ''}',
                      ),
                      trailing: IconButton(
                        tooltip: '原本を左右にめくる',
                        icon: const Icon(Icons.picture_as_pdf_outlined),
                        onPressed: _opening
                            ? null
                            : () => _openArchive(_rows.indexOf(row)),
                      ),
                      onTap: () => Navigator.push<void>(
                        context,
                        MaterialPageRoute(
                          builder: (_) => SiteOrderPackagePage(
                            api: api!,
                            previewBuilder: widget.previewBuilder,
                            packageId: row['package_id'].toString(),
                          ),
                        ),
                      ),
                    ),
                  ),
                if (_more)
                  TextButton(
                    onPressed: _loading ? null : () => _load(more: true),
                    child: Text(_loading ? '読み込み中…' : 'さらに読み込む'),
                  ),
              ],
            ),
    );
  }
}

class SiteOrderPackagePage extends StatefulWidget {
  const SiteOrderPackagePage({
    super.key,
    required this.api,
    required this.packageId,
    this.previewBuilder,
  });
  final SiteOrderWorkflowApi api;
  final String packageId;
  final Widget Function(Uint8List)? previewBuilder;
  @override
  State<SiteOrderPackagePage> createState() => _SiteOrderPackagePageState();
}

class _SiteOrderPackagePageState extends State<SiteOrderPackagePage> {
  Map<String, dynamic>? _detail;
  bool _busy = true, _unknown = false, _prompting = false;
  String? _error, _message;
  final Map<String, dynamic> _uncertainOperation = {};
  @override
  void initState() {
    super.initState();
    widget.api.addListener(_scopeChanged);
    _load();
  }

  void _scopeChanged() {
    if (widget.api.invalidated && mounted) {
      setState(() {
        _detail = null;
        _error = 'ログイン・会社の状態が変わりました。開き直してください。';
      });
    }
  }

  Future<void> _load() async {
    final recovering = _unknown;
    var pendingApproval = false;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      pendingApproval =
          await widget.api.hasPendingApproval(widget.packageId) ||
          await widget.api.hasPendingRefusal(widget.packageId) ||
          await widget.api.hasPendingReplyRecovery(widget.packageId);
      final value = await widget.api.detail(widget.packageId);
      if (mounted && !widget.api.invalidated) {
        setState(() {
          _detail = value;
          // A negative read can race an earlier request still committing.
          // A persisted decision requires its exact operation barrier;
          // only a final recipient receipt resolves an uncertain reply read.
          _unknown =
              pendingApproval ||
              (recovering && value['reply_recipient_stored'] != true);
          if (recovering || pendingApproval) {
            _message = _unknown
                ? '結果はまだ確定できません。再送せず、保存状態を再確認してください。'
                : '相手の保管先への保存を確認しました。';
            if (!_unknown) {
              _uncertainOperation.clear();
            }
          }
        });
      }
    } catch (_) {
      if (mounted) setState(() => _error = '保存状態を確認できません。画面を開き直してください。');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _checkSaved() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final state = await widget.api.reconcileApproval(widget.packageId);
      final refusal = await widget.api.reconcileRefusal(widget.packageId);
      final reply = await widget.api.reconcileReplyRecovery(widget.packageId);
      if (!mounted || widget.api.invalidated) return;
      if (state != null || refusal != null || reply != null) {
        setState(() {
          _unknown = false;
          _message = reply != null
              ? (reply == 'accepted'
                    ? '請書の相手先保管を確認しました。'
                    : '前の返信を停止しました。内容と自社印を確認して再開できます。')
              : refusal != null
              ? (refusal == 'accepted'
                    ? '注文の辞退が保存されています。'
                    : '前の辞退は受け付けられていません。内容をご確認ください。')
              : state == 'accepted'
              ? '承認の保存を確認しました。請書の送信状態を確認してください。'
              : '前の承認は受け付けられていません。内容を確認して承認し直せます。';
        });
      }
      await _load();
    } catch (_) {
      if (mounted) setState(() => _error = '保存状態はまだ確定できません。再送せず、もう一度確認してください。');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _review() async {
    if (_busy || _unknown) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final targets = await widget.api.targets(widget.packageId);
      if (targets.length != 1) throw StateError('取引会社の登録を一つに確認してください。');
      final preview = await widget.api.preview(
        widget.packageId,
        targets.single,
      );
      final bytes = await widget.api.renderReview(preview);
      if (!mounted || widget.api.invalidated) return;
      final outcome = await Navigator.push<Map<String, dynamic>>(
        context,
        MaterialPageRoute(
          builder: (_) => _ApprovalReviewPage(
            api: widget.api,
            preview: preview,
            bytes: bytes,
            previewBuilder: widget.previewBuilder,
          ),
        ),
      );
      if (!mounted || outcome == null) return;
      final saved = outcome['result'];
      final terminal = saved is Map && saved['status'] == 'recipient_stored';
      final pending =
          saved is Map &&
          saved['status'] == 'approved_reply_queued' &&
          const {
            'pending',
            'result_unknown',
          }.contains(outcome['reply_processing']);
      if (outcome['unknown'] == true || (!terminal && !pending)) {
        setState(() {
          _unknown = true;
          _uncertainOperation.addAll({
            'request_id': outcome['request_id'],
            'preview_id': outcome['preview_id'],
          });
          _message = '保存結果を確認できません。再送せず「保存状態を確認」を押してください。';
        });
      } else {
        setState(
          () => _message = outcome['reply_processing'] != null
              ? '承認済みです。請書の送信状態を確認してください。'
              : '承認しました。請書は相手の保管先に保存されました。',
        );
        await _load();
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = '承認内容を確認できません。取引会社の登録と保存状態を確認してください。');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _refuse() async {
    if (_busy || _unknown || _prompting) return;
    setState(() => _prompting = true);
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        useRootNavigator: false,
        builder: (context) => AlertDialog(
          title: const Text('この注文を辞退しますか？'),
          content: const Text('注文元の会社へ辞退したことを通知します。現場の追加や請書の作成は行いません。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('戻る'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('辞退を送信'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted || widget.api.invalidated) return;
      setState(() => _busy = true);
      await widget.api.refuse(widget.packageId, siteOrderRequestId());
      if (!mounted || widget.api.invalidated) return;
      setState(() => _message = '注文を辞退し、注文元の要通知へ保存しました。');
      await _load();
    } on SiteOrderResultUnknown {
      if (mounted) {
        setState(() {
          _unknown = true;
          _message = '辞退の保存結果を確認できません。再送せず、保存状態を確認してください。';
        });
      }
    } catch (_) {
      if (mounted) setState(() => _error = '辞退の結果を確認できません。保存状態を確認してください。');
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _prompting = false;
        });
      }
    }
  }

  Future<void> _resume() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final preview = await widget.api.previewReplyRecovery(widget.packageId);
      final bytes = await widget.api.renderReplyRecovery(preview);
      if (!mounted || widget.api.invalidated) return;
      final outcome = await Navigator.push<Map<String, dynamic>>(
        context,
        MaterialPageRoute(
          builder: (_) => _ApprovalReviewPage(
            api: widget.api,
            preview: preview,
            bytes: bytes,
            previewBuilder: widget.previewBuilder,
            recovery: true,
          ),
        ),
      );
      if (!mounted || outcome == null) return;
      final saved = outcome['result'];
      if (saved is! Map || saved['status'] != 'recipient_stored') {
        throw const SiteOrderResultUnknown();
      }
      if (!mounted) return;
      setState(() => _message = '請書の保管先を更新しました。');
      await _load();
    } on SiteOrderResultUnknown {
      if (mounted) {
        setState(() {
          _unknown = true;
          _message = '送信結果を確認できません。保存状態を確認してください。';
        });
      }
    } catch (_) {
      if (mounted) setState(() => _error = '請書の処理を再開できません。保存状態を確認してください。');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _open(String kind) {
    final body = _detail?['body'];
    final title = body is Map ? body['work_name']?.toString() : null;
    Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => SiteOrderWorkflowPdfPage(
          api: widget.api,
          packageId: widget.packageId,
          title: title ?? '工事名称未設定',
          kind: kind,
          previewBuilder: widget.previewBuilder,
        ),
      ),
    );
  }

  @override
  void dispose() {
    widget.api.removeListener(_scopeChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final detail = _detail, rawBody = detail?['body'];
    final body = rawBody is Map ? rawBody : const {};
    final projection = detail?['site_projection'];
    final site = projection is Map ? projection : const {};
    final recipient = detail?['is_recipient'] == true;
    final approved = detail?['approved'] == true;
    final rejected = detail?['rejected'] == true;
    final stored = detail?['reply_recipient_stored'] == true;
    final canWrite = detail?['can_write'] == true;
    final sent = detail?['is_sender'] == true;
    final rawParty = body[sent ? 'counterparty' : 'issuer'];
    final partyName = rawParty is Map ? rawParty['name']?.toString() : null;
    return Scaffold(
      appBar: AppBar(
        title: const Text('注文・請書'),
        actions: [
          IconButton(
            tooltip: '保存状態を確認',
            onPressed: _busy ? null : _checkSaved,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: widget.api.invalidated
          ? const Center(child: Text('ログイン・会社の状態が変わりました。開き直してください。'))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (_busy) const LinearProgressIndicator(),
                if (detail != null) ...[
                  Text(
                    body['work_name']?.toString() ?? '工事名称未設定',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${body['period_start'] ?? ''} ～ ${body['period_end'] ?? ''}',
                  ),
                  if (partyName != null && partyName.trim().isNotEmpty)
                    Text('${sent ? '送付先' : '注文元'}：$partyName'),
                  if (recipient) ...[
                    const SizedBox(height: 12),
                    const Text('共有された現場情報'),
                    for (final entry in const {
                      'name': '現場名',
                      'formal_name': '正式名称',
                      'address': '住所',
                      'nearest_station': '最寄り駅',
                      'starts_on': '開始日',
                      'ends_on': '終了日',
                    }.entries)
                      if (site[entry.key] is String &&
                          (site[entry.key] as String).trim().isNotEmpty)
                        Text('${entry.value}：${site[entry.key]}'),
                  ],
                  const SizedBox(height: 12),
                  Chip(
                    label: Text(
                      rejected
                          ? '辞退済み'
                          : stored
                          ? '請書を相手先に保管済み'
                          : approved
                          ? '承認済み・請書の処理を確認'
                          : '承認待ち',
                    ),
                    backgroundColor: Colors.white,
                    side: BorderSide(
                      color: approved
                          ? Colors.green.shade700
                          : Theme.of(context).colorScheme.outline,
                    ),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : () => _open('order'),
                    icon: const Icon(Icons.description_outlined),
                    label: const Text('注文書を見る'),
                  ),
                  if (detail['reply_original_registered'] == true &&
                      (recipient || stored))
                    OutlinedButton.icon(
                      onPressed: _busy ? null : () => _open('acceptance'),
                      icon: const Icon(Icons.description_outlined),
                      label: const Text('請書を見る'),
                    ),
                  if (recipient && !approved && !rejected && canWrite)
                    FilledButton(
                      onPressed: _busy || _unknown ? null : _review,
                      child: const Text('内容と自社印を確認して承認'),
                    ),
                  if (recipient && !approved && !rejected && canWrite)
                    OutlinedButton(
                      onPressed: _busy || _unknown ? null : _refuse,
                      child: const Text('注文を辞退'),
                    ),
                  if (recipient && approved && !stored && canWrite)
                    FilledButton(
                      onPressed: _busy || _unknown ? null : _resume,
                      child: const Text('内容と自社印を確認して返信を再開'),
                    ),
                ],
                if (_message != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(_message!),
                  ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(_error!),
                  ),
                if (_unknown || _error != null)
                  OutlinedButton(
                    onPressed: _busy ? null : _checkSaved,
                    child: const Text('保存状態を確認'),
                  ),
              ],
            ),
    );
  }
}

class _ApprovalReviewPage extends StatefulWidget {
  const _ApprovalReviewPage({
    required this.api,
    required this.preview,
    required this.bytes,
    this.previewBuilder,
    this.recovery = false,
  });
  final bool recovery;
  final SiteOrderWorkflowApi api;
  final Map<String, dynamic> preview;
  final Uint8List bytes;
  final Widget Function(Uint8List)? previewBuilder;
  @override
  State<_ApprovalReviewPage> createState() => _ApprovalReviewPageState();
}

class _ApprovalReviewPageState extends State<_ApprovalReviewPage> {
  final _requestId = siteOrderRequestId();
  bool _confirmed = false, _sending = false, _closing = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    widget.api.addListener(_changed);
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Map<String, dynamic> _unknownOutcome() => {
    'unknown': true,
    'request_id': _requestId,
    'preview_id': widget.preview['preview_id'],
  };

  void _close() {
    if (_closing) return;
    final unknown = _sending;
    setState(() => _closing = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.pop(context, unknown ? _unknownOutcome() : null);
    });
  }

  Future<void> _approve() async {
    if (!_confirmed || _sending || _closing) return;
    setState(() => _sending = true);
    try {
      final result = widget.recovery
          ? await widget.api.recoverReply(widget.preview, _requestId)
          : await widget.api.approve(widget.preview, _requestId);
      if (mounted && !_closing) Navigator.pop(context, result);
    } on SiteOrderResultUnknown {
      if (mounted && !_closing) Navigator.pop(context, _unknownOutcome());
    } catch (_) {
      if (mounted && !_closing) {
        setState(() {
          _error = '承認を確認できません。閉じて保存状態を確認してください。';
          _sending = false;
        });
      }
    }
  }

  @override
  void dispose() {
    widget.api.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_sending || _closing,
    child: Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: '閉じる',
          onPressed: _close,
          icon: const Icon(Icons.close),
        ),
        title: const Text('請書・自社印の確認'),
      ),
      body: widget.api.invalidated
          ? const Center(child: Text('画面を閉じて開き直してください。'))
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text(widget.recovery ? '保存済みの請書・印影を再確認' : '確認用・未承認'),
                ),
                Expanded(
                  child:
                      widget.previewBuilder?.call(widget.bytes) ??
                      PdfPreview.builder(
                        build: (_) async {
                          widget.api.requireCurrent();
                          return widget.bytes;
                        },
                        allowPrinting: false,
                        allowSharing: false,
                        canChangeOrientation: false,
                        canChangePageFormat: false,
                        canDebug: false,
                        pagesBuilder: (context, pages) =>
                            PdfPinchPages(pages: pages),
                      ),
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: Text(_error!),
                  ),
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CheckboxListTile(
                          value: _confirmed,
                          dense: true,
                          title: const Text('注文条件と自社印を確認しました'),
                          onChanged: _sending || _closing
                              ? null
                              : (value) =>
                                    setState(() => _confirmed = value == true),
                        ),
                        FilledButton(
                          onPressed: !_confirmed || _sending || _closing
                              ? null
                              : _approve,
                          child: Text(
                            _sending
                                ? '保存状態を確認中…'
                                : widget.recovery
                                ? '確認して返信を再開'
                                : '承認して請書を送る',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    ),
  );
}
