import 'dart:math';

import 'package:flutter/material.dart';

import 'worker_document_admin_correction_repository.dart';
import 'worker_document_photos.dart';

/// Only opened after the purpose-specific server capability check. Production
/// authorization remains in the server; this is not a personal approval route.
class WorkerDocumentAdminCorrectionPage extends StatefulWidget {
  const WorkerDocumentAdminCorrectionPage({
    super.key,
    required this.repository,
    required this.snapshot,
    required this.documentName,
  });
  final WorkerDocumentAdminCorrectionRepository repository;
  final Map<String, dynamic> snapshot;
  final String documentName;
  @override
  State<WorkerDocumentAdminCorrectionPage> createState() => _CorrectionState();
}

class _CorrectionState extends State<WorkerDocumentAdminCorrectionPage> {
  late final TextEditingController _expiry, _notes;
  final _reason = TextEditingController();
  late final List<String> _paths;
  bool _busy = false, _available = false, _pending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _expiry = TextEditingController(
      text: widget.snapshot['expires_at'] as String? ?? '',
    );
    _notes = TextEditingController(
      text: widget.snapshot['notes'] as String? ?? '',
    );
    _paths = workerDocumentPaths(widget.snapshot).toList();
    _load();
  }

  Future<void> _load() async {
    try {
      _pending = widget.repository.pendingRequest() != null;
      final available = await widget.repository.available();
      if (mounted) {
        setState(() => _available = available);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = '管理訂正の利用状態を確認できません。開き直してください。');
      }
    }
  }

  String _newId() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 15) | 64;
    bytes[8] = (bytes[8] & 63) | 128;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  Future<void> _recover() async {
    setState(() => _busy = true);
    try {
      final result = await widget.repository.recover();
      if (!mounted) {
        return;
      }
      if (result == 'applied') {
        Navigator.of(context).pop(true);
      } else if (result == 'cancelled' || result == null) {
        // Reopen from a freshly loaded snapshot before making another command.
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('前の変更は反映されていません。書類を開き直してください。')),
        );
        Navigator.of(context).pop(true);
      } else {
        setState(() => _error = '変更結果が不明です。再送せず、結果確認をやり直してください。');
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = '変更結果を確認できません。変更IDを保持しています。');
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    final expiry = _expiry.text.trim();
    if (_reason.text.trim().isEmpty ||
        (expiry.isNotEmpty &&
            (DateTime.tryParse(expiry)?.toIso8601String().substring(0, 10) !=
                    expiry ||
                !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(expiry)))) {
      setState(() => _error = '変更理由と期限（年-月-日）を確認してください。');
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('本人の書類を管理訂正'),
        content: Text(
          '${widget.documentName}\n理由：${_reason.text.trim()}\n原本と変更履歴を残して保存します。原本確認は解除されます。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('入力に戻る'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('変更を保存'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await widget.repository.correct(
        requestId: _newId(),
        expectedSnapshot: widget.snapshot,
        paths: _paths,
        expiresAt: expiry.isEmpty ? null : expiry,
        notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
        reason: _reason.text.trim(),
      );
      if (mounted) {
        if (result == 'applied') {
          Navigator.of(context).pop(true);
        } else {
          setState(() {
            _pending = true;
            _error = '保存結果を確認してください。';
          });
        }
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          // A retired captured session must not be used for a second local read
          // to infer rollback. Keep recovery visible; reopening rebinds safely.
          _pending = true;
          _error = '保存を確認できません。再送せず変更結果を確認してください。';
        });
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  void dispose() {
    _expiry.dispose();
    _notes.dispose();
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('本人書類の管理訂正')),
    body: GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: ListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: EdgeInsets.fromLTRB(
          16,
          16,
          16,
          MediaQuery.viewInsetsOf(context).bottom + 24,
        ),
        children: [
          Text(
            widget.documentName,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          const Text('期限・備考・登録済み写真の並び順や除外を変更します。新しい写真の追加には対応していません。'),
          if (!_available && !_pending)
            const Text('管理訂正は現在利用できません。原本は変更していません。'),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(_error!),
            ),
          TextField(
            controller: _expiry,
            enabled: _available && !_pending && !_busy,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => FocusScope.of(context).unfocus(),
            decoration: const InputDecoration(labelText: '期限（YYYY-MM-DD／空欄可）'),
          ),
          TextField(
            controller: _notes,
            enabled: _available && !_pending && !_busy,
            maxLength: 4000,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => FocusScope.of(context).unfocus(),
            decoration: const InputDecoration(labelText: '備考'),
          ),
          TextField(
            controller: _reason,
            enabled: _available && !_pending && !_busy,
            maxLength: 1000,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => FocusScope.of(context).unfocus(),
            decoration: const InputDecoration(labelText: '変更理由（必須）'),
          ),
          for (var i = 0; i < _paths.length; i++)
            ListTile(
              title: Text('登録済み写真 ${i + 1}'),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: '前へ',
                    icon: const Icon(Icons.arrow_upward),
                    onPressed: !_available || _busy || _pending || i == 0
                        ? null
                        : () => setState(() {
                            final path = _paths.removeAt(i);
                            _paths.insert(i - 1, path);
                          }),
                  ),
                  IconButton(
                    tooltip: '今回の表示から除外（原本保持）',
                    icon: const Icon(Icons.remove_circle_outline),
                    onPressed: !_available || _busy || _pending
                        ? null
                        : () => setState(() => _paths.removeAt(i)),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 16),
          if (_pending)
            FilledButton(
              onPressed: _busy ? null : _recover,
              child: const Text('前の変更結果を確認'),
            )
          else
            FilledButton(
              onPressed: _available && !_busy ? _save : null,
              child: const Text('変更を保存'),
            ),
        ],
      ),
    ),
  );
}
