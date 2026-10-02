// ignore_for_file: prefer_interpolation_to_compose_strings

import 'dart:math';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../common/data_date_labels.dart';

import 'company_document_exchange_repository.dart';
import 'company_submitted_document_repository.dart';

class CompanySubmittedDocumentsPage extends StatefulWidget {
  const CompanySubmittedDocumentsPage({super.key});

  @override
  State<CompanySubmittedDocumentsPage> createState() =>
      _CompanySubmittedDocumentsPageState();
}

class _CompanySubmittedDocumentsPageState
    extends State<CompanySubmittedDocumentsPage> {
  final _repository = CompanySubmittedDocumentRepository.maybeCreate();
  final _exchange = CompanyDocumentExchangeRepository.maybeCreate();
  final _selected = <String>{};
  final _receiveCode = TextEditingController();
  final _note = TextEditingController();

  List<Map<String, dynamic>> _documents = const [];
  bool _loading = true;
  bool _busy = false;
  String? _targetCompany;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _receiveCode.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final repository = _repository;
    if (repository == null) return;
    try {
      final rows = await repository.listDocuments();
      if (!mounted) return;
      setState(() {
        _documents = rows;
        _selected.removeWhere(
          (id) => !rows.any((row) => row['id']?.toString() == id),
        );
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('会社提出書類'),
        actions: [
          IconButton(
            tooltip: '書類種類を追加',
            onPressed: _busy ? null : _create,
            icon: const Icon(Icons.add_circle_outline),
          ),
          IconButton(
            tooltip: '再読み込み',
            onPressed: _busy ? null : _reload,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(child: Text(_error!, textAlign: TextAlign.center))
                : ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      const Card(
                        child: Padding(
                          padding: EdgeInsets.all(16),
                          child: Text(
                            '自社が上位会社へ提出する会社単位の書類です。従業員個人の必要書類とは分けて管理します。',
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      if (_documents.isEmpty)
                        const Card(
                          child: Padding(
                            padding: EdgeInsets.all(18),
                            child: Text('会社提出書類はまだ登録されていません'),
                          ),
                        ),
                      for (final row in _documents) _documentCard(row),
                      if (_selected.isNotEmpty) ...[
                        const SizedBox(height: 20),
                        Text(
                          '上位会社へ送信（' + _selected.length.toString() + '件）',
                          style:
                              Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w900,
                                  ),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _receiveCode,
                          decoration: const InputDecoration(
                            labelText: '上位会社の受取コード',
                            prefixIcon: Icon(Icons.vpn_key_outlined),
                          ),
                          onChanged: (_) =>
                              setState(() => _targetCompany = null),
                        ),
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: _busy ? null : _resolveTarget,
                          icon: const Icon(Icons.verified_outlined),
                          label: const Text('送信先会社を確認'),
                        ),
                        if (_targetCompany != null)
                          ListTile(
                            leading: const Icon(Icons.business_outlined),
                            title: const Text('送信先'),
                            subtitle: Text(
                              _targetCompany!,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w900),
                            ),
                          ),
                        TextField(
                          controller: _note,
                          maxLines: 3,
                          maxLength: 2000,
                          decoration:
                              const InputDecoration(labelText: '案内・メモ（任意）'),
                        ),
                        FilledButton.icon(
                          onPressed: _busy || _targetCompany == null
                              ? null
                              : _confirmSend,
                          icon: const Icon(Icons.send_outlined),
                          label: const Text('内容を確認して送信'),
                        ),
                      ],
                    ],
                  ),
      ),
    );
  }

  Widget _documentCard(Map<String, dynamic> row) {
    final id = row['id']?.toString() ?? '';
    final path = row['attachment_path']?.toString() ?? '';
    final expires = row['expires_at']?.toString() ?? '';
    return Card(
      child: Column(
        children: [
          CheckboxListTile(
            value: _selected.contains(id),
            onChanged: path.isEmpty
                ? null
                : (value) => setState(() {
                      if (value == true) {
                        _selected.add(id);
                      } else {
                        _selected.remove(id);
                      }
                    }),
            title: Text(
              row['name']?.toString() ?? '会社提出書類',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            subtitle: Text(
              [
                path.isEmpty ? 'PDF・画像未登録' : '提出ファイル登録済み',
                if (expires.isNotEmpty) '有効期限 ' + expires,
                if ((row['notes']?.toString() ?? '').isNotEmpty)
                  row['notes'].toString(),
                ...DataDateLabels.labels(
                  createdAt: row['created_at'],
                  updatedAt: row['updated_at'],
                ),
              ].join(' / '),
            ),
            secondary: const Icon(Icons.business_center_outlined),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Row(
              children: [
                OutlinedButton.icon(
                  onPressed: _busy ? null : () => _pickFile(row),
                  icon: const Icon(Icons.upload_file_outlined),
                  label: Text(path.isEmpty ? 'PDF等を登録' : 'ファイル差替'),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: _busy ? null : () => _edit(row),
                  child: const Text('編集'),
                ),
                const Spacer(),
                IconButton(
                  tooltip: '無効化',
                  onPressed: _busy ? null : () => _archive(row),
                  icon: const Icon(Icons.archive_outlined),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _create() async {
    final draft = await _metadataDialog();
    if (draft == null || _repository == null) return;
    setState(() => _busy = true);
    try {
      await _repository.createDocument(
        name: draft.name,
        expiresAt: draft.expiresAt,
        notes: draft.notes,
      );
      await _load();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _edit(Map<String, dynamic> row) async {
    final draft = await _metadataDialog(row: row);
    if (draft == null || _repository == null) return;
    setState(() => _busy = true);
    try {
      await _repository.updateMetadata(
        id: row['id'].toString(),
        name: draft.name,
        expiresAt: draft.expiresAt,
        notes: draft.notes,
      );
      await _load();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<_DocumentDraft?> _metadataDialog({Map<String, dynamic>? row}) async {
    final name = TextEditingController(text: row?['name']?.toString() ?? '');
    final notes =
        TextEditingController(text: row?['notes']?.toString() ?? '');
    DateTime? expiresAt = _parseDate(row?['expires_at']);
    final result = await showDialog<_DocumentDraft>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(row == null ? '会社提出書類を追加' : '会社提出書類を編集'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: name,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: '書類種類 *',
                    hintText: '例：建設業許可証',
                  ),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('有効期限'),
                  subtitle: Text(
                    expiresAt == null ? '設定なし' : _formatDate(expiresAt!),
                  ),
                  trailing: const Icon(Icons.calendar_month_outlined),
                  onTap: () async {
                    final now = DateTime.now();
                    final picked = await showDatePicker(
                      context: dialogContext,
                      initialDate: expiresAt ?? now,
                      firstDate: DateTime(1950),
                      lastDate: DateTime(now.year + 30),
                    );
                    if (picked != null) {
                      setDialogState(() => expiresAt = picked);
                    }
                  },
                ),
                TextField(
                  controller: notes,
                  maxLines: 3,
                  decoration: const InputDecoration(labelText: 'メモ'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('キャンセル'),
            ),
            FilledButton(
              onPressed: () {
                if (name.text.trim().isEmpty) return;
                Navigator.pop(
                  dialogContext,
                  _DocumentDraft(
                    name: name.text.trim(),
                    expiresAt: expiresAt,
                    notes: notes.text.trim(),
                  ),
                );
              },
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
    name.dispose();
    notes.dispose();
    return result;
  }

  Future<void> _pickFile(Map<String, dynamic> row) async {
    final repository = _repository;
    if (repository == null) return;
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png', 'heic', 'heif'],
    );
    if (file == null) return;
    final bytes = await file.readAsBytes();
    setState(() => _busy = true);
    try {
      await repository.upload(
        id: row['id'].toString(),
        bytes: bytes,
        filename: file.name,
        contentType: _contentType(file.extension),
      );
      await _load();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _archive(Map<String, dynamic> row) async {
    if (_repository == null) return;
    final name = row['name']?.toString() ?? '会社提出書類';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('会社提出書類を無効化'),
        content: Text(name + 'を一覧から外します。履歴・送信済みデータは削除しません。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('戻る'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('無効化'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _busy = true);
    try {
      await _repository.archive(row['id'].toString());
      await _load();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resolveTarget() async {
    final exchange = _exchange;
    if (exchange == null || _receiveCode.text.trim().isEmpty) return;
    final row = await exchange.resolveReceiveCode(_receiveCode.text);
    if (!mounted) return;
    setState(() => _targetCompany = row['company_name']?.toString());
  }

  Future<void> _confirmSend() async {
    final exchange = _exchange;
    final target = _targetCompany;
    if (exchange == null || target == null) return;
    final selectedRows = _documents
        .where((row) => _selected.contains(row['id']?.toString()))
        .toList(growable: false);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('送信内容の最終確認'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('送信先: ' + target),
              const SizedBox(height: 8),
              for (final row in selectedRows)
                Text('・' + (row['name']?.toString() ?? '会社提出書類')),
              const SizedBox(height: 12),
              const Text('会社提出書類として、出所会社を保持したまま上位会社へ送信します。'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('戻る'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('この内容で送信'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _busy = true);
    try {
      await exchange.send(
        requestId: _requestId(),
        receiveCode: _receiveCode.text,
        items: [
          for (final row in selectedRows)
            {'id': row['id'].toString(), 'kind': 'company'},
        ],
        note: _note.text,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(target + 'へ会社提出書類を送信しました')),
      );
      setState(() {
        _selected.clear();
        _targetCompany = null;
      });
      _receiveCode.clear();
      _note.clear();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _reload() {
    setState(() => _loading = true);
    _load();
  }

  DateTime? _parseDate(Object? value) {
    final text = value?.toString();
    return text == null || text.isEmpty ? null : DateTime.tryParse(text);
  }

  String _formatDate(DateTime value) {
    return value.year.toString() +
        '/' +
        value.month.toString().padLeft(2, '0') +
        '/' +
        value.day.toString().padLeft(2, '0');
  }

  String _contentType(String? extension) {
    return switch (extension?.toLowerCase()) {
      'pdf' => 'application/pdf',
      'png' => 'image/png',
      'heic' => 'image/heic',
      'heif' => 'image/heif',
      _ => 'image/jpeg',
    };
  }

  String _requestId() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex =
        bytes.map((value) => value.toRadixString(16).padLeft(2, '0')).join();
    return hex.substring(0, 8) +
        '-' +
        hex.substring(8, 12) +
        '-' +
        hex.substring(12, 16) +
        '-' +
        hex.substring(16, 20) +
        '-' +
        hex.substring(20);
  }
}

class _DocumentDraft {
  const _DocumentDraft({
    required this.name,
    required this.expiresAt,
    required this.notes,
  });

  final String name;
  final DateTime? expiresAt;
  final String notes;
}
