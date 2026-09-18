import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'worker_document_repository.dart';

class WorkerDocumentPage extends StatefulWidget {
  const WorkerDocumentPage({super.key});

  @override
  State<WorkerDocumentPage> createState() => _WorkerDocumentPageState();
}

class _WorkerDocumentPageState extends State<WorkerDocumentPage> {
  final _repository = WorkerDocumentRepository.maybeCreate();
  final _picker = ImagePicker();

  List<Map<String, dynamic>> _workers = [];
  List<Map<String, dynamic>> _requirements = [];
  List<Map<String, dynamic>> _statuses = [];
  bool _loading = true;
  bool _canManageRequirements = false;
  bool _canManageStatuses = false;
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
      final values = await Future.wait([
        repository.loadAll(),
        repository.canManageRequirements(),
        repository.canManageStatuses(),
      ]);
      final data = values[0] as Map<String, List<Map<String, dynamic>>>;
      if (!mounted) return;
      final workers = data['workers'] ?? const <Map<String, dynamic>>[];
      setState(() {
        _workers = workers;
        _requirements = data['requirements'] ?? const <Map<String, dynamic>>[];
        _statuses = data['statuses'] ?? const <Map<String, dynamic>>[];
        _canManageRequirements = values[1] as bool;
        _canManageStatuses = values[2] as bool;
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
    final today = DateTime.now();
    final completed = visibleRequirements.where((requirement) {
      final status = statusByRequirement[requirement['id']?.toString()];
      final effectiveStatus = _effectiveDocumentStatus(requirement, status, today);
      return effectiveStatus == 'submitted' || effectiveStatus == 'verified';
    }).length;
    final needsAttention = visibleRequirements.where((requirement) {
      final status = statusByRequirement[requirement['id']?.toString()];
      return _documentNeedsAttention(requirement, status, today);
    }).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('必要書類チェック'),
        actions: [
          IconButton(
            tooltip: '標準項目を追加',
            onPressed: _loading || !_canManageRequirements ? null : _addDefaults,
            icon: const Icon(Icons.playlist_add_check_circle_outlined),
          ),
          IconButton(
            tooltip: '自由項目を追加',
            onPressed: _loading || !_canManageRequirements ? null : _addRequirement,
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
                                Text(
                                  needsAttention == 0
                                      ? '完了 $completed/${visibleRequirements.length}'
                                      : '完了 $completed/${visibleRequirements.length} / 要確認 $needsAttention',
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 8),
                          Expanded(
                            child: _requirements.isEmpty
                                ? _EmptyState(
                                    onAddDefaults:
                                        _canManageRequirements ? _addDefaults : null,
                                  )
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
                                        onTap: _canManageStatuses
                                            ? () => _editStatus(requirement, status)
                                            : null,
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
                if ((current?['attachment_path']?.toString() ?? '').isNotEmpty) ...[
                  const SizedBox(height: 12),
                  FutureBuilder<String>(
                    future: repository.createSignedAttachmentUrl(
                      current!['attachment_path'].toString(),
                    ),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState != ConnectionState.done) {
                        return const LinearProgressIndicator();
                      }
                      if (snapshot.hasError || snapshot.data == null) {
                        return const Text('添付写真を表示できませんでした。');
                      }
                      return ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Image.network(
                          snapshot.data!,
                          height: 180,
                          fit: BoxFit.contain,
                          errorBuilder: (_, __, ___) =>
                              const Text('添付写真を表示できませんでした。'),
                        ),
                      );
                    },
                  ),
                ],
              ],
            ),
          ),
          actions: [
            if (current != null)
              TextButton.icon(
                onPressed: () async {
                  final source = await showModalBottomSheet<ImageSource>(
                    context: dialogContext,
                    builder: (sheetContext) => SafeArea(
                      child: Wrap(
                        children: [
                          ListTile(
                            leading: const Icon(Icons.photo_camera_outlined),
                            title: const Text('カメラで撮影'),
                            onTap: () =>
                                Navigator.pop(sheetContext, ImageSource.camera),
                          ),
                          ListTile(
                            leading: const Icon(Icons.photo_library_outlined),
                            title: const Text('写真から選ぶ'),
                            onTap: () =>
                                Navigator.pop(sheetContext, ImageSource.gallery),
                          ),
                        ],
                      ),
                    ),
                  );
                  if (source == null) return;
                  final picked = await _picker.pickImage(
                    source: source,
                    imageQuality: 88,
                    maxWidth: 2400,
                  );
                  if (picked == null) return;
                  try {
                    await repository.uploadAttachment(
                      statusId: current['id'].toString(),
                      workerId: workerId,
                      requirementId: requirementId,
                      bytes: await picked.readAsBytes(),
                      originalFilename: picked.name,
                    );
                    if (dialogContext.mounted) {
                      Navigator.pop(dialogContext, true);
                    }
                  } catch (error) {
                    if (dialogContext.mounted) {
                      ScaffoldMessenger.of(dialogContext).showSnackBar(
                        SnackBar(content: Text('写真を保存できませんでした: $error')),
                      );
                    }
                  }
                },
                icon: const Icon(Icons.attach_file),
                label: Text(
                  (current['attachment_path']?.toString() ?? '').isEmpty
                      ? '写真を添付'
                      : '写真を差し替え',
                ),
              ),
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


DateTime? _parseDocumentDate(Object? value) {
  if (value == null) return null;
  final parsed = DateTime.tryParse(value.toString());
  if (parsed == null) return null;
  return DateTime(parsed.year, parsed.month, parsed.day);
}

DateTime _dateOnly(DateTime value) => DateTime(value.year, value.month, value.day);

int _reminderDays(Map<String, dynamic> requirement) {
  final raw = requirement['renewal_reminder_days'];
  if (raw is int) return raw;
  return int.tryParse(raw?.toString() ?? '') ?? 30;
}

String _effectiveDocumentStatus(
  Map<String, dynamic> requirement,
  Map<String, dynamic>? status,
  DateTime now,
) {
  final stored = status?['status']?.toString() ?? 'not_submitted';
  if (requirement['expiry_required'] != true) return stored;

  final expiry = _parseDocumentDate(status?['expires_at']);
  if (expiry == null) return stored;
  if (expiry.isBefore(_dateOnly(now))) return 'expired';
  return stored;
}

bool _documentNeedsAttention(
  Map<String, dynamic> requirement,
  Map<String, dynamic>? status,
  DateTime now,
) {
  final effective = _effectiveDocumentStatus(requirement, status, now);
  if (effective == 'expired' || effective == 'missing') return true;
  if (requirement['expiry_required'] != true) return false;

  final expiry = _parseDocumentDate(status?['expires_at']);
  if (expiry == null) return false;
  final days = expiry.difference(_dateOnly(now)).inDays;
  return days >= 0 && days <= _reminderDays(requirement);
}

String? _expiryHint(
  Map<String, dynamic> requirement,
  DateTime? expiry,
  DateTime now,
) {
  if (requirement['expiry_required'] != true || expiry == null) return null;
  final days = expiry.difference(_dateOnly(now)).inDays;
  if (days < 0) return '期限切れ';
  if (days == 0) return '本日期限';
  if (days <= _reminderDays(requirement)) return 'あと$days日';
  return null;
}

class _RequirementTile extends StatelessWidget {
  const _RequirementTile({
    required this.requirement,
    required this.status,
    required this.onTap,
  });

  final Map<String, dynamic> requirement;
  final Map<String, dynamic>? status;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final statusValue = _effectiveDocumentStatus(requirement, status, today);
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
    final expiryDate = _parseDocumentDate(expiry);
    final expiryHint = _expiryHint(requirement, expiryDate, today);

    return Card(
      child: ListTile(
        leading: CircleAvatar(
          child: Icon(
            statusValue == 'verified'
                ? Icons.check
                : statusValue == 'expired'
                    ? Icons.warning_amber_rounded
                    : Icons.description_outlined,
          ),
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
            if (expiryHint != null) expiryHint,
            if (status?['original_verified'] == true) '原本確認済み',
            if ((status?['attachment_path']?.toString() ?? '').isNotEmpty)
              '写真あり',
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

  final VoidCallback? onAddDefaults;

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
            if (onAddDefaults != null)
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
