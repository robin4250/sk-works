import 'package:flutter/material.dart';

import 'qualification_cloud_repository.dart';

class QualificationCloudPage extends StatefulWidget {
  const QualificationCloudPage({super.key});

  @override
  State<QualificationCloudPage> createState() => _QualificationCloudPageState();
}

class _QualificationCloudPageState extends State<QualificationCloudPage> {
  final _repository = QualificationCloudRepository.maybeCreate();
  final _queryController = TextEditingController();

  List<Map<String, dynamic>> _masters = [];
  List<Map<String, dynamic>> _workers = [];
  List<Map<String, dynamic>> _qualifications = [];
  bool _loading = true;
  bool _canManageMaster = false;
  bool _canManageWorkerQualifications = false;
  bool _showExpiringOnly = false;
  String _query = '';
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _queryController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final repository = _repository;
    if (repository == null) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Supabase接続が利用できません。';
      });
      return;
    }

    try {
      final values = await Future.wait([
        repository.loadAll(),
        repository.canManageMaster(),
        repository.canManageWorkerQualifications(),
      ]);
      final data = values[0] as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _masters = List<Map<String, dynamic>>.from(data['masters'] as List);
        _workers = List<Map<String, dynamic>>.from(data['workers'] as List);
        _qualifications = List<Map<String, dynamic>>.from(data['qualifications'] as List);
        _canManageMaster = values[1] as bool;
        _canManageWorkerQualifications = values[2] as bool;
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
    final now = DateTime.now();
    final masterById = {
      for (final row in _masters) row['id']?.toString() ?? '': row,
    };
    final workerById = {
      for (final row in _workers) row['id']?.toString() ?? '': row,
    };
    final needle = _query.trim().toLowerCase();

    final filtered = _qualifications.where((row) {
      final master = masterById[row['qualification_master_id']?.toString() ?? ''];
      final worker = workerById[row['worker_id']?.toString() ?? ''];
      final expiry = _parseDate(row['expires_at']);
      final isExpired = expiry != null && expiry.isBefore(_dateOnly(now));
      final isExpiringSoon = expiry != null &&
          !isExpired &&
          !expiry.isAfter(_dateOnly(now).add(const Duration(days: 90)));
      final matchesExpiry = !_showExpiringOnly || isExpired || isExpiringSoon;
      final haystack = [
        master?['name'],
        master?['issuer'],
        worker?['name'],
        row['certificate_number'],
        row['issuer'],
        row['notes'],
      ].whereType<Object>().join(' ').toLowerCase();
      final matchesQuery = needle.isEmpty || haystack.contains(needle);
      return matchesExpiry && matchesQuery;
    }).toList(growable: false);

    return Scaffold(
      appBar: AppBar(
        title: const Text('資格管理'),
        actions: [
          IconButton(
            tooltip: '資格マスター追加',
            onPressed: _loading || !_canManageMaster ? null : _addMaster,
            icon: const Icon(Icons.library_add_outlined),
          ),
          IconButton(
            tooltip: '再読み込み',
            onPressed: _loading
                ? null
                : () {
                    setState(() => _loading = true);
                    _load();
                  },
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _loading || !_canManageWorkerQualifications
            ? null
            : _addQualification,
        icon: const Icon(Icons.add_card),
        label: const Text('資格登録'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: TextField(
                controller: _queryController,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: '資格名・保有者・証明書番号で検索',
                ),
                onChanged: (value) => setState(() => _query = value),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  FilterChip(
                    label: const Text('期限切れ・90日以内'),
                    selected: _showExpiringOnly,
                    onSelected: (value) => setState(() => _showExpiringOnly = value),
                  ),
                  const Spacer(),
                  Text('${filtered.length}件'),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? _ErrorState(message: _error!, onRetry: _load)
                      : filtered.isEmpty
                          ? _EmptyState(
                              hasMaster: _masters.isNotEmpty,
                              hasWorker: _workers.isNotEmpty,
                              onAddMaster: _canManageMaster ? _addMaster : null,
                              onAddQualification: _canManageWorkerQualifications
                                  ? _addQualification
                                  : null,
                            )
                          : ListView.separated(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
                              itemCount: filtered.length,
                              separatorBuilder: (_, __) => const SizedBox(height: 8),
                              itemBuilder: (context, index) {
                                final row = filtered[index];
                                final master = masterById[
                                    row['qualification_master_id']?.toString() ?? ''];
                                final worker = workerById[row['worker_id']?.toString() ?? ''];
                                final expiry = _parseDate(row['expires_at']);
                                final status = _expiryLabel(expiry, now);
                                return Card(
                                  child: ListTile(
                                    leading: const CircleAvatar(
                                      child: Icon(Icons.badge_outlined),
                                    ),
                                    title: Text(
                                      master?['name']?.toString() ?? '資格',
                                      style: const TextStyle(fontWeight: FontWeight.w700),
                                    ),
                                    subtitle: Text(
                                      [
                                        worker?['name']?.toString() ?? '保有者不明',
                                        if ((row['certificate_number']?.toString() ?? '').isNotEmpty)
                                          '証明書 ${row['certificate_number']}',
                                        status,
                                      ].join(' / '),
                                    ),
                                    trailing: const Icon(Icons.chevron_right),
                                    onTap: () => _showDetails(
                                      row,
                                      master,
                                      worker,
                                      status,
                                    ),
                                  ),
                                );
                              },
                            ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _addMaster() async {
    final repository = _repository;
    if (repository == null) return;
    final nameController = TextEditingController();
    final categoryController = TextEditingController();
    final issuerController = TextEditingController();
    final notesController = TextEditingController();
    var expiryRequired = false;

    final draft = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('資格マスター追加'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: '資格・免許・講習名 *'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: categoryController,
                  decoration: const InputDecoration(labelText: '分類'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: issuerController,
                  decoration: const InputDecoration(labelText: '発行元・実施機関'),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('有効期限あり'),
                  value: expiryRequired,
                  onChanged: (value) => setDialogState(() => expiryRequired = value),
                ),
                TextField(
                  controller: notesController,
                  decoration: const InputDecoration(labelText: '備考'),
                  maxLines: 2,
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
                if (nameController.text.trim().isEmpty) return;
                Navigator.pop(dialogContext, {
                  'name': nameController.text.trim(),
                  'category': categoryController.text.trim(),
                  'issuer': issuerController.text.trim(),
                  'expiryRequired': expiryRequired,
                  'notes': notesController.text.trim(),
                });
              },
              child: const Text('追加'),
            ),
          ],
        ),
      ),
    );

    nameController.dispose();
    categoryController.dispose();
    issuerController.dispose();
    notesController.dispose();
    if (draft == null) return;

    try {
      final inserted = await repository.insertMaster(
        name: draft['name'] as String,
        category: draft['category'] as String,
        issuer: draft['issuer'] as String,
        expiryRequired: draft['expiryRequired'] as bool,
        notes: draft['notes'] as String,
      );
      if (!mounted) return;
      setState(() => _masters.add(inserted));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('資格マスターを追加しました')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('追加できませんでした: $error')),
      );
    }
  }

  Future<void> _addQualification() async {
    final repository = _repository;
    if (repository == null) return;
    if (_masters.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('先に資格マスターを追加してください')),
      );
      return;
    }
    if (_workers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('先に社員・作業員を登録してください')),
      );
      return;
    }

    var workerId = _workers.first['id']?.toString();
    var masterId = _masters.first['id']?.toString();
    final certificateController = TextEditingController();
    final issuerController = TextEditingController();
    final notesController = TextEditingController();
    DateTime? issuedAt;
    DateTime? expiresAt;

    final draft = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('資格登録'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: workerId,
                  decoration: const InputDecoration(labelText: '保有者'),
                  items: _workers
                      .map(
                        (row) => DropdownMenuItem<String>(
                          value: row['id']?.toString(),
                          child: Text(row['name']?.toString() ?? ''),
                        ),
                      )
                      .toList(),
                  onChanged: (value) => setDialogState(() => workerId = value),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: masterId,
                  decoration: const InputDecoration(labelText: '資格・免許・講習'),
                  items: _masters
                      .map(
                        (row) => DropdownMenuItem<String>(
                          value: row['id']?.toString(),
                          child: Text(row['name']?.toString() ?? ''),
                        ),
                      )
                      .toList(),
                  onChanged: (value) => setDialogState(() => masterId = value),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: certificateController,
                  decoration: const InputDecoration(labelText: '証明書番号'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: issuerController,
                  decoration: const InputDecoration(labelText: '発行元'),
                ),
                const SizedBox(height: 12),
                _DateRow(
                  label: '取得日',
                  value: issuedAt,
                  onTap: () async {
                    final picked = await _pickDate(dialogContext, issuedAt);
                    if (picked != null) setDialogState(() => issuedAt = picked);
                  },
                ),
                _DateRow(
                  label: '有効期限',
                  value: expiresAt,
                  onTap: () async {
                    final picked = await _pickDate(dialogContext, expiresAt);
                    if (picked != null) setDialogState(() => expiresAt = picked);
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: notesController,
                  decoration: const InputDecoration(labelText: '備考'),
                  maxLines: 2,
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
              onPressed: workerId == null || masterId == null
                  ? null
                  : () => Navigator.pop(dialogContext, {
                        'workerId': workerId,
                        'masterId': masterId,
                        'certificateNumber': certificateController.text.trim(),
                        'issuer': issuerController.text.trim(),
                        'issuedAt': issuedAt,
                        'expiresAt': expiresAt,
                        'notes': notesController.text.trim(),
                      }),
              child: const Text('登録'),
            ),
          ],
        ),
      ),
    );

    certificateController.dispose();
    issuerController.dispose();
    notesController.dispose();
    if (draft == null) return;

    try {
      final inserted = await repository.insertWorkerQualification(
        workerId: draft['workerId'] as String,
        qualificationMasterId: draft['masterId'] as String,
        certificateNumber: draft['certificateNumber'] as String,
        issuer: draft['issuer'] as String,
        issuedAt: draft['issuedAt'] as DateTime?,
        expiresAt: draft['expiresAt'] as DateTime?,
        notes: draft['notes'] as String,
      );
      if (!mounted) return;
      setState(() => _qualifications.insert(0, inserted));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('資格をクラウドに登録しました')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('登録できませんでした: $error')),
      );
    }
  }

  Future<DateTime?> _pickDate(BuildContext context, DateTime? current) {
    final now = DateTime.now();
    return showDatePicker(
      context: context,
      initialDate: current ?? now,
      firstDate: DateTime(1950),
      lastDate: DateTime(now.year + 30),
    );
  }

  void _showDetails(
    Map<String, dynamic> row,
    Map<String, dynamic>? master,
    Map<String, dynamic>? worker,
    String status,
  ) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(master?['name']?.toString() ?? '資格',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              Text('保有者: ${worker?['name'] ?? '不明'}'),
              if ((master?['category']?.toString() ?? '').isNotEmpty)
                Text('分類: ${master?['category']}'),
              if ((row['issuer']?.toString() ?? '').isNotEmpty)
                Text('発行元: ${row['issuer']}'),
              if ((row['certificate_number']?.toString() ?? '').isNotEmpty)
                Text('証明書番号: ${row['certificate_number']}'),
              if (row['issued_at'] != null) Text('取得日: ${row['issued_at']}'),
              if (row['expires_at'] != null) Text('有効期限: ${row['expires_at']}'),
              Text('状態: $status'),
              if ((row['notes']?.toString() ?? '').isNotEmpty) Text('備考: ${row['notes']}'),
              if ((row['attachment_path']?.toString() ?? '').isNotEmpty)
                const Text('証明書画像: 登録済み'),
              const SizedBox(height: 16),
              if (_canManageWorkerQualifications)
                OutlinedButton.icon(
                  onPressed: () async {
                    Navigator.pop(sheetContext);
                    await _delete(row['id']?.toString() ?? '');
                  },
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('資格登録を削除'),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _delete(String id) async {
    if (id.isEmpty || _repository == null) return;
    try {
      await _repository.deleteWorkerQualification(id);
      if (!mounted) return;
      setState(() => _qualifications.removeWhere((row) => row['id']?.toString() == id));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('資格登録を削除しました')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('削除できませんでした: $error')),
      );
    }
  }

  DateTime? _parseDate(Object? value) {
    if (value == null) return null;
    return DateTime.tryParse(value.toString());
  }

  DateTime _dateOnly(DateTime value) => DateTime(value.year, value.month, value.day);

  String _expiryLabel(DateTime? expiry, DateTime now) {
    if (expiry == null) return '期限なし';
    final today = _dateOnly(now);
    final end = _dateOnly(expiry);
    if (end.isBefore(today)) return '期限切れ';
    if (!end.isAfter(today.add(const Duration(days: 90)))) return '90日以内に期限';
    return '期限 ${_formatDate(end)}';
  }

  String _formatDate(DateTime value) {
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    return '${value.year}/$month/$day';
  }
}

class _DateRow extends StatelessWidget {
  const _DateRow({required this.label, required this.value, required this.onTap});

  final String label;
  final DateTime? value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = value == null
        ? '未設定'
        : '${value!.year}/${value!.month.toString().padLeft(2, '0')}/${value!.day.toString().padLeft(2, '0')}';
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(label),
      subtitle: Text(text),
      trailing: const Icon(Icons.calendar_month_outlined),
      onTap: onTap,
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.hasMaster,
    required this.hasWorker,
    required this.onAddMaster,
    required this.onAddQualification,
  });

  final bool hasMaster;
  final bool hasWorker;
  final VoidCallback? onAddMaster;
  final VoidCallback? onAddQualification;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.badge_outlined, size: 48),
            const SizedBox(height: 12),
            const Text('資格登録はまだありません'),
            const SizedBox(height: 8),
            Text(
              !hasMaster
                  ? '最初に資格マスターを追加してください。'
                  : !hasWorker
                      ? '社員・作業員を登録すると資格を紐づけられます。'
                      : '資格登録ボタンから保有資格を追加できます。',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            if (!hasMaster && onAddMaster != null)
              FilledButton.icon(
                onPressed: onAddMaster,
                icon: const Icon(Icons.library_add_outlined),
                label: const Text('資格マスター追加'),
              )
            else if (hasWorker && onAddQualification != null)
              FilledButton.icon(
                onPressed: onAddQualification,
                icon: const Icon(Icons.add_card),
                label: const Text('資格登録'),
              ),
          ],
        ),
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
            const Icon(Icons.cloud_off_outlined, size: 42),
            const SizedBox(height: 12),
            const Text('クラウドデータを読み込めませんでした'),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('再試行'),
            ),
          ],
        ),
      ),
    );
  }
}
