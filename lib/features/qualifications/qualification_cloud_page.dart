import 'dart:async';

import 'package:flutter/material.dart';

import '../../domain/company_data_transfer.dart';
import '../common/data_date_labels.dart';
import '../people/personnel_export_page.dart';
import '../../international/language_controller.dart';
import 'qualification_cloud_repository.dart';
import 'qualification_send_page.dart';
import 'qualification_certificate_page.dart';
import 'qualification_certificate_repository.dart';
import '../shared/resource_registration_card.dart';

class QualificationCloudPage extends StatefulWidget {
  const QualificationCloudPage({super.key, this.repository, this.certificateRepository});
  @visibleForTesting
  final QualificationCloudRepository? repository;
  @visibleForTesting
  final QualificationCertificateRepository? certificateRepository;

  @override
  State<QualificationCloudPage> createState() => _QualificationCloudPageState();
}

class _QualificationCloudPageState extends State<QualificationCloudPage> {
  late final QualificationCloudRepository? _repository;
  final _workerQueryController = TextEditingController();
  final _qualificationQueryController = TextEditingController();

  List<Map<String, dynamic>> _masters = [];
  List<Map<String, dynamic>> _workers = [];
  List<Map<String, dynamic>> _qualifications = [];
  bool Function()? _galleryLease;
  int _galleryGeneration = 0;
  bool _loading = true;
  bool _registrationDialogOpen = false;
  bool _canManageMaster = false;
  bool _canManageWorkerQualifications = false;
  bool _showExpiringOnly = false;
  bool _canEditCertificates = false;
  late final QualificationCertificateRepository? _certificateRepository;
  String _workerQuery = '';
  String _qualificationQuery = '';
  String? _selectedWorkerId;
  String? _error;

  @override
  void initState() {
    super.initState();
    _repository = widget.repository ?? QualificationCloudRepository.maybeCreate();
    _certificateRepository = widget.certificateRepository ?? QualificationCertificateRepository.maybeCreate();
    _load();
  }

  @override
  void dispose() {
    _workerQueryController.dispose();
    _qualificationQueryController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final galleryGeneration = ++_galleryGeneration;
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
      bool Function()? galleryLease;
      try { galleryLease = await repository.captureAttachmentReadScope(); } catch (_) { galleryLease = null; }

      final values = await Future.wait([
        repository.loadAll(),
        repository.canManageMaster(),
        repository.canManageWorkerQualifications(),
        _certificateRepository?.canManageCertificates() ?? Future.value(false),
      ]);
      final data = values[0] as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _galleryLease = galleryGeneration == _galleryGeneration ? galleryLease : null;
        _masters = List<Map<String, dynamic>>.from(data['masters'] as List);
        _workers = List<Map<String, dynamic>>.from(data['workers'] as List);
        _qualifications = List<Map<String, dynamic>>.from(data['qualifications'] as List);
        _canManageMaster = values[1] as bool;
        _canManageWorkerQualifications = values[2] as bool;
        _canEditCertificates = values[3] as bool;
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

  ResourceAttachmentGallery? _galleryForWorker(String workerId) {
    final repository = _certificateRepository, rows = _qualifications;
    final lease = _galleryLease, galleryGeneration = _galleryGeneration;
    final workers = _workers.where((row) => row['id'] == workerId).toList();
    final company = workers.length == 1 ? workers.single['company_id']?.toString() : null;
    final actor = repository?.currentUserId, selection = _selectedWorkerId;
    if (repository == null || lease == null || !lease() || actor == null || company == null || company.isEmpty) { return null; }
    bool current() => mounted && !_loading && galleryGeneration == _galleryGeneration && lease() && identical(rows, _qualifications) &&
      _selectedWorkerId == selection && repository.currentUserId == actor &&
      _workers.any((row) => row['id'] == workerId && row['company_id'] == company);
    if (rows.any((row) => row['worker_id'] == workerId && row['company_id'] != company && row['_unregistered'] != true)) { return null; }
    final titles = {for (final row in _masters) row['id']: row['name']?.toString() ?? '資格'};
    final entries = <ResourceAttachment>[];
    for (final row in rows.where((row) => row['worker_id'] == workerId && row['company_id'] == company && row['_unregistered'] != true)) {
      final id = row['id']?.toString(); if (id == null || id.isEmpty) { continue; }
      final paths = [row['attachment_path'], row['attachment_back_path'], ...?row['attachment_extra_paths'] as List?];
      for (var i = 0; i < paths.length; i++) {
        final path = paths[i]; if (path is! String || path.trim().isEmpty) { continue; }
        Future<String> signed(String value) async {
          if (!current()) { throw StateError('Attachment scope changed'); }
          final url = await repository.createSignedUrl(value);
          if (!current()) { throw StateError('Attachment scope changed'); } return url;
        }
        entries.add(signedResourceAttachment(label: i == 0 ? '表面' : i == 1 ? '裏面' : '追加写真 ${i - 1}', path: path,
          signedUrl: signed, previewKey: 'qualification:$id:$i', recordTitle: titles[row['qualification_master_id']] ?? '資格'));
      }
    }
    return ResourceAttachmentGallery(source: rows, workerId: workerId, companyId: company, isCurrent: current, changes: _repository!.attachmentAuthChanges, entries: entries);
  }

  @override
  Widget build(BuildContext context) {
    SkoLanguageController.watch(context);
    final now = DateTime.now();
    final masterById = {
      for (final row in _masters) row['id']?.toString() ?? '': row,
    };
    final workerById = {
      for (final row in _workers) row['id']?.toString() ?? '': row,
    };
    final workerNeedle = _workerQuery.trim().toLowerCase();
    final qualificationNeedle = _qualificationQuery.trim().toLowerCase();
    final filteredWorkers = _workers.where((row) {
      if (workerNeedle.isEmpty) return true;
      return [
        row['name'],
        row['affiliation'],
      ].whereType<Object>().join(' ').toLowerCase().contains(workerNeedle);
    }).toList(growable: false);

    final listed = _qualifications;
    final filtered = listed.where((row) {
      final master = masterById[row['qualification_master_id']?.toString() ?? ''];
      final expiry = _parseDate(row['expires_at']);
      final isExpired = expiry != null && expiry.isBefore(_dateOnly(now));
      final isExpiringSoon = expiry != null &&
          !isExpired &&
          !expiry.isAfter(_dateOnly(now).add(const Duration(days: 90)));
      final matchesExpiry = !_showExpiringOnly || isExpired || isExpiringSoon;
      final matchesWorker =
          _selectedWorkerId == null || row['worker_id']?.toString() == _selectedWorkerId;
      final qualificationHaystack = [
        master?['name'],
        master?['category'],
        master?['issuer'],
        row['certificate_number'],
        row['issuer'],
        row['notes'],
      ].whereType<Object>().join(' ').toLowerCase();
      final matchesQualification = qualificationNeedle.isEmpty ||
          qualificationHaystack.contains(qualificationNeedle);
      return matchesExpiry && matchesWorker && matchesQualification;
    }).toList(growable: false);

    return Scaffold(
      resizeToAvoidBottomInset: !_registrationDialogOpen,
      appBar: AppBar(
        title: const Text('従業員資格'),
        actions: [
          IconButton(
            tooltip: '親会社に送る',
            onPressed: _loading || _workers.isEmpty
                ? null
                : () => _openExport(PersonnelExportOperation.send),
            icon: const Icon(Icons.send_outlined),
          ),
          IconButton(
            tooltip: '印刷',
            onPressed: _loading || _workers.isEmpty
                ? null
                : () => _openExport(PersonnelExportOperation.print),
            icon: const Icon(Icons.print_outlined),
          ),
          IconButton(
            tooltip: '資格マスター管理',
            onPressed: _loading || !_canManageWorkerQualifications ? null : _manageMasters,
            icon: const Icon(Icons.manage_accounts_outlined),
          ),
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
      bottomNavigationBar: ResourceRegistrationFooter(
        label: '資格を登録',
        onPressed: _loading || !_canManageWorkerQualifications || _masters.isEmpty || _workers.isEmpty
          ? null : _addQualification,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
              child: TextField(
                controller: _workerQueryController,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.person_search_outlined),
                  hintText: '従業員名で検索',
                ),
                onChanged: (value) => setState(() => _workerQuery = value),
              ),
            ),
            SizedBox(
              height: 72,
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                scrollDirection: Axis.horizontal,
                children: [
                  ChoiceChip(
                    label: const Text('全員'),
                    selected: _selectedWorkerId == null,
                    onSelected: (_) => setState(() => _selectedWorkerId = null),
                  ),
                  const SizedBox(width: 8),
                  for (final worker in filteredWorkers) ...[
                    ChoiceChip(
                      label: Text(worker['name']?.toString() ?? '名前未登録'),
                      selected:
                          _selectedWorkerId == worker['id']?.toString(),
                      onSelected: (_) => setState(
                        () => _selectedWorkerId = worker['id']?.toString(),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: TextField(
                controller: _qualificationQueryController,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: '資格種類・証明書番号で検索',
                ),
                onChanged: (value) =>
                    setState(() => _qualificationQuery = value),
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
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                              itemCount: filtered.length,
                              separatorBuilder: (_, __) => const SizedBox(height: 8),
                              itemBuilder: (context, index) {
                                final row = filtered[index];
                                final master = masterById[
                                    row['qualification_master_id']?.toString() ?? ''];
                                final worker = workerById[row['worker_id']?.toString() ?? ''];
                                final expiry = _parseDate(row['expires_at']);
                                final status = _expiryLabel(expiry, now);
                                final unregistered = row['_unregistered'] == true;
                                final actor = _certificateRepository?.currentUserId;
                                Future<String> signedUrl(String path) async {
                                  final repository = _certificateRepository;
                                  if (repository == null || actor == null || actor != repository.currentUserId) {
                                    throw StateError('Session changed');
                                  }
                                  final url = await repository.createSignedUrl(path);
                                  if (actor != repository.currentUserId) throw StateError('Session changed');
                                  return url;
                                }
                                final attachments = [
                                  signedResourceAttachment(label: '表面', previewKey: 'qualification:${row['id']}:0', recordTitle: master?['name']?.toString() ?? '資格', path: row['attachment_path']?.toString(),
                                    signedUrl: signedUrl, known: unregistered || row.containsKey('attachment_path')),
                                  signedResourceAttachment(label: '裏面', previewKey: 'qualification:${row['id']}:1', recordTitle: master?['name']?.toString() ?? '資格', path: row['attachment_back_path']?.toString(),
                                    signedUrl: signedUrl, known: unregistered || row.containsKey('attachment_back_path')),
                                ];
                                return ResourceRegistrationCard(
                                  key: ValueKey('managed-qualification:$actor:${row['worker_id']}:${row['id'] ?? row['qualification_master_id']}'),
                                  title: master?['name']?.toString() ?? '資格', icon: Icons.badge_outlined,
                                  registered: !unregistered,
                                  registeredActionLabel: '詳細を確認',
                                  dateLabel: '${(row['issued_at']?.toString() ?? '').isEmpty ? '取得日 未設定' : '取得日 ${row['issued_at']}'}　区分 ${(master?['category']?.toString().trim().isNotEmpty ?? false) ? master!['category'] : '未設定'}',
                                  detailLabel: worker?['name']?.toString() ?? '', attachments: attachments, gallery: _galleryForWorker(row['worker_id'].toString()), requireGalleryScope: true,
                                  onAction: unregistered ? _canManageWorkerQualifications
                                    ? () => _addQualification(initialMasterId: row['qualification_master_id']?.toString()) : null
                                    : () => _showDetails(row, master, worker, status),
                                  onOpenDetail: unregistered ? null : () => _showDetails(row, master, worker, status),
                                );
                              },
                            ),
            ),
          ],
        ),
      ),
    );
  }

  List<PersonnelExportWorker> get _exportWorkers => _workers
      .map(
        (row) => PersonnelExportWorker(
          id: row['id']?.toString() ?? '',
          name: row['name']?.toString() ?? '名称未設定',
          originCompanyName: row['affiliation']?.toString(),
        ),
      )
      .where((worker) => worker.id.isNotEmpty)
      .toList(growable: false);

  Future<void> _openExport(PersonnelExportOperation operation) async {
    if (operation == PersonnelExportOperation.send) {
      final workerIds = _workers
          .map((row) => row['id']?.toString() ?? '')
          .where((id) => id.isNotEmpty)
          .toSet();
      await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => QualificationSendPage(workerIds: workerIds),
        ),
      );
      return;
    }

    await Navigator.of(context).push<PersonnelExportResult>(
      MaterialPageRoute(
        builder: (_) => PersonnelExportPage(
          title: '資格データ',
          workers: _exportWorkers,
          operation: operation,
          fixedKind: TransferPayloadKind.qualificationsOnly,
        ),
      ),
    );
  }
  Future<void> _addMaster() async {
    final repository = _repository;
    if (repository == null) return;
    final nameController = TextEditingController();
    String? selectedCategory;
    final issuerController = TextEditingController();
    final notesController = TextEditingController();
    var expiryRequired = false;

    setState(() => _registrationDialogOpen = true);
    Future<dynamic>? dialogCompleted;
    final draft = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) {
        dialogCompleted ??= ModalRoute.of(dialogContext)?.completed;
        return StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          constraints: const BoxConstraints(maxWidth: 560),
          title: const Text('資格マスター追加'),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: '資格・免許・講習名 *'),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: selectedCategory,
                  decoration: const InputDecoration(labelText: '区分'),
                  items: const [
                    DropdownMenuItem(value: '国家資格', child: Text('国家資格')),
                    DropdownMenuItem(value: '技能講習', child: Text('技能講習')),
                    DropdownMenuItem(value: '実技講習', child: Text('実技講習')),
                    DropdownMenuItem(value: '安全教育', child: Text('安全教育')),
                    DropdownMenuItem(value: '特別教育', child: Text('特別教育')),
                  ],
                  onChanged: (value) => setDialogState(() => selectedCategory = value),
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
                  'category': selectedCategory ?? '',
                  'issuer': issuerController.text.trim(),
                  'expiryRequired': expiryRequired,
                  'notes': notesController.text.trim(),
                });
              },
              child: const Text('追加'),
            ),
          ],
        ),
        );
      },
    );

    void disposeDraft() {
      nameController.dispose();
      issuerController.dispose();
      notesController.dispose();
      if (mounted) {
        setState(() => _registrationDialogOpen = false);
      }
    }
    final completed = dialogCompleted;
    if (completed == null) {
      disposeDraft();
    } else {
      unawaited(completed.then((_) => disposeDraft()));
    }
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

  Future<void> _addQualification({String? initialMasterId}) async {
    final repository = _repository;
    if (repository == null) return;
    if (_masters.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('先に資格マスターを追加してください')));
      return;
    }
    if (_workers.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('先に社員・作業員を登録してください')));
      return;
    }

    var workerId = _selectedWorkerId ?? _workers.first['id']?.toString();
    var masterId = _masters.any((m) => m['id']?.toString() == initialMasterId)
        ? initialMasterId
        : _masters.first['id']?.toString();
    final certificateController = TextEditingController();
    final issuerController = TextEditingController();
    final notesController = TextEditingController();
    DateTime? issuedAt;
    DateTime? expiresAt;

    setState(() => _registrationDialogOpen = true);
    Future<dynamic>? dialogCompleted;
    final draft = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) {
        dialogCompleted ??= ModalRoute.of(dialogContext)?.completed;
        return StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
            constraints: const BoxConstraints(maxWidth: 560),
            title: const Text('資格登録'),
            content: SizedBox(
              width: double.maxFinite,
              child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                  isExpanded: true,
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
                    onChanged: (value) =>
                        setDialogState(() => workerId = value),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                  isExpanded: true,
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
                    onChanged: (value) =>
                        setDialogState(() => masterId = value),
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
                      if (picked != null) {
                        setDialogState(() => issuedAt = picked);
                      }
                    },
                  ),
                  _DateRow(
                    label: '有効期限',
                    value: expiresAt,
                    onTap: () async {
                      final picked = await _pickDate(dialogContext, expiresAt);
                      if (picked != null) {
                        setDialogState(() => expiresAt = picked);
                      }
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
        );
      },
    );

    void disposeDraft() {
      certificateController.dispose();
      issuerController.dispose();
      notesController.dispose();
      if (mounted) {
        setState(() => _registrationDialogOpen = false);
      }
    }

    // Dialog results precede the reverse animation. Keep its controllers alive
    // until the actual route subtree has finished using them.
    final completed = dialogCompleted;
    if (completed == null) {
      disposeDraft();
    } else {
      unawaited(completed.then((_) => disposeDraft()));
    }
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
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('資格をクラウドに登録しました')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('登録できませんでした: $error')));
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

  Future<void> _changeMasterCategory(Map<String, dynamic> master) async {
    final repository = _repository;
    final masterId = master['id']?.toString() ?? '';
    if (repository == null || masterId.isEmpty || !_canManageWorkerQualifications) return;
    final choice = await showDialog<String>(context: context, builder: (context) =>
      SimpleDialog(title: const Text('資格区分を変更'), children: [
        const Padding(padding: EdgeInsets.symmetric(horizontal: 24),
          child: Text('同じ資格を持つ全員の区分に反映されます。')),
        for (final category in const ['国家資格', '技能講習', '実技講習', '安全教育', '特別教育'])
          SimpleDialogOption(onPressed: () => Navigator.pop(context, category), child: Text(category)),
      ]));
    if (choice == null) return;
    try {
      await repository.updateMasterCategory(masterId, choice);
      if (!mounted) return;
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('資格区分を更新しました')));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('資格区分を更新できませんでした')));
    }
  }

  Future<void> _manageMasters() async {
    if (!_canManageWorkerQualifications) return;
    await showDialog<void>(context: context, builder: (dialogContext) =>
      SimpleDialog(title: const Text('資格マスター管理'), children: [
        for (final master in _masters)
          ListTile(title: Text(master['name']?.toString() ?? '資格'),
            subtitle: Text(master['category']?.toString() ?? '区分未設定'),
            trailing: Wrap(children: [
              IconButton(tooltip: '区分を変更', icon: const Icon(Icons.edit_outlined),
                onPressed: () { Navigator.pop(dialogContext); _changeMasterCategory(master); }),
              const IconButton(tooltip: '削除は準備中', icon: Icon(Icons.delete_outline),
                onPressed: null),
            ])),
      ]));
  }

  void _showDetails(
    Map<String, dynamic> row,
    Map<String, dynamic>? master,
    Map<String, dynamic>? worker,
    String status,
  ) {
    final actor = _certificateRepository?.currentUserId;
    Future<String> detailSignedUrl(String path) async {
      final repository = _certificateRepository;
      if (repository == null || actor == null || actor != repository.currentUserId) {
        throw StateError('Session changed');
      }
      final url = await repository.createSignedUrl(path);
      if (actor != repository.currentUserId) throw StateError('Session changed');
      return url;
    }
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: SingleChildScrollView(
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
              if (_canManageWorkerQualifications && master != null)
                TextButton(onPressed: () { Navigator.pop(sheetContext); _changeMasterCategory(master); },
                  child: const Text('資格区分を変更')),
              if (_canManageWorkerQualifications && master != null)
                const Text('資格マスターの削除は準備中です。'),
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
              for (final label in DataDateLabels.labels(
                createdAt: row['created_at'],
                updatedAt: row['updated_at'],
              ))
                Text(label),
              const SizedBox(height: 16),
              if (_canManageWorkerQualifications && _canEditCertificates)
                OutlinedButton.icon(
                  onPressed: () async {
                    Navigator.pop(sheetContext);
                    await Navigator.push<void>(context, MaterialPageRoute(builder: (_) =>
                      QualificationCertificatePage(initialQualificationId: row['id']?.toString(), repository: _certificateRepository)));
                    if (mounted) await _load();
                  },
                  icon: const Icon(Icons.edit_outlined), label: Text(SkoLanguageController.tr('資格証を確認'))),
              if (QualificationCloudRepository.ownPhotoAttachments(row).isNotEmpty)
                TextButton(onPressed: () => showResourceAttachments(context,
                  title: master?['name']?.toString() ?? '資格', attachments: [
                    for (final photo in QualificationCloudRepository.ownPhotoAttachments(row))
                      signedResourceAttachment(label: photo.label, path: photo.path,
                        signedUrl: detailSignedUrl),
                  ]), child: const Text('すべての添付を確認')),
              if (_canManageWorkerQualifications)
                OutlinedButton.icon(
                  onPressed: () async {
                    Navigator.pop(sheetContext);
                    await _delete(row['id']?.toString() ?? '');
                  },
                  icon: const Icon(Icons.info_outline),
                  label: Text(SkoLanguageController.tr('登録後の変更について')),
                ),
            ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _delete(String id) async {
    // No manager change-approval contract is available. Keep even a captured
    // legacy delete callback from reaching the direct repository delete path.
    if (!mounted || id.isEmpty) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(SkoLanguageController.tr(registeredQualificationChangeNotice)),
    ));
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


