import 'dart:math';

import 'package:flutter/material.dart';

import 'company_document_exchange_repository.dart';

enum CompanyDataSendKind {
  personnel,
  qualification,
  workerDocument,
}

extension CompanyDataSendKindLabel on CompanyDataSendKind {
  String get sourceKind => switch (this) {
        CompanyDataSendKind.personnel => 'worker_personnel',
        CompanyDataSendKind.qualification => 'worker_qualification',
        CompanyDataSendKind.workerDocument => 'worker_document',
      };

  String get label => switch (this) {
        CompanyDataSendKind.personnel => '社員',
        CompanyDataSendKind.qualification => '資格',
        CompanyDataSendKind.workerDocument => '必要書類',
      };

  String get description => switch (this) {
        CompanyDataSendKind.personnel => '基本情報＋資格＋元請向け書類を一式で送信します。',
        CompanyDataSendKind.qualification => '選択した社員の資格情報だけを送信します。',
        CompanyDataSendKind.workerDocument => '元請向けの必要書類だけを送信します。',
      };
}

class UnifiedCompanyDataSendPage extends StatefulWidget {
  const UnifiedCompanyDataSendPage({
    super.key,
    required this.kind,
    required this.workerIds,
  });

  final CompanyDataSendKind kind;
  final Set<String> workerIds;

  @override
  State<UnifiedCompanyDataSendPage> createState() =>
      _UnifiedCompanyDataSendPageState();
}

class _UnifiedCompanyDataSendPageState
    extends State<UnifiedCompanyDataSendPage> {
  final _repository = CompanyDocumentExchangeRepository.maybeCreate();
  final _search = TextEditingController();
  final _note = TextEditingController();

  List<Map<String, dynamic>> _sources = const [];
  List<Map<String, dynamic>> _targets = const [];
  final Set<String> _selectedIds = <String>{};

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
      final allSources = values[0] as List<Map<String, dynamic>>;
      final targets = values[1] as List<Map<String, dynamic>>;
      final filtered = allSources.where((row) {
        if (row['kind']?.toString() != widget.kind.sourceKind) return false;
        if (widget.workerIds.isEmpty) return true;
        final workerId = row['worker_id']?.toString();
        return workerId != null && widget.workerIds.contains(workerId);
      }).toList(growable: false);

      if (!mounted) return;
      setState(() {
        _sources = filtered;
        _targets = targets;
        _selectedIds
          ..clear()
          ..addAll(
            filtered
                .map((row) => row['id']?.toString() ?? '')
                .where((id) => id.isNotEmpty),
          );
        _targetCompanyId =
            targets.length == 1 ? targets.first['company_id']?.toString() : null;
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

  List<Map<String, dynamic>> get _visibleSources {
    final query = _search.text.trim().toLowerCase();
    if (query.isEmpty) return _sources;
    return _sources.where((row) {
      final text = [
        row['name'],
        row['group'],
      ].whereType<Object?>().join(' ').toLowerCase();
      return text.contains(query);
    }).toList(growable: false);
  }

  List<Map<String, dynamic>> get _selectedRows => _sources
      .where((row) => _selectedIds.contains(row['id']?.toString()))
      .toList(growable: false);

  Map<String, dynamic>? get _target {
    final id = _targetCompanyId;
    if (id == null) return null;
    for (final item in _targets) {
      if (item['company_id']?.toString() == id) return item;
    }
    return null;
  }

  void _setMode(bool sendAll) {
    setState(() {
      _sendAll = sendAll;
      if (sendAll) {
        _selectedIds
          ..clear()
          ..addAll(
            _sources
                .map((row) => row['id']?.toString() ?? '')
                .where((id) => id.isNotEmpty),
          );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final selected = _selectedRows;
    final target = _target;
    final targetName = target?['company_name']?.toString() ?? '';

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.kind.label + 'を会社へ送信'),
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
                        '送信先会社',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (_targets.isEmpty)
                        const Card(
                          child: Padding(
                            padding: EdgeInsets.all(18),
                            child: Text(
                              '接続済みの親会社がありません。先に会社接続を完了してください。',
                            ),
                          ),
                        )
                      else
                        DropdownButtonFormField<String>(
                          initialValue: _targetCompanyId,
                          decoration: const InputDecoration(
                            labelText: '接続済み会社から選択',
                            prefixIcon: Icon(Icons.business_outlined),
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
                      const SizedBox(height: 20),
                      const Text(
                        '送信方法',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 8),
                      SegmentedButton<bool>(
                        segments: const [
                          ButtonSegment(
                            value: true,
                            label: Text('全部送る'),
                            icon: Icon(Icons.select_all),
                          ),
                          ButtonSegment(
                            value: false,
                            label: Text('選んで送る'),
                            icon: Icon(Icons.checklist_outlined),
                          ),
                        ],
                        selected: {_sendAll},
                        onSelectionChanged: (value) =>
                            _setMode(value.first),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _search,
                        decoration: InputDecoration(
                          labelText: widget.kind.label + 'を検索',
                          prefixIcon: const Icon(Icons.search),
                          border: const OutlineInputBorder(),
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                      const SizedBox(height: 8),
                      Text(widget.kind.description),
                      const SizedBox(height: 8),
                      if (_sources.isEmpty)
                        const Card(
                          child: Padding(
                            padding: EdgeInsets.all(18),
                            child: Text('送信できるデータがありません'),
                          ),
                        )
                      else
                        for (final row in _visibleSources)
                          CheckboxListTile(
                            value: _selectedIds
                                .contains(row['id']?.toString()),
                            onChanged: _sendAll
                                ? null
                                : (value) {
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
                              row['name']?.toString() ?? widget.kind.label,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            subtitle: row['group'] == null
                                ? null
                                : Text(row['group'].toString()),
                            controlAffinity:
                                ListTileControlAffinity.leading,
                          ),
                      const SizedBox(height: 12),
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
                      if (target != null && selected.isNotEmpty)
                        Card(
                          color: Theme.of(context)
                              .colorScheme
                              .primaryContainer,
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.stretch,
                              children: [
                                Text(
                                  targetName +
                                      'へ' +
                                      widget.kind.label +
                                      'データを送信します',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w900,
                                    fontSize: 17,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  _sendAll
                                      ? '送信方法: 一覧送信（全部送る）'
                                      : '送信方法: 個別選択送信',
                                ),
                                Text(
                                  '選択済み: ' +
                                      selected.length.toString() +
                                      '件',
                                ),
                                const SizedBox(height: 8),
                                ConstrainedBox(
                                  constraints:
                                      const BoxConstraints(maxHeight: 180),
                                  child: ListView(
                                    shrinkWrap: true,
                                    children: [
                                      for (final row in selected)
                                        Text(
                                          '・' +
                                              (row['name']?.toString() ??
                                                  widget.kind.label),
                                        ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: target == null ||
                                selected.isEmpty ||
                                _sending
                            ? null
                            : _confirmAndSend,
                        icon: const Icon(Icons.send_outlined),
                        label: Text(
                          _sending ? '送信中…' : '確定して送信',
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

  Future<void> _confirmAndSend() async {
    final repository = _repository;
    final target = _target;
    final selected = _selectedRows;
    if (repository == null || target == null || selected.isEmpty) return;

    final targetId = target['company_id']?.toString() ?? '';
    final targetName = target['company_name']?.toString() ?? '会社';
    if (targetId.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('最終確認'),
        content: Text(
          targetName +
              'へ' +
              widget.kind.label +
              'データを' +
              selected.length.toString() +
              '件送信します。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('戻る'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('確定して送信'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _sending = true);
    try {
      await repository.sendConnected(
        requestId: _newRequestId(),
        targetCompanyId: targetId,
        items: [
          for (final row in selected)
            {
              'id': row['id']?.toString(),
              'kind': widget.kind.sourceKind,
            },
        ],
        note: _note.text,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            targetName + 'へ' + widget.kind.label + 'データを送信しました',
          ),
        ),
      );
      Navigator.of(context).pop(true);
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
