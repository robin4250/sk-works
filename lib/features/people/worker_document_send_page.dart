import 'dart:math';

import 'package:flutter/material.dart';

import 'company_document_exchange_repository.dart';

class WorkerDocumentSendPage extends StatefulWidget {
  const WorkerDocumentSendPage({
    super.key,
    required this.workerIds,
  });

  final Set<String> workerIds;

  @override
  State<WorkerDocumentSendPage> createState() => _WorkerDocumentSendPageState();
}

class _WorkerDocumentSendPageState extends State<WorkerDocumentSendPage> {
  final _repository = CompanyDocumentExchangeRepository.maybeCreate();
  final _codeController = TextEditingController();
  final _noteController = TextEditingController();

  List<Map<String, dynamic>> _sources = [];
  final Set<String> _selectedIds = {};
  bool _loading = true;
  bool _sending = false;
  String? _targetCompanyName;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadSources();
  }

  @override
  void dispose() {
    _codeController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _loadSources() async {
    final repository = _repository;
    if (repository == null) {
      setState(() {
        _loading = false;
        _error = '会社間書類送信を利用できません。';
      });
      return;
    }
    try {
      final rows = await repository.listSendableSources();
      final filtered = rows.where((row) {
        if (row['kind']?.toString() != 'worker_document') return false;
        final workerId = row['worker_id']?.toString();
        return workerId != null && widget.workerIds.contains(workerId);
      }).toList(growable: false);
      if (!mounted) return;
      setState(() {
        _sources = filtered;
        _selectedIds
          ..clear()
          ..addAll(
            filtered
                .map((row) => row['id']?.toString() ?? '')
                .where((id) => id.isNotEmpty),
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

  Future<void> _resolveTarget() async {
    final repository = _repository;
    final code = _codeController.text.trim();
    if (repository == null || code.isEmpty) return;
    try {
      final result = await repository.resolveReceiveCode(code);
      if (!mounted) return;
      setState(() => _targetCompanyName = result['company_name']?.toString());
    } catch (error) {
      if (!mounted) return;
      setState(() => _targetCompanyName = null);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('受取コードを確認できませんでした: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final selectedRows = _sources
        .where((row) => _selectedIds.contains(row['id']?.toString()))
        .toList(growable: false);

    return Scaffold(
      appBar: AppBar(title: const Text('親会社に書類を送る')),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(_error!, textAlign: TextAlign.center),
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      const Text(
                        '1. 送信先を確認',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _codeController,
                        decoration: const InputDecoration(
                          labelText: '親会社の受取コード',
                          hintText: '親会社の管理者から受け取ったコード',
                          prefixIcon: Icon(Icons.vpn_key_outlined),
                        ),
                        onChanged: (_) =>
                            setState(() => _targetCompanyName = null),
                      ),
                      const SizedBox(height: 10),
                      OutlinedButton.icon(
                        onPressed: _resolveTarget,
                        icon: const Icon(Icons.verified_outlined),
                        label: const Text('送信先の会社名を確認'),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(48),
                        ),
                      ),
                      if (_targetCompanyName != null) ...[
                        const SizedBox(height: 10),
                        Card(
                          child: ListTile(
                            leading: const Icon(Icons.business_outlined),
                            title: const Text('送信先'),
                            subtitle: Text(
                              _targetCompanyName!,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w900),
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 20),
                      const Text(
                        '2. 送る書類を選択',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        '元請・得意先向けに設定された、添付済みの書類だけ表示しています。',
                      ),
                      const SizedBox(height: 8),
                      if (_sources.isEmpty)
                        const Card(
                          child: Padding(
                            padding: EdgeInsets.all(18),
                            child: Text('送信できる書類がありません'),
                          ),
                        )
                      else
                        for (final row in _sources)
                          Card(
                            child: CheckboxListTile(
                              value: _selectedIds
                                  .contains(row['id']?.toString()),
                              onChanged: (value) {
                                final id = row['id']?.toString() ?? '';
                                if (id.isEmpty) return;
                                setState(() {
                                  if (value == true) {
                                    _selectedIds.add(id);
                                  } else {
                                    _selectedIds.remove(id);
                                  }
                                });
                              },
                              title: Text(
                                row['name']?.toString() ?? '書類',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              subtitle:
                                  Text(row['group']?.toString() ?? ''),
                              controlAffinity:
                                  ListTileControlAffinity.leading,
                            ),
                          ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _noteController,
                        maxLines: 3,
                        maxLength: 2000,
                        decoration: const InputDecoration(
                          labelText: '案内・備考（任意）',
                        ),
                      ),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: _targetCompanyName == null ||
                                selectedRows.isEmpty ||
                                _sending
                            ? null
                            : () => _confirmAndSend(selectedRows),
                        icon: const Icon(Icons.send_outlined),
                        label: Text(
                          '内容を確認して送る（${selectedRows.length}件）',
                        ),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(52),
                        ),
                      ),
                    ],
                  ),
      ),
    );
  }

  Future<void> _confirmAndSend(
    List<Map<String, dynamic>> selectedRows,
  ) async {
    final target = _targetCompanyName;
    final repository = _repository;
    if (target == null || repository == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('最終確認'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('送信先: $target'),
              Text('書類: ${selectedRows.length}件'),
              const SizedBox(height: 10),
              for (final row in selectedRows)
                Text('・${row['name']?.toString() ?? '書類'}'),
              const SizedBox(height: 12),
              const Text(
                '送信後も出所情報を保持し、受信会社から上位会社へ再転送できます。',
              ),
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
    if (confirmed != true || !mounted) return;

    setState(() => _sending = true);
    try {
      await repository.send(
        requestId: _newRequestId(),
        receiveCode: _codeController.text,
        items: [
          for (final row in selectedRows)
            {
              'id': row['id']?.toString(),
              'kind': 'worker_document',
            },
        ],
        note: _noteController.text,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$targetへ書類を送信しました')),
      );
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('送信できませんでした: $error')),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  String _newRequestId() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes
        .map((value) => value.toRadixString(16).padLeft(2, '0'))
        .join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }
}
