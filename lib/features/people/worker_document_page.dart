import 'package:flutter/material.dart';

import 'worker_document_repository.dart';

class WorkerDocumentPage extends StatefulWidget {
  const WorkerDocumentPage({super.key});

  @override
  State<WorkerDocumentPage> createState() => _WorkerDocumentPageState();
}

class _WorkerDocumentPageState extends State<WorkerDocumentPage> {
  final _repository = WorkerDocumentRepository.maybeCreate();

  List<Map<String, dynamic>> _workers = [];
  List<Map<String, dynamic>> _requirements = [];
  List<Map<String, dynamic>> _statuses = [];
  bool _loading = true;
  String? _error;
  String? _selectedWorkerId;
  String _scope = 'all';

  @override
  void initState() {
    super.initState();
    _load();
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
      final data = await repository.loadAll();
      if (!mounted) return;
      final workers = data['workers'] ?? const <Map<String, dynamic>>[];
      setState(() {
        _workers = workers;
        _requirements = data['requirements'] ?? const <Map<String, dynamic>>[];
        _statuses = data['statuses'] ?? const <Map<String, dynamic>>[];
        if (_selectedWorkerId == null ||
            !_workers.any((row) => row['id']?.toString() == _selectedWorkerId)) {
          _selectedWorkerId = _workers.isEmpty ? null : _workers.first['id']?.toString();
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
    final workerId = _selectedWorkerId;
    final visibleRequirements = _requirements
        .where((row) => _scope == 'all' || row['scope']?.toString() == _scope)
        .toList(growable: false);
    final statusByRequirement = <String, Map<String, dynamic>>{
      for (final row in _statuses.where((row) => row['worker_id']?.toString() == workerId))
        row['requirement_id']?.toString() ?? '': row,
    };
    final completed = visibleRequirements.where((requirement) {
      final status = statusByRequirement[requirement['id']?.toString()]?['status']?.toString();
      return status == 'submitted' || status == 'verified';
    }).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('必要書類チェック'),
        actions: [
          IconButton(
            tooltip: '標準項目を追加',
            onPressed: _loading ? null : _addDefaults,
            icon: const Icon(Icons.playlist_add_check_circle_outlined),
          ),
          IconButton(
            tooltip: '自由項目を追加',
            onPressed: _loading ? null : _addRequirement,
            icon: const Icon(Icons.add_circle_outline),
          ),
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
                : _workers.isEmpty
                    ? const Center(child: Text('先に社員・作業員を登録してください'))
                    : Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                            child: DropdownButtonFormField<String>(
                              initialValue: _selectedWorkerId,
                              decoration: const InputDecoration(
                                labelText: '対象者',
                                prefixIcon: Icon(Icons.person_outline),
                              ),
                              items: _workers
                                  .map(
                                    (row) => DropdownMenuItem<String>(
                                      value: row['id']?.toString(),
                                      child: Text(row['name']?.toString() ?? ''),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (value) => setState(() => _selectedWorkerId = value),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Row(
                              children: [
                                FilterChip(
                                  label: const Text('すべて'),
                                  selected: _scope == 'all',
                                  onSelected: (_) => setState(() => _scope = 'all'),
                                ),
                                const SizedBox(width: 8),
                                FilterChip(
                                  label: const Text('社内'),
                                  selected: _scope == 'internal',
                                  onSelected: (_) => setState(() => _scope = 'internal'),
                                ),
                                const SizedBox(width: 8),
                                FilterChip(
                                  label: const Text('元請・得意先'),
                                  selected: _scope == 'upstream',
                                  onSelected: (_) => setState(() => _scope = 'upstream'),
                                ),
                                const Spacer(),
                                Text('$completed/${visibleRequirements.length}'),
                              ],
                            ),
                          ),
                          const SizedBox(height: 8),
                          Expanded(
                            child: _requirements.isEmpty
                                ? _EmptyState(onAddDefaults: _addDefaults)
                                : ListView.separated(
                                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                                    itemCount: visibleRequirements.length,
                                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                                    itemBuilder: (context, index) {
                                      final requirement = visibleRequirements[index];
                                      final status = statusByRequirement[
                                          requirement['id']?.toString() ?? ''];
                                      return _RequirementTile(
                                        requirement: requirement,
                                        status: status,
                                        onTap: () => _editStatus(requirement, status),
                                      );
                                    },
                                  ),
                          ),
                        ],
                      ),
      ),
    );
  }

  void _reload() {
    setState(() => _loading = true);
    _load();
  }

  Future<void> _addDefaults() async {
    final repository = _repository;
    if (repository == null) return;
    setState(() => _loading = true);
    try {
      await repository.addDefaultRequirements();
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('標準の必要書類候補を追加しました')),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('追加できませんでした: $error')),
      );
    }
  }

  Future<void> _addRequirement() async {
    final repository = _repository;
    if (repository == null) return;
    final nameController = TextEditingController();
    var scope = 'internal';
    var isRequired = true;
    var expiryRequired = false;

    final draft = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('必要書類を追加'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: '書類名 *'),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: scope,
                  decoration: const InputDecoration(labelText: '用途'),
                  items: const [
                    DropdownMenuItem(value: 'internal', child: Text('社内手続き')),
                    DropdownMenuItem(value: 'upstream', child: Text('元請・得意先提出')),
                  ],
                  onChanged: (value) {
                    if (value != null) setDialogState(() => scope = value);
                  },
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('必須'),
                  value: isRequired,
                  onChanged: (value) => setDialogState(() => isRequired = value),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('有効期限あり'),
                  value: expiryRequired,
                  onChanged: (value) => setDialogState(() => expiryRequired = value),
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
                  'scope': scope,
                  'isRequired': isRequired,
                  'expiryRequired': expiryRequired,
                });
              },
              child: const Text('追加'),
            ),
          ],
        ),
      ),
    );
    nameController.dispose();
    if (draft == null) return;

    try {
      await repository.addRequirement(
        name: draft['name'] as String,
        scope: draft['scope'] as String,
        isRequired: draft['isRequired'] as bool,
        expiryRequired: draft['expiryRequired'] as bool,
      );
      _reload();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('追加できませんでした: $error')),
      );
    }
  }

  Future<void> _editStatus(
    Map<String, dynamic> requirement,
    Map<String, dynamic>? current,
  ) async {
    final repository = _repository;
    final workerId = _selectedWorkerId;
    final requirementId = requirement['id']?.toString();
    if (repository == null || workerId == null || requirementId == null) return;

    var status = current?['status']?.toString() ?? 'not_submitted';
    var originalVerified = current?['original_verified'] == true;
    DateTime? expiresAt = _parseDate(current?['expires_at']);
    final notesController = TextEditingController(text: current?['notes']?.toString() ?? '');

    final save = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(requirement['name']?.toString() ?? '書類'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: status,
                  decoration: const InputDecoration(labelText: '状態'),
                  items: const [
                    DropdownMenuItem(value: 'not_submitted', child: Text('未提出')),
                    DropdownMenuItem(value: 'submitted', child: Text('提出済み')),
                    DropdownMenuItem(value: 'verified', child: Text('確認済み')),
                    DropdownMenuItem(value: 'missing', child: Text('不足')),
                    DropdownMenuItem(value: 'expired', child: Text('期限切れ')),
                  ],
                  onChanged: (value) {
                    if (value != null) setDialogState(() => status = value);
                  },
                ),
                if (requirement['expiry_required'] == true) ...[
                  const SizedBox(height: 12),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('有効期限'),
                    subtitle: Text(expiresAt == null ? '未設定' : _formatDate(expiresAt!)),
                    trailing: const Icon(Icons.calendar_month_outlined),
                    onTap: () async {
                      final now = DateTime.now();
                      final picked = await showDatePicker(
                        context: dialogContext,
                        initialDate: expiresAt ?? now,
                        firstDate: DateTime(1950),
                        lastDate: DateTime(now.year + 30),
                      );
                      if (picked != null) setDialogState(() => expiresAt = picked);
                    },
                  ),
                ],
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('原本確認済み'),
                  value: originalVerified,
                  onChanged: (value) => setDialogState(() => originalVerified = value ?? false),
                ),
                TextField(
                  controller: notesController,
                  decoration: const InputDecoration(labelText: '備考'),
                  maxLines: 3,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('キャンセル'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
    final notes = notesController.text;
    notesController.dispose();
    if (save != true) return;

    try {
      await repository.updateStatus(
        workerId: workerId,
        requirementId: requirementId,
        status: status,
        expiresAt: expiresAt,
        originalVerified: originalVerified,
        notes: notes,
      );
      _reload();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('保存できませんでした: $error')),
      );
    }
  }

  DateTime? _parseDate(Object? value) {
    if (value == null) return null;
    return DateTime.tryParse(value.toString());
  }

  String _formatDate(DateTime value) =>
      '${value.year}/${value.month.toString().padLeft(2, '0')}/${value.day.toString().padLeft(2, '0')}';
}

class _RequirementTile extends StatelessWidget {
  const _RequirementTile({
    required this.requirement,
    required this.status,
    required this.onTap,
  });

  final Map<String, dynamic> requirement;
  final Map<String, dynamic>? status;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final statusValue = status?['status']?.toString() ?? 'not_submitted';
    final labels = <String, String>{
      'not_submitted': '未提出',
      'submitted': '提出済み',
      'verified': '確認済み',
      'missing': '不足',
      'expired': '期限切れ',
    };
    final scopeLabel = requirement['scope'] == 'upstream' ? '元請・得意先' : '社内';
    final requiredLabel = requirement['is_required'] == true ? '必須' : '任意';
    final expiry = status?['expires_at']?.toString();

    return Card(
      child: ListTile(
        leading: CircleAvatar(
          child: Icon(statusValue == 'verified' ? Icons.check : Icons.description_outlined),
        ),
        title: Text(
          requirement['name']?.toString() ?? '',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Text(
          [
            '$scopeLabel / $requiredLabel',
            labels[statusValue] ?? statusValue,
            if (expiry != null && expiry.isNotEmpty) '期限 $expiry',
            if (status?['original_verified'] == true) '原本確認済み',
          ].join(' / '),
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onAddDefaults});

  final VoidCallback onAddDefaults;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.fact_check_outlined, size: 52),
            const SizedBox(height: 12),
            const Text('必要書類の設定がまだありません'),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: onAddDefaults,
              icon: const Icon(Icons.playlist_add),
              label: const Text('標準項目を追加'),
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
            const Icon(Icons.error_outline, size: 48),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(onPressed: onRetry, child: const Text('再試行')),
          ],
        ),
      ),
    );
  }
}
