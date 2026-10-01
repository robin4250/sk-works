import 'dart:math';

import 'package:flutter/material.dart';

import 'company_document_exchange_repository.dart';

class CompanyTransferSendPage extends StatefulWidget {
  const CompanyTransferSendPage({
    super.key,
    required this.title,
    required this.sourceKind,
    required this.subjectLabel,
    required this.workerIds,
    required this.description,
  });

  final String title;
  final String sourceKind;
  final String subjectLabel;
  final Set<String> workerIds;
  final String description;

  @override
  State<CompanyTransferSendPage> createState() =>
      _CompanyTransferSendPageState();
}

class _CompanyTransferSendPageState extends State<CompanyTransferSendPage> {
  final _repository = CompanyDocumentExchangeRepository.maybeCreate();
  final _search = TextEditingController();
  final _note = TextEditingController();
  List<Map<String, dynamic>> _sources = const [];
  List<Map<String, dynamic>> _targets = const [];
  final Set<String> _selected = <String>{};
  String? _targetCompanyId;
  bool _sendAll = true;
  bool _loading = true;
  bool _sending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final repository = _repository;
    if (repository == null) {
      setState(() {
        _loading = false;
        _error = '会社間送信を利用できません。';
      });
      return;
    }
    try {
      final values = await Future.wait([
        repository.listSendableSources(),
        repository.listTransferTargets(),
      ]);
      final sources = (values[0] as List<Map<String, dynamic>>).where((row) {
        if (row['kind']?.toString() != widget.sourceKind) return false;
        final workerId = row['worker_id']?.toString();
        return widget.workerIds.isEmpty ||
            (workerId != null && widget.workerIds.contains(workerId));
      }).toList(growable: false);
      final targets = values[1] as List<Map<String, dynamic>>;
      if (!mounted) return;
      setState(() {
        _sources = sources;
        _targets = targets;
        _selected
          ..clear()
          ..addAll(sources
              .map((row) => row['id']?.toString() ?? '')
              .where((id) => id.isNotEmpty));
        if (targets.length == 1) {
          _targetCompanyId = targets.first['company_id']?.toString();
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

  List<Map<String, dynamic>> get _filtered {
    final needle = _search.text.trim().toLowerCase();
    if (needle.isEmpty) return _sources;
    return _sources.where((row) {
      final text = [
        row['name'],
        row['group'],
      ].whereType<Object>().join(' ').toLowerCase();
      return text.contains(needle);
    }).toList(growable: false);
  }

  List<Map<String, dynamic>> get _selectedRows => _sources
      .where((row) => _selected.contains(row['id']?.toString()))
      .toList(growable: false);

  Map<String, dynamic>? get _target {
    for (final target in _targets) {
      if (target['company_id']?.toString() == _targetCompanyId) return target;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    final selectedRows = _sendAll ? _sources : _selectedRows;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title,
            style: const TextStyle(fontWeight: FontWeight.w900)),
      ),
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
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                    children: [
                      const Text(
                        '1. 送信先会社を選択',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        initialValue: _targetCompanyId,
                        decoration: const InputDecoration(
                          labelText: '接続済み会社',
                          border: OutlineInputBorder(),
                        ),
                        items: [
                          for (final target in _targets)
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
                      if (_targets.isEmpty)
                        const Padding(
                          padding: EdgeInsets.only(top: 8),
                          child: Text('送信できる接続済み親会社がありません。'),
                        ),
                      const SizedBox(height: 20),
                      const Text(
                        '2. 送信方法',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 8),
                      SegmentedButton<bool>(
                        segments: const [
                          ButtonSegment(value: true, label: Text('全部送る')),
                          ButtonSegment(value: false, label: Text('選んで送る')),
                        ],
                        selected: {_sendAll},
                        onSelectionChanged: (values) {
                          if (values.isNotEmpty) {
                            setState(() => _sendAll = values.first);
                          }
                        },
                      ),
                      const SizedBox(height: 8),
                      Text(widget.description),
                      if (!_sendAll) ...[
                        const SizedBox(height: 14),
                        TextField(
                          controller: _search,
                          decoration: InputDecoration(
                            prefixIcon: const Icon(Icons.search),
                            labelText: widget.subjectLabel + 'を検索',
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                        const SizedBox(height: 8),
                        for (final row in filtered)
                          CheckboxListTile(
                            value:
                                _selected.contains(row['id']?.toString()),
                            title: Text(row['name']?.toString() ??
                                widget.subjectLabel),
                            subtitle: row['group'] == null
                                ? null
                                : Text(row['group'].toString()),
                            onChanged: (value) {
                              final id = row['id']?.toString() ?? '';
                              if (id.isEmpty) return;
                              setState(() {
                                if (value == true) {
                                  _selected.add(id);
                                } else {
                                  _selected.remove(id);
                                }
                              });
                            },
                          ),
                      ],
                      const SizedBox(height: 16),
                      TextField(
                        controller: _note,
                        maxLines: 3,
                        maxLength: 2000,
                        decoration: const InputDecoration(
                          labelText: '案内・備考メモ',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const Text(
                                '選択済み対象',
                                style: TextStyle(fontWeight: FontWeight.w900),
                              ),
                              const SizedBox(height: 6),
                              SizedBox(
                                height: selectedRows.length > 5 ? 180 : null,
                                child: SingleChildScrollView(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      for (final row in selectedRows)
                                        Text('・' +
                                            (row['name']?.toString() ??
                                                widget.subjectLabel)),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: _sending ||
                                _targetCompanyId == null ||
                                selectedRows.isEmpty
                            ? null
                            : () => _confirmAndSend(selectedRows),
                        icon: const Icon(Icons.send_outlined),
                        label: const Text('確定して送信'),
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
    final repository = _repository;
    final target = _target;
    final targetId = _targetCompanyId;
    if (repository == null || target == null || targetId == null) return;
    final targetName = target['company_name']?.toString() ?? '選択した会社';
    final mode = _sendAll ? '一覧送信（全部送る）' : '個別選択送信';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('送信内容の最終確認'),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  targetName + 'へ' + widget.subjectLabel + 'データを送信します',
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 8),
                Text('送信方法：' + mode),
                Text('件数：' + selectedRows.length.toString() + '件'),
                const Divider(height: 20),
                for (final row in selectedRows)
                  Text('・' +
                      (row['name']?.toString() ?? widget.subjectLabel)),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('戻る'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('確定して送信'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _sending = true);
    try {
      await repository.sendConnected(
        requestId: _newRequestId(),
        targetCompanyId: targetId,
        items: [
          for (final row in selectedRows)
            {
              'id': row['id']?.toString(),
              'kind': widget.sourceKind,
            },
        ],
        note: _note.text,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(targetName + 'へ送信しました')),
      );
      Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('送信できませんでした: ' + error.toString())),
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
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-'
        '${hex.substring(20)}';
  }
}
