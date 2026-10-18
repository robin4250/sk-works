import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'worker_document_change_repository.dart';
import 'worker_document_change_route_host.dart';
import 'worker_document_photo_editor.dart';
import 'worker_document_photos.dart';

/// Empty placeholders are not proof of registration. Server history is final.
bool workerDocumentHasRegisteredContent(Map<String, dynamic>? row) =>
    row != null &&
    (!['not_submitted', 'missing'].contains(row['status']) ||
        row['original_verified'] == true ||
        row['expires_at'] != null ||
        (row['notes']?.toString().trim().isNotEmpty ?? false) ||
        workerDocumentPaths(row).isNotEmpty);

Map<String, dynamic> _encode(WorkerDocumentChangeCommand c) => {
  ...c.preparePayload,
  'company_id': c.companyId,
  'worker_id': c.workerId,
  'requirement_id': c.requirementId,
  'requested_by': c.requestedBy,
};

WorkerDocumentChangeCommand decodeWorkerDocumentChangeCommand(Map raw) {
  final proposed = raw['proposed'] as Map;
  return WorkerDocumentChangeCommand(
    requestId: raw['request_id'] as String,
    targetId: raw['status_id'] as String,
    companyId: raw['company_id'] as String,
    workerId: raw['worker_id'] as String,
    requirementId: raw['requirement_id'] as String,
    requestedBy: raw['requested_by'] as String,
    expectedUpdatedAt: raw['expected_updated_at'] as String,
    paths: (proposed['attachment_paths'] as List).cast<String>(),
    expiresAt: proposed['expires_at'] as String?,
    notes: proposed['notes'] as String?,
  );
}

/// Write and verify before RPC. Unknown results retain the exact original ID.
class WorkerDocumentChangeStore {
  WorkerDocumentChangeStore(this.preferences);
  final SharedPreferences preferences;
  String _key(String actor, String target) =>
      'worker_document_change_v1:$actor:$target';
  WorkerDocumentChangeCommand? read(String actor, String target) {
    final raw = preferences.getString(_key(actor, target));
    if (raw == null) return null;
    final command = decodeWorkerDocumentChangeCommand(jsonDecode(raw) as Map);
    if (command.requestedBy != actor || command.targetId != target) {
      throw const FormatException('保存された申請の対象が一致しません。');
    }
    return command;
  }

  Future<void> write(WorkerDocumentChangeCommand command) async {
    final key = _key(command.requestedBy, command.targetId);
    final old = preferences.getString(key);
    final value = jsonEncode(_encode(command));
    if (old != null && old != value) throw StateError('前の申請結果を先に確認してください。');
    if (!await preferences.setString(key, value) ||
        preferences.getString(key) != value) {
      throw StateError('申請を端末に保存できませんでした。送信していません。');
    }
  }

  Future<void> clear(WorkerDocumentChangeCommand command) async {
    final key = _key(command.requestedBy, command.targetId);
    if (preferences.getString(key) != jsonEncode(_encode(command))) {
      throw StateError('保存された申請が変わりました。');
    }
    if (!await preferences.remove(key)) {
      throw StateError('申請結果の端末保存を確認できませんでした。');
    }
  }
}

String _newId() {
  final random = Random.secure();
  final b = List<int>.generate(16, (_) => random.nextInt(256));
  b[6] = (b[6] & 15) | 64;
  b[8] = (b[8] & 63) | 128;
  final h = b.map((v) => v.toRadixString(16).padLeft(2, '0')).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
}

class WorkerDocumentChangePage extends StatefulWidget {
  const WorkerDocumentChangePage({
    super.key,
    required this.repository,
    required this.actor,
    required this.companyId,
    required this.row,
    required this.signedUrl,
    required this.isCurrent,
    this.onVerification,
  });
  final WorkerDocumentChangeRepository repository;
  final String actor, companyId;
  final Map<String, dynamic> row;
  final Future<String> Function(String) signedUrl;
  final bool Function() isCurrent;
  final Future<void> Function(String status, bool originalVerified)?
  onVerification;
  @override
  State<WorkerDocumentChangePage> createState() =>
      _WorkerDocumentChangePageState();
}

class _WorkerDocumentChangePageState extends State<WorkerDocumentChangePage>
    with WidgetsBindingObserver {
  late final _notes = TextEditingController(
    text: widget.row['notes']?.toString() ?? '',
  );
  late List<String> _paths = workerDocumentPaths(widget.row);
  late String? _expires = widget.row['expires_at']?.toString();
  WorkerDocumentChangeStore? _store;
  WorkerDocumentChangeCommand? _command;
  bool _busy = true, _available = false, _closed = false;
  StreamSubscription<void>? _subscription;
  String? _message;
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
  void didUpdateWidget(covariant WorkerDocumentChangePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.repository != widget.repository ||
        oldWidget.actor != widget.actor ||
        oldWidget.companyId != widget.companyId ||
        oldWidget.row['id'] != widget.row['id'] ||
        oldWidget.row['worker_id'] != widget.row['worker_id'] ||
        oldWidget.row['requirement_id'] != widget.row['requirement_id']) {
      _close();
    }
  }

  void _close() {
    if (mounted && !_closed) setState(() => _closed = true);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _close();
  }

  Future<void> _load() async {
    try {
      final store = WorkerDocumentChangeStore(
        await SharedPreferences.getInstance(),
      );
      final command = store.read(widget.actor, widget.row['id'] as String);
      if (command != null &&
          (command.companyId != widget.companyId ||
              command.workerId != widget.row['worker_id'] ||
              command.requirementId != widget.row['requirement_id'])) {
        throw const FormatException('Saved document scope changed');
      }
      final capability = await widget.repository.capability();
      if (!_current) return;
      setState(() {
        _store = store;
        _command = command;
        _available = capability.available;
        if (command != null) {
          _paths = command.paths;
          _expires = command.expiresAt;
          _notes.text = command.notes ?? '';
        }
        _busy = false;
        _message = capability.available
            ? (command == null ? null : '前の申請が保存されています。結果を確認してください。')
            : '書類変更申請は準備中です。正式な書類は変更していません。';
      });
    } catch (e) {
      if (_current) {
        setState(() {
          _busy = false;
          _message = '申請を確認できません。画面を開き直してください。';
        });
      }
    }
  }

  Future<void> _send() async {
    if (_busy || !_available || !_current || _store == null) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final trimmed = _notes.text.trim();
      final command =
          _command ??
          WorkerDocumentChangeCommand(
            requestId: _newId(),
            targetId: widget.row['id'] as String,
            companyId: widget.companyId,
            workerId: widget.row['worker_id'] as String,
            requirementId: widget.row['requirement_id'] as String,
            requestedBy: widget.actor,
            expectedUpdatedAt: widget.row['updated_at'] as String,
            paths: _paths,
            expiresAt: _expires,
            notes: trimmed.isEmpty ? null : trimmed,
          );
      await _store!.write(command);
      if (!_current) return;
      _command = command;
      // prepare is idempotent and also resolves a previous lost submit response.
      var receipt = await widget.repository.prepare(command);
      if (!_current) return;
      if (receipt.status == 'draft') {
        receipt = await widget.repository.submit(command);
      }
      if (!_current) return;
      if (![
        'pending',
        'approved',
        'rejected',
        'cancelled',
      ].contains(receipt.status)) {
        throw StateError('申請結果を確認できません。');
      }
      await _store!.clear(command);
      if (!_current) return;
      setState(() {
        _available = false;
        _message = switch (receipt.status) {
          'pending' => '変更申請を送信しました。承認されるまで正式な書類は変わりません。',
          'approved' => 'この変更申請は承認済みです。',
          'rejected' => 'この変更申請は却下されました。画面を開き直してください。',
          _ => 'この変更申請は取消済みです。画面を開き直してください。',
        };
      });
    } catch (e) {
      if (_current) {
        setState(() {
          _message = '結果を確認できません。前の申請の結果を再確認してください。';
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verify(BuildContext localContext) async {
    if (!_current || _busy || widget.onVerification == null) return;
    var status = widget.row['status']?.toString() ?? 'not_submitted';
    var verified = widget.row['original_verified'] == true;
    setState(() => _busy = true);
    try {
      final save = await showDialog<bool>(
        context: localContext,
        useRootNavigator: false,
        builder: (dialogContext) => StatefulBuilder(
          builder: (_, update) => AlertDialog(
            title: const Text('提出状態・原本の確認'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('写真・期限・備考は変更しません。内容の変更には承認が必要です。'),
                DropdownButton<String>(
                  value: status,
                  items: [
                    for (final value in [
                      'not_submitted',
                      'submitted',
                      'verified',
                      'missing',
                      'expired',
                    ])
                      DropdownMenuItem(
                        value: value,
                        child: Text(switch (value) {
                          'not_submitted' => '未提出',
                          'submitted' => '提出済み',
                          'verified' => '確認済み',
                          'missing' => '不足',
                          _ => '期限切れ',
                        }),
                      ),
                  ],
                  onChanged: (value) {
                    if (value != null) update(() => status = value);
                  },
                ),
                CheckboxListTile(
                  title: const Text('原本確認済み'),
                  value: verified,
                  onChanged: (value) => update(() => verified = value ?? false),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('戻る'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('確認結果を保存'),
              ),
            ],
          ),
        ),
      );
      if (!_current || !widget.repository.isCurrentActor || save != true) {
        return;
      }
      await widget.onVerification!(status, verified);
      if (_current) {
        setState(() {
          _available = false;
          _message = '確認結果を保存しました。画面を開き直してください。';
        });
      }
    } catch (_) {
      if (_current) setState(() => _message = '確認結果を保存できません。再読み込みしてください。');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _subscription?.cancel();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_closed) {
      return Scaffold(
        appBar: AppBar(title: const Text('書類の変更申請')),
        body: const Center(child: Text('画面を開き直してください。')),
      );
    }
    return WorkerDocumentChangeRouteHost(
      onClose: () => Navigator.of(context).pop(),
      builder: _content,
    );
  }

  Widget _content(BuildContext context) {
    final editable = !_busy && _available && _command == null;
    return Scaffold(
      appBar: AppBar(title: const Text('書類の変更申請')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('登録済み書類の変更には承認が必要です。新しい写真の追加は準備中です。'),
          if (widget.onVerification != null)
            TextButton(
              onPressed: _busy || _command != null
                  ? null
                  : () => _verify(context),
              child: const Text('提出状態・原本の確認'),
            ),
          if (_message != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(_message!),
            ),
          if (_busy) const LinearProgressIndicator(),
          TextButton(
            onPressed: !editable
                ? null
                : () async {
                    final photos = await editWorkerDocumentPhotos(
                      context,
                      paths: _paths,
                      signedUrl: widget.signedUrl,
                      allowNewPhotos: false,
                      useRootNavigator: false,
                      uploadNotice: '保存済み写真の並べ替え・削除のみ申請できます。',
                    );
                    if (!_current || photos == null) return;
                    setState(
                      () => _paths = photos.map((p) => p.path!).toList(),
                    );
                  },
            child: Text('保存済み写真（${_paths.length}枚）'),
          ),
          ListTile(
            title: const Text('有効期限'),
            subtitle: Text(_expires ?? '未設定'),
            onTap: !editable
                ? null
                : () async {
                    final picked = await showDatePicker(
                      context: context,
                      useRootNavigator: false,
                      initialDate:
                          DateTime.tryParse(_expires ?? '') ?? DateTime.now(),
                      firstDate: DateTime(1950),
                      lastDate: DateTime(2200),
                    );
                    if (_current && picked != null) {
                      setState(
                        () => _expires = picked.toIso8601String().substring(
                          0,
                          10,
                        ),
                      );
                    }
                  },
            trailing: IconButton(
              onPressed: !editable
                  ? null
                  : () => setState(() => _expires = null),
              icon: const Icon(Icons.clear),
            ),
          ),
          TextField(
            controller: _notes,
            enabled: editable,
            maxLength: 4000,
            maxLines: 3,
            decoration: const InputDecoration(labelText: '備考'),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: FilledButton(
            onPressed: _busy || !_available ? null : _send,
            child: Text(_command == null ? '変更を申請' : '前の申請の結果を確認'),
          ),
        ),
      ),
    );
  }
}
