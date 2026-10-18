import 'dart:async';

import 'package:flutter/material.dart';

import 'worker_document_change_repository.dart';
import 'worker_document_change_route_host.dart';
import 'worker_document_photos.dart';

class WorkerDocumentChangeReviewPage extends StatefulWidget {
  const WorkerDocumentChangeReviewPage({
    super.key,
    required this.repository,
    required this.companyId,
    required this.isCurrent,
    this.workerNames = const {},
    this.requirementNames = const {},
  });
  final WorkerDocumentChangeRepository repository;
  final String companyId;
  final Map<String, String> workerNames, requirementNames;
  final bool Function() isCurrent;
  @override
  State<WorkerDocumentChangeReviewPage> createState() =>
      _WorkerDocumentChangeReviewPageState();
}

class _WorkerDocumentChangeReviewPageState
    extends State<WorkerDocumentChangeReviewPage>
    with WidgetsBindingObserver {
  List<WorkerDocumentChangeEntry> _entries = [];
  bool _loading = true, _busy = false, _closed = false;
  String? _error;
  int _generation = 0;
  StreamSubscription<void>? _subscription;
  bool get _current =>
      mounted &&
      !_closed &&
      widget.repository.isCurrentActor &&
      widget.isCurrent();
  @override
  void initState() {
    super.initState();
    _closed = !widget.repository.isCurrentActor;
    WidgetsBinding.instance.addObserver(this);
    _subscription = widget.repository.invalidations.listen((_) => _close());
    _load();
  }

  @override
  void didUpdateWidget(covariant WorkerDocumentChangeReviewPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.repository != widget.repository ||
        oldWidget.companyId != widget.companyId) {
      _close();
    }
  }

  void _close() {
    if (mounted && !_closed) {
      setState(() {
        _closed = true;
        _entries = [];
        _generation++;
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _close();
  }

  Future<void> _load() async {
    final generation = ++_generation;
    if (!_current) return;
    setState(() {
      _loading = true;
      _entries = [];
      _error = null;
    });
    try {
      if (!(await widget.repository.capability()).available) {
        throw StateError('書類変更申請は準備中です。');
      }
      final rows = await widget.repository.list(widget.companyId);
      if (!_current || generation != _generation) return;
      setState(() {
        _entries = rows;
        _loading = false;
      });
    } catch (e) {
      if (_current && generation == _generation) {
        setState(() {
          _error = '変更申請を読み込めません。接続と利用状況を確認してください。';
          _loading = false;
        });
      }
    }
  }

  Future<void> _review(
    BuildContext localContext,
    WorkerDocumentChangeEntry entry,
  ) async {
    if (!_current ||
        _busy ||
        !entry.receipt.canReview ||
        entry.receipt.status != 'pending' ||
        !_entries.contains(entry)) {
      return;
    }
    if (!_hasLabels(entry)) return;
    final generation = _generation;
    setState(() => _busy = true);
    final reason = TextEditingController();
    DialogRoute<bool>? dialogRoute;
    try {
      final current = await widget.repository.detail(entry.command);
      if (!_current ||
          generation != _generation ||
          !current.canReview ||
          current.status != 'pending') {
        return;
      }
      if (!localContext.mounted) return;
      final old = entry.previous;
      final command = entry.command;
      dialogRoute = DialogRoute<bool>(
        context: localContext,
        builder: (dialogContext) => AlertDialog(
          title: Text(
            '${widget.workerNames[command.workerId] ?? '対象者'} / ${widget.requirementNames[command.requirementId] ?? '書類'}の変更確認',
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '有効期限：${old['expires_at'] ?? '未設定'} → ${command.expiresAt ?? '未設定'}',
                ),
                Text('備考（変更前）：${old['notes'] ?? 'なし'}'),
                Text('備考（変更後）：${command.notes ?? 'なし'}'),
                Text(
                  '写真：${workerDocumentPaths(old).length}枚 → ${command.paths.length}枚',
                ),
                for (var i = 0; i < command.paths.length; i++)
                  Text(
                    '変更後 ${i + 1}枚目：変更前の${workerDocumentPaths(old).indexOf(command.paths[i]) + 1}枚目',
                  ),
                const Text('承認時に正式な書類へ反映されます。'),
                TextField(
                  controller: reason,
                  decoration: const InputDecoration(labelText: '却下理由（却下時必須）'),
                  maxLength: 1000,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('戻る'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('却下'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('承認'),
            ),
          ],
        ),
      );
      final decision = await Navigator.of(localContext).push(dialogRoute);
      if (!_current ||
          generation != _generation ||
          !_entries.contains(entry) ||
          decision == null) {
        return;
      }
      if (!decision && reason.text.trim().isEmpty) {
        setState(() => _error = '却下理由を入力してください。');
        return;
      }
      final currentBeforeWrite = await widget.repository.detail(command);
      if (!_current ||
          generation != _generation ||
          !currentBeforeWrite.canReview ||
          currentBeforeWrite.status != 'pending') {
        return;
      }
      await widget.repository.review(
        command,
        approve: decision,
        reason: reason.text,
      );
      if (!_current || generation != _generation) return;
      await _load();
    } catch (e) {
      if (_current && generation == _generation) {
        setState(() => _error = '結果を確認できません。再読み込みして申請状態を確認してください。');
      }
    } finally {
      final route = dialogRoute;
      if (route == null) {
        reason.dispose();
      } else {
        unawaited(route.completed.then((_) => reason.dispose()));
      }
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _generation++;
    WidgetsBinding.instance.removeObserver(this);
    _subscription?.cancel();
    super.dispose();
  }

  bool _hasLabels(WorkerDocumentChangeEntry entry) =>
      entry.command.companyId == widget.companyId &&
      (widget.workerNames[entry.command.workerId]?.trim().isNotEmpty ??
          false) &&
      (widget.requirementNames[entry.command.requirementId]
              ?.trim()
              .isNotEmpty ??
          false);

  @override
  Widget build(BuildContext context) {
    if (_closed) {
      return Scaffold(
        appBar: AppBar(title: const Text('書類の変更申請一覧')),
        body: const Center(child: Text('画面を開き直してください。')),
      );
    }
    return WorkerDocumentChangeRouteHost(
      onClose: () => Navigator.of(context).pop(),
      builder: _content,
    );
  }

  Widget _content(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('書類の変更申請一覧'),
      actions: [
        IconButton(
          onPressed: _loading || _busy || _closed ? null : _load,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: _closed
        ? const Center(child: Text('画面を開き直してください。'))
        : _loading
        ? const Center(child: CircularProgressIndicator())
        : ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (_error != null) Text(_error!),
              if (_entries.isEmpty && _error == null)
                const Text('表示できる変更申請はありません。'),
              for (final entry in _entries)
                Card(
                  child: ListTile(
                    title: Text(
                      '${widget.workerNames[entry.command.workerId] ?? '対象者'} / ${widget.requirementNames[entry.command.requirementId] ?? '書類'}',
                    ),
                    subtitle: Text(
                      '${_hasLabels(entry) ? '' : '対象情報を確認できません。再読み込みしてください。\n'}状態：${switch (entry.receipt.status) {
                        'pending' => '承認待ち',
                        'approved' => '承認済み',
                        'rejected' => '却下',
                        'cancelled' => '取消済み',
                        _ => '下書き',
                      }}\n期限：${entry.command.expiresAt ?? '未設定'}\n備考：${entry.command.notes ?? 'なし'}',
                    ),
                    trailing:
                        _hasLabels(entry) &&
                            entry.receipt.canReview &&
                            entry.receipt.status == 'pending'
                        ? TextButton(
                            onPressed: _busy
                                ? null
                                : () => _review(context, entry),
                            child: const Text('差分を確認'),
                          )
                        : null,
                  ),
                ),
            ],
          ),
  );
}
