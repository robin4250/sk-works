// ignore_for_file: prefer_interpolation_to_compose_strings

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

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
  Map<String, DateTime> _savedState = const {};
  List<Map<String, dynamic>> _incomingConnections = const [];
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
        repository.loadConnectionInbox(),
        repository.loadSavedDeliveryState(),
      ]);
      final deliveries = valuesTop[0] as List<Map<String, dynamic>>;
      final transferTargets = valuesTop[1] as List<Map<String, dynamic>>;
      final connectionInbox = valuesTop[2] as Map<String, dynamic>;
      final savedState = valuesTop[3] as Map<String, DateTime>;
      final incomingRaw = connectionInbox['incoming'];
      final incomingConnections = incomingRaw is List
          ? incomingRaw
              .whereType<Map>()
              .map((item) => Map<String, dynamic>.from(item))
              .toList(growable: false)
          : const <Map<String, dynamic>>[];
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
              deliveryId: deliveryId,
              savedAt: delivery['saved_at']?.toString() ?? '',
              fallbackCompany:
                  delivery['sender_name']?.toString() ?? '協力会社',
            ),
          );
        }
        for (final row in data) {
          loaded.add(
            _ReceivedTransferItem.data(
              row,
              deliveryId: deliveryId,
              savedAt: delivery['saved_at']?.toString() ?? '',
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
        _savedState = savedState;
        _incomingConnections = incomingConnections;
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


  Future<void> _openPrintPreview(
    String title,
    List<_ReceivedTransferItem> items,
  ) async {
    if (items.isEmpty) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _ReceivedDataPdfPreview(
          title: title,
          items: items,
        ),
      ),
    );
  }

  Future<void> _saveReceivedItems(
    Iterable<_ReceivedTransferItem> items,
  ) async {
    final repository = _repository;
    if (repository == null) return;
    final keys = items.map((item) => item.key).toList(growable: false);
    if (keys.isEmpty) return;
    await repository.saveDeliveryItems(keys);
    final savedState = await repository.loadSavedDeliveryState();
    if (!mounted) return;
    setState(() => _savedState = savedState);
  }

  Future<void> _showReceivedDetail(_ReceivedTransferItem item) async {
    final alreadySaved = _savedState.containsKey(item.key);
    final shouldSave = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(item.originCompany + 'からデータが届いています'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(item.title,
                style: const TextStyle(fontWeight: FontWeight.w900)),
            const SizedBox(height: 6),
            Text(item.subtitle),
            const SizedBox(height: 12),
            Text(alreadySaved ? 'このデータは保存済みです。' : '保存しますか'),
            const SizedBox(height: 4),
            const Text('保存先：協力会社 → 出所会社 → データ種別'),
          ],
        ),
        actions: [
          TextButton.icon(
            onPressed: () {
              Navigator.pop(dialogContext, false);
              _openPrintPreview(item.title, [item]);
            },
            icon: const Icon(Icons.print_outlined),
            label: const Text('印刷プレビュー'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(alreadySaved ? '閉じる' : 'あとで'),
          ),
          if (!alreadySaved)
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('保存する'),
            ),
        ],
      ),
    );
    if (shouldSave != true) return;
    try {
      await _saveReceivedItems([item]);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('保存しました'),
          content: Text(item.originCompany + 'の協力会社フォルダへ保存しました。'),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('保存したデータを開く'),
            ),
          ],
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('保存できませんでした: ' + error.toString())),
      );
    }
  }

  Future<void> _saveCompanyFolder(
    String companyName,
    List<_ReceivedTransferItem> items,
  ) async {
    final unsaved =
        items.where((item) => !_savedState.containsKey(item.key)).toList();
    if (unsaved.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(companyName + 'のデータはすべて保存済みです')),
      );
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('会社単位で一括保存'),
        content: Text(
          companyName +
              'から受信した' +
              unsaved.length.toString() +
              '件を協力会社フォルダへ保存します。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('戻る'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('一括保存'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _saveReceivedItems(unsaved);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(companyName + 'のデータを一括保存しました')),
    );
  }

  Future<void> _respondConnection(
    Map<String, dynamic> request,
    bool accept,
  ) async {
    final repository = _repository;
    if (repository == null) return;
    final id = request['id']?.toString() ?? '';
    if (id.isEmpty) return;
    final name = request['child_company_name']?.toString() ?? '会社';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(accept ? '会社接続を承認しますか？' : '会社接続を拒否しますか？'),
        content: Text(name),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('戻る'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(accept ? '承認する' : '拒否する'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await repository.respondCompanyConnection(
      connectionId: id,
      accept: accept,
    );
    _reload();
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
                      if (_incomingConnections.isNotEmpty) ...[
                        const Text(
                          '要対応',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 8),
                        for (final request in _incomingConnections)
                          Card(
                            child: ListTile(
                              leading: const CircleAvatar(
                                child: Icon(Icons.link_outlined),
                              ),
                              title: Text(
                                request['child_company_name']?.toString() ??
                                    '会社',
                              ),
                              subtitle: const Text('会社接続申請が届いています'),
                              trailing: Wrap(
                                children: [
                                  IconButton(
                                    tooltip: '拒否',
                                    onPressed: () =>
                                        _respondConnection(request, false),
                                    icon: const Icon(Icons.close),
                                  ),
                                  IconButton(
                                    tooltip: '承認',
                                    onPressed: () =>
                                        _respondConnection(request, true),
                                    icon: const Icon(Icons.check_circle_outline),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        const SizedBox(height: 16),
                      ],
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
                              subtitle: Text(
                                _companySubtitle(entry.value),
                              ),
                              trailing: Wrap(
                                children: [
                                  IconButton(
                                    tooltip: '一覧を印刷',
                                    onPressed: () => _openPrintPreview(
                                      entry.key,
                                      entry.value,
                                    ),
                                    icon: const Icon(Icons.print_outlined),
                                  ),
                                  IconButton(
                                    tooltip: '会社単位で一括保存',
                                    onPressed: () => _saveCompanyFolder(
                                      entry.key,
                                      entry.value,
                                    ),
                                    icon: const Icon(Icons.save_alt_outlined),
                                  ),
                                ],
                              ),
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
                                        subtitle: Text(
                                          _savedState.containsKey(item.key)
                                              ? item.subtitle + ' / 保存済み'
                                              : item.subtitle,
                                        ),
                                        secondary: IconButton(
                                          tooltip: _savedState.containsKey(item.key)
                                              ? '保存したデータを開く'
                                              : '詳細・保存',
                                          onPressed: () =>
                                              _showReceivedDetail(item),
                                          icon: Icon(
                                            _savedState.containsKey(item.key)
                                                ? Icons.folder_open_outlined
                                                : Icons.download_outlined,
                                          ),
                                        ),
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

  String _companySubtitle(List<_ReceivedTransferItem> items) {
    final saved = items
        .map((item) => _savedState[item.key])
        .whereType<DateTime>()
        .toList()
      ..sort();
    if (saved.isEmpty) return items.length.toString() + '件';
    final latest = saved.last;
    String two(int n) => n.toString().padLeft(2, '0');
    return items.length.toString() +
        '件 / 最終データ保存日 ' +
        latest.year.toString() +
        '/' +
        two(latest.month) +
        '/' +
        two(latest.day);
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
  personnel('社員'),
  qualifications('資格'),
  workerDocuments('必要書類'),
  companyDocuments('会社提出書類');

  const _ReceivedTransferCategory(this.label);

  final String label;
}

class _ReceivedTransferItem {
  const _ReceivedTransferItem({
    required this.id,
    required this.deliveryId,
    required this.savedAt,
    required this.isStructured,
    required this.category,
    required this.originCompany,
    required this.title,
    required this.subtitle,
  });

  final String id;
  final String deliveryId;
  final String savedAt;
  final bool isStructured;
  final _ReceivedTransferCategory category;
  final String originCompany;
  final String title;
  final String subtitle;

  String get key => '${isStructured ? 'data' : 'file'}:$id';

  factory _ReceivedTransferItem.file(
    Map<String, dynamic> row, {
    required String deliveryId,
    required String savedAt,
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
      deliveryId: deliveryId,
      savedAt: savedAt,
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
    required String deliveryId,
    required String savedAt,
    required String fallbackCompany,
  }) {
    final path = _companyPath(row['company_path']);
    final payload = row['payload'] is Map
        ? Map<String, dynamic>.from(row['payload'] as Map)
        : <String, dynamic>{};
    final kind = row['payload_kind']?.toString() ?? 'data';
    final title = switch (kind) {
      'personnel' => payload['name']?.toString() ?? '社員情報',
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
      deliveryId: deliveryId,
      savedAt: savedAt,
      isStructured: true,
      category: category,
      originCompany: _origin(path, fallbackCompany),
      title: title,
      subtitle: [
        kind == 'personnel' ? '社員情報' : kind == 'qualification' ? '資格' : kind,
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

class _ReceivedDataPdfPreview extends StatelessWidget {
  const _ReceivedDataPdfPreview({
    required this.title,
    required this.items,
  });

  final String title;
  final List<_ReceivedTransferItem> items;

  Future<List<int>> _buildPdf() async {
    final regular = await PdfGoogleFonts.notoSansJPRegular();
    final bold = await PdfGoogleFonts.notoSansJPBold();
    final document = pw.Document(
      theme: pw.ThemeData.withFont(base: regular, bold: bold),
    );
    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(14 * PdfPageFormat.mm),
        build: (_) => [
          pw.Text(
            title,
            style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 10),
          for (final item in items)
            pw.Container(
              margin: const pw.EdgeInsets.only(bottom: 7),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    item.title,
                    style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                  ),
                  pw.Text(item.category.label + ' / ' + item.originCompany),
                  if (item.subtitle.isNotEmpty) pw.Text(item.subtitle),
                ],
              ),
            ),
        ],
      ),
    );
    return document.save();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('印刷プレビュー')),
      body: PdfPreview(
        build: (_) => _buildPdf(),
        canChangePageFormat: false,
        canChangeOrientation: false,
        allowPrinting: true,
        allowSharing: true,
        pdfFileName: title + '.pdf',
      ),
    );
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
