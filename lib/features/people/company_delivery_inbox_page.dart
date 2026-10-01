import 'dart:math';

import 'package:flutter/material.dart';

import 'company_document_exchange_repository.dart';

class CompanyDeliveryInboxPage extends StatefulWidget {
  const CompanyDeliveryInboxPage({super.key});

  @override
  State<CompanyDeliveryInboxPage> createState() =>
      _CompanyDeliveryInboxPageState();
}

class _CompanyDeliveryInboxPageState extends State<CompanyDeliveryInboxPage> {
  final _repository = CompanyDocumentExchangeRepository.maybeCreate();
  final _noteController = TextEditingController();

  final List<_ReceivedTransferItem> _items = [];
  final Set<String> _selectedKeys = {};
  bool _loading = true;
  bool _forwarding = false;
  List<Map<String, dynamic>> _transferTargets = const [];
  String? _targetCompanyId;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final repository = _repository;
    if (repository == null) {
      setState(() {
        _loading = false;
        _error = '会社間データ受渡しを利用できません。';
      });
      return;
    }

    try {
      final valuesTop = await Future.wait([
        repository.listDeliveries(),
        repository.listTransferTargets(),
      ]);
      final deliveries = valuesTop[0] as List<Map<String, dynamic>>;
      final transferTargets = valuesTop[1] as List<Map<String, dynamic>>;
      final received = deliveries
          .where((row) => row['received'] == true)
          .toList(growable: false);

      final loaded = <_ReceivedTransferItem>[];
      for (final delivery in received) {
        final deliveryId = delivery['id']?.toString() ?? '';
        if (deliveryId.isEmpty) continue;

        final values = await Future.wait([
          repository.listDeliveryItems(deliveryId),
          repository.listDeliveryDataItems(deliveryId),
        ]);
        final files = values[0];
        final data = values[1];

        for (final row in files) {
          loaded.add(
            _ReceivedTransferItem.file(
              row,
              fallbackCompany:
                  delivery['sender_name']?.toString() ?? '協力会社',
            ),
          );
        }
        for (final row in data) {
          loaded.add(
            _ReceivedTransferItem.data(
              row,
              fallbackCompany:
                  delivery['sender_name']?.toString() ?? '協力会社',
            ),
          );
        }
      }

      if (!mounted) return;
      setState(() {
        _items
          ..clear()
          ..addAll(loaded);
        _selectedKeys.clear();
        _transferTargets = transferTargets;
        if (_targetCompanyId != null &&
            !transferTargets.any(
              (row) => row['company_id']?.toString() == _targetCompanyId,
            )) {
          _targetCompanyId = null;
        }
        if (_targetCompanyId == null && transferTargets.length == 1) {
          _targetCompanyId = transferTargets.first['company_id']?.toString();
        }
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
    final grouped = <String, List<_ReceivedTransferItem>>{};
    for (final item in _items) {
      grouped.putIfAbsent(item.originCompany, () => []).add(item);
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('協力会社'),
        actions: [
          IconButton(
            tooltip: '再読み込み',
            onPressed: _loading ? null : _reload,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? _ErrorState(message: _error!, onRetry: _reload)
                : ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      const Text(
                        '出所会社ごとに整理しています。受け取った情報は出所を保持したまま上位会社へ再転送できます。',
                      ),
                      const SizedBox(height: 12),
                      if (grouped.isEmpty)
                        const Card(
                          child: Padding(
                            padding: EdgeInsets.all(18),
                            child: Text('受信データはまだありません'),
                          ),
                        )
                      else
                        for (final entry in grouped.entries)
                          Card(
                            child: ExpansionTile(
                              leading: const CircleAvatar(
                                child: Icon(Icons.folder_outlined),
                              ),
                              title: Text(
                                entry.key,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              subtitle: Text('${entry.value.length}件'),
                              children: [
                                for (final category
                                    in _ReceivedTransferCategory.values)
                                  if (entry.value.any(
                                    (item) => item.category == category,
                                  )) ...[
                                    Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                        20,
                                        12,
                                        20,
                                        4,
                                      ),
                                      child: Align(
                                        alignment: Alignment.centerLeft,
                                        child: Text(
                                          category.label,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w900,
                                          ),
                                        ),
                                      ),
                                    ),
                                    for (final item in entry.value.where(
                                      (item) => item.category == category,
                                    ))
                                      CheckboxListTile(
                                        value:
                                            _selectedKeys.contains(item.key),
                                        onChanged: (value) {
                                          setState(() {
                                            if (value == true) {
                                              _selectedKeys.add(item.key);
                                            } else {
                                              _selectedKeys.remove(item.key);
                                            }
                                          });
                                        },
                                        title: Text(
                                          item.title,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                        subtitle: Text(item.subtitle),
                                        controlAffinity:
                                            ListTileControlAffinity.leading,
                                      ),
                                  ],
                              ],
                            ),
                          ),
                      if (_selectedKeys.isNotEmpty) ...[
                        const SizedBox(height: 20),
                        const Text(
                          '上位会社へ再転送',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 8),
                        DropdownButtonFormField<String>(
                          initialValue: _targetCompanyId,
                          decoration: const InputDecoration(
                            labelText: '接続済み親会社',
                            border: OutlineInputBorder(),
                          ),
                          items: [
                            for (final target in _transferTargets)
                              DropdownMenuItem(
                                value: target['company_id']?.toString(),
                                child: Text(
                                  target['company_name']?.toString() ?? '会社',
                                ),
                              ),
                          ],
                          onChanged: (value) =>
                              setState(() => _targetCompanyId = value),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _noteController,
                          maxLines: 3,
                          maxLength: 2000,
                          decoration: const InputDecoration(
                            labelText: '案内・備考（任意）',
                          ),
                        ),
                        const SizedBox(height: 8),
                        FilledButton.icon(
                          onPressed: _targetCompanyId == null || _forwarding
                              ? null
                              : _confirmAndForward,
                          icon: const Icon(Icons.forward_to_inbox_outlined),
                          label: Text(
                            '内容を確認して再転送（${_selectedKeys.length}件）',
                          ),
                          style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(52),
                          ),
                        ),
                      ],
                    ],
                  ),
      ),
    );
  }

  Future<void> _confirmAndForward() async {
    final repository = _repository;
    final targetId = _targetCompanyId;
    if (repository == null || targetId == null) return;
    final targetRow = _transferTargets.where(
      (row) => row['company_id']?.toString() == targetId,
    );
    if (targetRow.isEmpty) return;
    final target =
        targetRow.first['company_name']?.toString() ?? '選択した会社';

    final selected = _items
        .where((item) => _selectedKeys.contains(item.key))
        .toList(growable: false);
    if (selected.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('再転送の最終確認'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('送信先: $target'),
              Text('対象: ${selected.length}件'),
              const SizedBox(height: 10),
              for (final item in selected) Text('・${item.title}'),
              const SizedBox(height: 12),
              const Text('元の出所会社と転送経路を保持したまま送信します。'),
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
            child: const Text('この内容で再転送'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _forwarding = true);
    try {
      await repository.sendConnected(
        requestId: _newRequestId(),
        targetCompanyId: targetId,
        items: [
          for (final item in selected)
            {
              'id': item.id,
              'kind': item.isStructured ? 'received_data' : 'received',
            },
        ],
        note: _noteController.text,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$targetへ再転送しました')),
      );
      _noteController.clear();
      setState(() {
        _selectedKeys.clear();
      });
      await _load();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('再転送できませんでした: $error')),
      );
    } finally {
      if (mounted) setState(() => _forwarding = false);
    }
  }

  void _reload() {
    setState(() => _loading = true);
    _load();
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

enum _ReceivedTransferCategory {
  personnel('従業員一覧'),
  qualifications('資格証一覧'),
  workerDocuments('従業員提出書類一覧'),
  companyDocuments('会社提出書類一覧');

  const _ReceivedTransferCategory(this.label);

  final String label;
}

class _ReceivedTransferItem {
  const _ReceivedTransferItem({
    required this.id,
    required this.isStructured,
    required this.category,
    required this.originCompany,
    required this.title,
    required this.subtitle,
  });

  final String id;
  final bool isStructured;
  final _ReceivedTransferCategory category;
  final String originCompany;
  final String title;
  final String subtitle;

  String get key => '${isStructured ? 'data' : 'file'}:$id';

  factory _ReceivedTransferItem.file(
    Map<String, dynamic> row, {
    required String fallbackCompany,
  }) {
    final path = _companyPath(row['company_path']);
    final bucket = row['bucket']?.toString() ?? '';
    final category = switch (bucket) {
      'qualification-certificates' =>
        _ReceivedTransferCategory.qualifications,
      'worker-documents' => _ReceivedTransferCategory.workerDocuments,
      'company-required-documents' ||
      'partner-archive-documents' =>
        _ReceivedTransferCategory.companyDocuments,
      _ => _ReceivedTransferCategory.companyDocuments,
    };
    return _ReceivedTransferItem(
      id: row['id']?.toString() ?? '',
      isStructured: false,
      category: category,
      originCompany: _origin(path, fallbackCompany),
      title: row['name']?.toString() ?? '書類',
      subtitle: [
        '書類',
        if (path.isNotEmpty) '経路 ${path.join(' → ')}',
      ].join(' / '),
    );
  }

  factory _ReceivedTransferItem.data(
    Map<String, dynamic> row, {
    required String fallbackCompany,
  }) {
    final path = _companyPath(row['company_path']);
    final payload = row['payload'] is Map
        ? Map<String, dynamic>.from(row['payload'] as Map)
        : <String, dynamic>{};
    final kind = row['payload_kind']?.toString() ?? 'data';
    final title = switch (kind) {
      'personnel' => payload['name']?.toString() ?? '人員情報',
      'qualification' =>
        '${payload['worker_name']?.toString() ?? ''} / ${payload['qualification_name']?.toString() ?? '資格'}',
      _ => '受信データ',
    };
    final category = switch (kind) {
      'personnel' => _ReceivedTransferCategory.personnel,
      'qualification' => _ReceivedTransferCategory.qualifications,
      _ => _ReceivedTransferCategory.personnel,
    };
    return _ReceivedTransferItem(
      id: row['id']?.toString() ?? '',
      isStructured: true,
      category: category,
      originCompany: _origin(path, fallbackCompany),
      title: title,
      subtitle: [
        kind == 'personnel' ? '人員情報' : kind == 'qualification' ? '資格' : kind,
        if (path.isNotEmpty) '経路 ${path.join(' → ')}',
      ].join(' / '),
    );
  }

  static List<String> _companyPath(Object? value) {
    if (value is! List) return const [];
    return value.map((item) => item.toString()).toList(growable: false);
  }

  static String _origin(List<String> path, String fallback) {
    if (path.isEmpty) return fallback;
    return path.last;
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: onRetry,
              child: const Text('再試行'),
            ),
          ],
        ),
      ),
    );
  }
}
