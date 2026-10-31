import 'dart:async';

import 'package:flutter/material.dart';

import '../../domain/company_data_transfer.dart';
import '../../international/language_controller.dart';
import '../help/floating_help_controller.dart';
import '../common/data_date_labels.dart';
import 'personnel_export_page.dart';
import 'worker_document_repository.dart';
import 'worker_document_exemption.dart';
import 'worker_document_display_status.dart';
import 'worker_document_change_flow.dart';
import 'worker_document_admin_correction_entry.dart';
import 'worker_document_change_review_page.dart';
import '../shared/resource_registration_card.dart';

import 'worker_document_scope.dart';
import 'worker_document_photos.dart';
import 'worker_document_photo_editor.dart';
import 'worker_document_send_page.dart';

enum WorkerDocumentView { home, workers, settings }

class WorkerDocumentPage extends StatefulWidget {
  const WorkerDocumentPage({
    super.key,
    this.view = WorkerDocumentView.home,
    this.repositoryOverride,
  });
  @visibleForTesting
  final WorkerDocumentRepository? repositoryOverride;
  final WorkerDocumentView view;

  @override
  State<WorkerDocumentPage> createState() => _WorkerDocumentPageState();
}

class _WorkerDocumentPageState extends State<WorkerDocumentPage> {
  late final _repository =
      widget.repositoryOverride ?? WorkerDocumentRepository.maybeCreate();

  List<Map<String, dynamic>> _workers = [];
  List<Map<String, dynamic>> _requirements = [];
  List<Map<String, dynamic>> _retainedRequirements = [];
  List<Map<String, dynamic>> _archivedRequirements = [];
  List<Map<String, dynamic>> _statuses = [];
  List<Map<String, dynamic>> _exemptions = [];
  List<Map<String, dynamic>> _bankMetadata = [];
  bool Function()? _galleryLease;
  int _galleryGeneration = 0;
  final _galleryChanges = ValueNotifier(0);
  bool _loading = true;
  bool _canManageRequirements = false;
  bool _canManageStatuses = false;
  String? _error;
  String? _selectedWorkerId;
  String? _loadedActorId;
  String _scope = 'all';
  String _workerQuery = '';
  final Set<String> _visibilitySaving = {};

  @override
  void initState() {
    super.initState();
    if (widget.view == WorkerDocumentView.settings) _scope = 'internal';
    _load();
  }

  @override
  void dispose() { _galleryGeneration++; _galleryChanges.value++; _galleryChanges.dispose(); super.dispose(); }

  Future<void> _load() async {
    final galleryGeneration = ++_galleryGeneration;
    _galleryChanges.value++;
    final repository = _repository;
    if (repository == null) {
      if (!mounted || galleryGeneration != _galleryGeneration) return;
      setState(() {
        _loading = false;
        _error = 'Supabase接続が利用できません。';
      });
      return;
    }
    final actor = repository.actorId;
    try {
      bool Function()? galleryLease;
      try { galleryLease = await repository.captureAttachmentReadScope(); } catch (_) { galleryLease = null; }

      final values = await Future.wait([
        repository.loadAll(includeHiddenRequirements: widget.view == WorkerDocumentView.settings),
        repository.canManageRequirements(),
        repository.canManageStatuses(),
      ]);
      if (actor == null || repository.actorId != actor) {
        throw StateError('ログイン情報が変更されました。再読み込みしてください。');
      }
      _loadedActorId = actor;
      final data = values[0] as Map<String, List<Map<String, dynamic>>>;
      if (!mounted || galleryGeneration != _galleryGeneration) return;
      final workers = data['workers'] ?? const <Map<String, dynamic>>[];
      setState(() {
        _galleryLease = galleryGeneration == _galleryGeneration ? galleryLease : null;
        _workers = workers;
        _requirements = data['requirements'] ?? const <Map<String, dynamic>>[];
        _retainedRequirements = data['retained_requirements'] ?? _requirements;
        _archivedRequirements = _retainedRequirements
            .where((row) => row['archived_at'] != null).toList();
        _statuses = data['statuses'] ?? const <Map<String, dynamic>>[];
        _exemptions = data['exemptions'] ?? const <Map<String, dynamic>>[];
        _bankMetadata = data['bank_account_metadata'] ?? const <Map<String, dynamic>>[];
        _canManageRequirements = values[1] as bool;
        _canManageStatuses = values[2] as bool;
        if (_selectedWorkerId == null ||
            !_workers.any(
              (row) => row['id']?.toString() == _selectedWorkerId,
            )) {
          _selectedWorkerId = null;
        }
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted || galleryGeneration != _galleryGeneration) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  void _selectGalleryWorker(String? worker) {
    if (_selectedWorkerId == worker) { return; }
    _selectedWorkerId = worker; _galleryGeneration++; _galleryChanges.value++; setState(() {});
  }

  ResourceAttachmentGallery? _galleryForWorker(String workerId) {
    final repository = _repository, rows = _statuses, requirements = _requirements;
    final lease = _galleryLease, galleryGeneration = _galleryGeneration;
    final workers = _workers.where((row) => row['id'] == workerId).toList();
    final company = workers.length == 1 ? workers.single['company_id']?.toString() : null;
    final actor = repository?.actorId;
    if (repository == null || lease == null || !lease() || actor == null || company == null || company.isEmpty) { return null; }
    bool current() => mounted && !_loading && galleryGeneration == _galleryGeneration && lease() && identical(rows, _statuses) && identical(requirements, _requirements) &&
      _selectedWorkerId == workerId && _loadedActorId == actor && repository.actorId == actor &&
      _workers.any((row) => row['id'] == workerId && row['company_id'] == company);
    if (requirements.any((row) => row['company_id'] != company) || rows.any((row) => row['worker_id'] == workerId && row['company_id'] != company)) { return null; }
    final entries = <ResourceAttachment>[];
    for (final requirement in requirements.where((row) => row['company_id'] == company && row['is_active'] == true)) {
      final id = requirement['id']?.toString(); if (id == null || id.isEmpty) { continue; }
      final matches = rows.where((row) => row['company_id'] == company && row['worker_id'] == workerId && row['requirement_id'] == id).toList();
      if (matches.length != 1) { continue; }
      final paths = workerDocumentPaths(matches.single);
      for (var i = 0; i < paths.length; i++) {
        Future<String> signed(String path) async {
          if (!current()) { throw StateError('Attachment scope changed'); }
          final url = await repository.createSignedAttachmentUrl(path);
          if (!current()) { throw StateError('Attachment scope changed'); } return url;
        }
        entries.add(signedResourceAttachment(label: '${i + 1}', path: paths[i], signedUrl: signed,
          previewKey: 'document:$id:$i', recordTitle: requirement['name']?.toString() ?? '書類'));
      }
    }
    return ResourceAttachmentGallery(source: rows, workerId: workerId, companyId: company, isCurrent: current, signal: _galleryChanges, changes: repository.attachmentAuthChanges, entries: entries);
  }

  bool? _bankRegisteredFor(String? workerId) {
    final workers = _workers.where((row) => row['id'] == workerId).toList();
    if (workers.length != 1 || workers.single['company_id'] is! String) { return null; }
    final companyId = workers.single['company_id'];
    final matches = _bankMetadata.where((row) => row['worker_id'] == workerId &&
        row['company_id'] == companyId &&
        DateTime.tryParse(row['updated_at']?.toString() ?? '') != null).toList();
    return matches.length == 1 ? true : null;
  }

  @override
  Widget build(BuildContext context) {
    SkoLanguageController.watch(context);
    FloatingHelpController.setContext(featureKey: 'documents');
    if (widget.view == WorkerDocumentView.home) return _buildHome();
    if (widget.view == WorkerDocumentView.settings) return _buildSettings();
    final workerId = _selectedWorkerId;
    final visibleRequirements = _requirements
        .where((row) => workerDocumentMatchesScope(row['scope'], _scope))
        .toList(growable: false);
    final statusByRequirement = <String, Map<String, dynamic>>{
      for (final row in _statuses.where(
        (row) => row['worker_id']?.toString() == workerId,
      ))
        row['requirement_id']?.toString() ?? '': row,
    };
    final today = DateTime.now();
    final completed = visibleRequirements.where((requirement) {
      final status = statusByRequirement[requirement['id']?.toString()];
      if (documentExemptionFor(_exemptions, workerId,
          requirement['id']?.toString())?['active'] == true) { return false; }
      return workerDocumentDisplayStatus(requirement, status,
          bankRegistered: _bankRegisteredFor(workerId), today: today).complete;
    }).length;
    final exemptCount = visibleRequirements.where((requirement) =>
        documentExemptionFor(_exemptions, workerId, requirement['id']?.toString())?['active'] == true).length;
    final needsAttention = visibleRequirements.where((requirement) {
      final status = statusByRequirement[requirement['id']?.toString()];
      if (documentExemptionFor(_exemptions, workerId,
          requirement['id']?.toString())?['active'] == true) { return false; }
      return _documentNeedsAttention(requirement, status, today);
    }).length;

    return Scaffold(
      appBar: AppBar(
        title: Text(SkoLanguageController.tr('従業員データ編集')),
        actions: [
          IconButton(tooltip: '書類の変更申請一覧', icon: const Icon(Icons.fact_check_outlined),
            onPressed: _loading ? null : _openChangeReviews),
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
            tooltip: '再読み込み',
            onPressed: _loading ? null : _reload,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      bottomNavigationBar: ResourceRegistrationFooter(
        label: '書類を登録',
        onPressed: _loading || _error != null || !_canManageStatuses || workerId == null ||
          !_workers.any((row) => row['id']?.toString() == workerId) ||
          !visibleRequirements.any((row) => (row['id']?.toString() ?? '').isNotEmpty)
          ? null : _registerForSelectedWorker,
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
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
                    child: TextField(
                      decoration: const InputDecoration(
                        labelText: '従業員検索',
                        prefixIcon: Icon(Icons.person_search_outlined),
                      ),
                      onChanged: (value) {
                        _workerQuery = value;
                        _selectGalleryWorker(null);
                        setState(() {});
                      },
                    ),
                  ),
                  SizedBox(
                    height: 148,
                    child: Builder(
                      builder: (context) {
                        final needle = _workerQuery.trim().toLowerCase();
                        final visibleWorkers = _workers
                            .where((row) {
                              if (needle.isEmpty) return true;
                              return (row['name']?.toString() ?? '')
                                  .toLowerCase()
                                  .contains(needle);
                            })
                            .toList(growable: false);
                        return ListView.separated(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: visibleWorkers.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 4),
                          itemBuilder: (context, index) {
                            final worker = visibleWorkers[index];
                            final id = worker['id']?.toString();
                            final selected = id == _selectedWorkerId;
                            return Card(
                              color: selected
                                  ? Theme.of(context)
                                        .colorScheme
                                        .primaryContainer
                                  : null,
                              child: ListTile(
                                dense: true,
                                leading: const CircleAvatar(
                                  child: Icon(Icons.person_outline),
                                ),
                                title: Text(
                                  worker['name']?.toString() ?? '名前未登録',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                trailing: selected
                                    ? const Icon(Icons.check_circle)
                                    : const Icon(Icons.chevron_right),
                                onTap: () =>
                                    _selectGalleryWorker(id),
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilterChip(
                          label: const Text('すべて'),
                          selected: _scope == 'all',
                          onSelected: (_) => setState(() => _scope = 'all'),
                        ),
                        FilterChip(
                          label: const Text('社内'),
                          selected: _scope == 'internal',
                          onSelected: (_) =>
                              setState(() => _scope = 'internal'),
                        ),
                        FilterChip(
                          label: Text(SkoLanguageController.tr('取引先')),
                          selected: _scope == 'upstream',
                          onSelected: (_) =>
                              setState(() => _scope = 'upstream'),
                        ),
                        if (exemptCount > 0) Text('提出免除 $exemptCount件'),
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
                    child: workerId == null
                        ? Center(
                            child: Text(
                              SkoLanguageController.tr('従業員を検索して選択してください'),
                            ),
                          )
                        : _requirements.isEmpty
                        ? const _EmptyState(onAddDefaults: null)
                        : ListView.separated(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                            itemCount: visibleRequirements.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 8),
                            itemBuilder: (context, index) {
                              final requirement = visibleRequirements[index];
                              final status =
                                  statusByRequirement[requirement['id']
                                          ?.toString() ??
                                      ''];
                              final paths = workerDocumentPaths(status);
                              final repository = _repository;
                              final actor = _loadedActorId;
                              Future<String> signedUrl(String path) async {
                                if (repository == null || actor == null || actor != repository.actorId ||
                                    workerId != _selectedWorkerId) { throw StateError('Session changed'); }
                                final url = await repository.createSignedAttachmentUrl(path);
                                if (actor != repository.actorId || workerId != _selectedWorkerId) {
                                  throw StateError('Session changed');
                                }
                                return url;
                              }
                              final attachments = [
                                for (var i = 0; i < paths.length; i++)
                                  signedResourceAttachment(label: '${i + 1}', path: paths[i], signedUrl: signedUrl,
                                    previewKey: 'document:${requirement['id']}:$i', recordTitle: requirement['name']?.toString() ?? '書類'),
                              ];
                              final effective = _effectiveDocumentStatus(requirement, status, today);
                              final dates = DataDateLabels.labels(createdAt: status?['created_at'],
                                updatedAt: status?['updated_at']);
                              final exemption = documentExemptionFor(_exemptions, workerId, requirement['id']?.toString());
                              final exempt = exemption?['active'] == true;
                              final display = workerDocumentDisplayStatus(requirement, status, bankRegistered: _bankRegisteredFor(workerId), today: today);
                              return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                              ResourceRegistrationCard(
                                key: ValueKey('managed-document:$actor:$workerId:${requirement['id']}'),
                                title: requirement['name']?.toString() ?? '書類',
                                icon: Icons.description_outlined, registered: exempt || display.complete,
                                statusLabel: exempt ? '提出免除' : display.label,
                                dateLabel: dates.isEmpty ? '' : dates.first,
                                detailLabel: [if (exempt) '免除理由：${exemption!['reason']}',
                                  if (!exempt) resourceDocumentReviewLabel(effective),
                                  workerDocumentScopeLabel(requirement['scope']),
                                  requirement['is_required'] == true ? '必須' : '任意',
                                  if ((status?['expires_at']?.toString() ?? '').isNotEmpty) '期限 ${status?['expires_at']}',
                                  if (!exempt && _expiryHint(requirement, _parseDocumentDate(status?['expires_at']), today) != null)
                                    _expiryHint(requirement, _parseDocumentDate(status?['expires_at']), today)!,
                                  if (status?['original_verified'] == true) '原本確認済み',
                                  for (final date in DataDateLabels.labels(createdAt: requirement['created_at'],
                                    updatedAt: requirement['updated_at'])) '${SkoLanguageController.tr('書類項目')} $date',
                                  if (paths.length > 2) '添付 ${paths.length}件（詳細で確認）'].join(' / '),
                                attachments: attachments, gallery: _galleryForWorker(workerId), requireGalleryScope: true,
                                onAction: _canManageStatuses ? () => _editStatus(requirement, status)
                                  : paths.isEmpty ? null : () => showResourceAttachments(
                                    context, title: requirement['name']?.toString() ?? '書類', attachments: attachments,
                                    gallery: _galleryForWorker(workerId), requireGalleryScope: true),
                                onOpenDetail: _canManageStatuses ? () => _editStatus(requirement, status)
                                  : paths.isEmpty ? null : () => showResourceAttachments(
                                    context, title: requirement['name']?.toString() ?? '書類', attachments: attachments,
                                    gallery: _galleryForWorker(workerId), requireGalleryScope: true),
                              ),
                              if (_canManageStatuses && _repository?.exemptionEditingAvailable == true)
                                Align(alignment: Alignment.centerRight, child: TextButton.icon(
                                  icon: Icon(exempt ? Icons.undo : Icons.rule_outlined),
                                  label: Text(exempt ? '免除を解除' : 'この社員の提出を免除'),
                                  onPressed: () => _setExemption(requirement, exemption))),
                              ]);
                            },
                          ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildHome() => Scaffold(
    appBar: AppBar(title: Text(SkoLanguageController.tr('必要書類'))),
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : _error != null
        ? _ErrorState(message: _error!, onRetry: _reload)
        : WorkerDocumentEntryChoices(
            canManageRequirements: _canManageRequirements,
            onOpenWorkers: () => _openView(WorkerDocumentView.workers),
            onOpenSettings: () => _openView(WorkerDocumentView.settings),
          ),
  );

  Future<void> _openView(WorkerDocumentView view) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => WorkerDocumentPage(
          view: view,
          repositoryOverride: widget.repositoryOverride,
        ),
      ),
    );
    if (mounted) _reload();
  }

  Widget _buildSettings() {
    final rows = _requirements.where((r) => workerDocumentMatchesScope(r['scope'], _scope)).toList();
    return Scaffold(
      appBar: AppBar(
        title: Text(SkoLanguageController.tr('必要書類設定')),
        actions: [IconButton(
          tooltip: '必要書類設定のヘルプ', icon: const Icon(Icons.help_outline),
          onPressed: () => showDialog<void>(context: context,
            builder: (context) => AlertDialog(
              title: const Text('必要書類の表示と削除'),
              content: const Text('チェックは本人の書類登録への表示・非表示です。不要な重複項目は、ごみ箱から管理一覧と選択候補から削除できます。社内・取引先共用の項目は両方から外れます。\n\n提出済みデータ・添付写真・履歴・送信済みデータは保持します。削除済み項目は元の登録IDで復元でき、非表示で戻ります。表示する場合はチェックを入れてください。'),
              actions: [TextButton(onPressed: () => Navigator.pop(context),
                child: const Text('閉じる'))],
            )),
        )],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? _ErrorState(message: _error!, onRetry: _reload)
          : !_canManageRequirements
          ? Center(child: Text(SkoLanguageController.tr('必要書類を変更する権限がありません。')))
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: SegmentedButton<String>(
                    segments: [
                      ButtonSegment(
                        value: 'internal',
                        label: Text(SkoLanguageController.tr('社内')),
                      ),
                      ButtonSegment(
                        value: 'upstream',
                        label: Text(SkoLanguageController.tr('取引先')),
                      ),
                    ],
                    selected: {_scope},
                    onSelectionChanged: (v) =>
                        setState(() => _scope = v.single),
                  ),
                ),
                Wrap(
                  spacing: 8,
                  children: [
                    FilledButton.icon(
                      onPressed: _addRequirement,
                      icon: const Icon(Icons.add),
                      label: Text(SkoLanguageController.tr('必要書類を追加')),
                    ),
                    TextButton(
                      onPressed: _addDefaults,
                      child: Text(SkoLanguageController.tr('標準項目を追加')),
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Text(
                    SkoLanguageController.tr('チェックした項目を本人の「書類登録」に表示します。'),
                  ),
                ),
                if (_archivedRequirements.isNotEmpty)
                  TextButton(
                    onPressed: _showArchivedRequirements,
                    child: Text('削除済みの項目（${_archivedRequirements.length}件）'),
                  ),
                Expanded(
                  child: rows.isEmpty
                      ? Center(
                          child: Text(
                            SkoLanguageController.tr('必要書類の設定がまだありません'),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: rows.length,
                          itemBuilder: (context, i) {
                            final row = rows[i];
                            return Card(
                              child: ListTile(
                                title: Text(row['name']?.toString() ?? ''),
                                subtitle: Text(
                                  SkoLanguageController.tr(
                                    row['is_active'] == false ? '非表示' : (row['is_required'] == true ? '必須' : '任意'),
                                  ),
                                ),
                                onTap: row['is_active'] == false ? null : () => _editRequirement(row),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Tooltip(
                                      message: SkoLanguageController.tr('本人の書類登録に表示'),
                                      child: Checkbox(
                                        key: ValueKey('requirement-visible-${row['id']}'),
                                        semanticLabel: '${row['name']}：${SkoLanguageController.tr('本人の書類登録に表示')}',
                                        value: row['is_active'] != false,
                                        onChanged: _visibilitySaving.contains(row['id'])
                                            ? null
                                            : (visible) {
                                                if (visible != null) {
                                                  _setRequirementVisible(row, visible);
                                                }
                                              },
                                      ),
                                    ),
                                    IconButton(
                                      tooltip: row.containsKey('archived_at')
                                          ? '書類項目を削除' : '項目削除は準備中です',
                                      icon: const Icon(Icons.delete_outline),
                                      onPressed: !row.containsKey('archived_at') ||
                                          _visibilitySaving.contains(row['id'])
                                          ? null : () => _changeRequirementArchive(row),
                                    ),
                                    if (row['is_active'] != false)
                                      IconButton(
                                        tooltip: SkoLanguageController.tr('編集'),
                                        icon: const Icon(Icons.edit_outlined),
                                        onPressed: () => _editRequirement(row),
                                      ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }

  Future<void> _showArchivedRequirements() async {
    final selected = await showDialog<Map<String, dynamic>>(
      context: context, builder: (context) => AlertDialog(
        title: const Text('削除済みの書類項目'),
        content: SizedBox(width: 420, height: 280,
          child: ListView(children: [for (final row in _archivedRequirements)
            ListTile(title: Text(row['name']?.toString() ?? '書類'),
              subtitle: Text(workerDocumentScopeLabel(row['scope'])),
              trailing: TextButton(onPressed: () => Navigator.pop(context, row),
                child: const Text('復元'))),
          ])),
        actions: [TextButton(onPressed: () => Navigator.pop(context),
          child: const Text('閉じる'))],
      ));
    if (selected != null && mounted) {
      await _changeRequirementArchive(selected, restore: true);
    }
  }

  Future<void> _changeRequirementArchive(
    Map<String, dynamic> row, {bool restore = false}
  ) async {
    final id = row['id']?.toString();
    final actor = _loadedActorId;
    final repository = _repository;
    if (!_canManageRequirements || repository == null || id == null ||
        _visibilitySaving.contains(id)) {
      return;
    }
    setState(() => _visibilitySaving.add(id));
    try {
      final confirmed = await showDialog<bool>(context: context,
        builder: (context) => AlertDialog(
          title: Text(restore ? '書類項目を復元' : '書類項目を削除'),
          content: Text(restore
              ? '${row['name']}を元の登録IDで復元します。提出済みデータと履歴を引き継ぎ、本人への表示はオフで戻します。'
              : '${row['name']}を管理一覧と選択候補から削除します。提出済みデータ・添付・履歴・送信済みデータは保持します。${row['scope'] == 'both' ? '社内・取引先の両方から外れます。' : ''}'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false),
              child: const Text('キャンセル')),
            FilledButton(onPressed: () => Navigator.pop(context, true),
              child: Text(restore ? '復元' : '削除')),
          ],
        ));
      if (confirmed != true || !mounted) return;
      if (actor == null || repository.actorId != actor) {
        throw StateError('ログイン情報が変更されました。再読み込みしてください。');
      }
      if (restore) {
        await repository.restoreRequirement(row);
      } else {
        await repository.archiveRequirement(row);
      }
      if (mounted) await _load();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    } finally {
      if (mounted) setState(() => _visibilitySaving.remove(id));
    }
  }

  Future<void> _setRequirementVisible(Map<String, dynamic> row, bool visible) async {
    final id = row['id'] as String;
    if (_visibilitySaving.contains(id) || visible == (row['is_active'] != false)) return;
    final actor = _loadedActorId;
    setState(() => _visibilitySaving.add(id));
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(SkoLanguageController.tr(visible ? '必要書類を表示' : '必要書類を非表示')),
          content: Text(SkoLanguageController.tr(visible ? '書類登録の一覧に再表示します。' : '書類登録の一覧から外します。提出済みデータと写真は保持します。')),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(SkoLanguageController.tr('キャンセル')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(SkoLanguageController.tr(visible ? '表示' : '非表示')),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
      if (actor == null || _repository?.actorId != actor) {
        throw StateError('ログイン情報が変更されました。再読み込みしてください。');
      }
      await _repository?.setRequirementVisible(id, visible);
      if (mounted) await _load();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
      }
    } finally {
      if (mounted) setState(() => _visibilitySaving.remove(id));
    }
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
          builder: (_) => WorkerDocumentSendPage(workerIds: workerIds),
        ),
      );
      return;
    }

    await Navigator.of(context).push<PersonnelExportResult>(
      MaterialPageRoute(
        builder: (_) => PersonnelExportPage(
          title: '書類データ',
          workers: _exportWorkers,
          operation: operation,
          fixedKind: TransferPayloadKind.documentsOnly,
          initialWorkerIds: _selectedWorkerId == null
              ? const []
              : [_selectedWorkerId!],
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
      await repository.addDefaultRequirements(
        scope: widget.view == WorkerDocumentView.settings ? _scope : null,
      );
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('標準の必要書類候補を追加しました')));
    } catch (error) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('追加できませんでした: $error')));
    }
  }

  Future<void> _addRequirement() async {
    if (!_canManageRequirements || _loading) return;
    final selected = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        constraints: const BoxConstraints(maxWidth: 560),
        title: const Text('必要書類を選択'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView(
            shrinkWrap: true,
            children: [
              const Text('登録済みの書類を選ぶと、同じ写真・有効期限を使えます。両方で必要な書類は共用します。'),
              const SizedBox(height: 12),
              for (final row in _requirements)
                ListTile(
                  title: Text(row['name']?.toString() ?? ''),
                  subtitle: Text(workerDocumentScopeLabel(row['scope'])),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.pop(context, row['id'] as String),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('キャンセル')),
          FilledButton.icon(
            onPressed: () => Navigator.pop(context, '__new__'),
            icon: const Icon(Icons.add),
            label: const Text('新しい書類を登録'),
          ),
        ],
      ),
    );
    if (selected == null || !mounted) return;
    if (selected == '__new__') {
      await _editRequirement();
      return;
    }
    final matches = _requirements.where((row) => row['id'] == selected);
    if (matches.length != 1) return;
    final row = matches.single;
    await _editRequirement({
      ...row,
      if (!workerDocumentMatchesScope(row['scope'], _scope)) 'scope': 'both',
    });
  }

  Future<void> _editRequirement([Map<String, dynamic>? current]) async {
    final repository = _repository;
    if (repository == null) return;
    final actor = _loadedActorId;
    final nameController = TextEditingController(
      text: current?['name']?.toString() ?? '',
    );
    var scope =
        current?['scope']?.toString() ??
        (_scope == 'upstream' ? 'upstream' : 'internal');
    var isRequired = current?['is_required'] != false;
    var expiryRequired = current?['expiry_required'] == true;
    String? nameError;

    final route = DialogRoute<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          constraints: const BoxConstraints(maxWidth: 560),
          title: Text(
            SkoLanguageController.tr(current == null ? '必要書類を追加' : '必要書類を編集'),
          ),
          content: SizedBox(width: double.maxFinite,
            child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  autofocus: true,
                  decoration: InputDecoration(labelText: '書類名 *', errorText: nameError),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: scope,
                  decoration: const InputDecoration(labelText: '用途'),
                  items: const [
                    DropdownMenuItem(value: 'internal', child: Text('社内手続き')),
                    DropdownMenuItem(value: 'upstream', child: Text('取引先提出')),
                    DropdownMenuItem(value: 'both', child: Text('自社・取引会社で共用')),
                  ],
                  onChanged: (value) {
                    if (value != null) setDialogState(() => scope = value);
                  },
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('必須'),
                  value: isRequired,
                  onChanged: (value) =>
                      setDialogState(() => isRequired = value),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('有効期限あり'),
                  value: expiryRequired,
                  onChanged: (value) =>
                      setDialogState(() => expiryRequired = value),
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
                if (current == null && _archivedRequirements.any(
                  (row) => row['name']?.toString().trim() == nameController.text.trim(),
                )) {
                  setDialogState(() => nameError = '削除済みの同名項目があります。「削除済みの項目」から復元してください。');
                  return;
                }
                if (current == null && _requirements.any(
                  (row) => row['name']?.toString().trim() == nameController.text.trim(),
                )) {
                  setDialogState(() => nameError = '登録済みです。書類一覧から選択してください。');
                  return;
                }
                Navigator.pop(dialogContext, {
                  'name': nameController.text.trim(),
                  'scope': scope,
                  'isRequired': isRequired,
                  'expiryRequired': expiryRequired,
                });
              },
              child: Text(
                SkoLanguageController.tr(current == null ? '追加' : '保存'),
              ),
            ),
          ],
        ),
      ),
    );
    final draft = await Navigator.of(context, rootNavigator: true).push(route);
    // The dialog result arrives before its reverse transition is finished.
    unawaited(route.completed.then((_) => nameController.dispose()));
    if (draft == null || !mounted) return;

    try {
      if (actor == null || repository.actorId != actor) {
        throw StateError('ログイン情報が変更されました。再読み込みしてください。');
      }
      if (current == null) {
        await repository.addRequirement(
          name: draft['name'] as String,
          scope: draft['scope'] as String,
          isRequired: draft['isRequired'] as bool,
          expiryRequired: draft['expiryRequired'] as bool,
        );
      } else {
        await repository.updateRequirement(
          id: current['id'] as String,
          name: draft['name'] as String,
          scope: draft['scope'] as String,
          isRequired: draft['isRequired'] as bool,
          expiryRequired: draft['expiryRequired'] as bool,
        );
      }
      _reload();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('追加できませんでした: $error')));
    }
  }

  Future<void> _openChangeReviews() async {
    final repository = _repository;
    final actor = _loadedActorId;
    if (repository == null || actor == null || actor != repository.actorId) return;
    final changes = repository.createChangeRepository();
    try {
      final membership = await repository.membership();
      if (!mounted || !changes.isCurrentActor || actor != repository.actorId) return;
      await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => WorkerDocumentChangeReviewPage(
        repository: changes, companyId: membership.companyId,
        workerNames: {for (final row in _workers) row['id'].toString(): row['name']?.toString() ?? '対象者'},
        requirementNames: {for (final row in _retainedRequirements) row['id'].toString(): row['name']?.toString() ?? '書類'},
        isCurrent: () => mounted && actor == repository.actorId,
      )));
    } finally { await changes.dispose(); }
    if (mounted) _reload();
  }

  Future<void> _registerForSelectedWorker() async {
    final repository = _repository;
    final workerId = _selectedWorkerId;
    final actor = _loadedActorId;
    if (repository == null || actor == null || workerId == null ||
        !_canManageStatuses || _loading) { return; }
    bool sameScope() => mounted && actor == repository.actorId &&
      workerId == _selectedWorkerId && _canManageStatuses;
    if (!sameScope()) { return; }
    final options = _requirements.where((row) =>
      workerDocumentMatchesScope(row['scope'], _scope) &&
      (row['id']?.toString() ?? '').isNotEmpty).toList(growable: false);
    if (options.isEmpty) { return; }
    final chosen = await chooseRegisteredDocumentRequirement(context, [
      for (final row in options) ResourceRegistrationOption(
        id: row['id'].toString(), title: row['name']?.toString() ?? '書類'),
    ], isCurrentScope: sameScope);
    if (!sameScope() || chosen == null) { return; }
    final matches = options.where((row) => row['id']?.toString() == chosen).toList();
    if (matches.length != 1) { return; }
    final rows = _statuses.where((row) => row['worker_id']?.toString() == workerId &&
      row['requirement_id']?.toString() == chosen).toList(growable: false);
    if (rows.length > 1) { return; }
    await _editStatus(matches.single, rows.isEmpty ? null : rows.single);
  }

  Future<void> _setExemption(Map<String, dynamic> requirement,
      Map<String, dynamic>? previous) async {
    final repository = _repository;
    final workerId = _selectedWorkerId;
    final actor = _loadedActorId;
    final requirementId = requirement['id']?.toString();
    if (repository == null || workerId == null || requirementId == null ||
        actor == null || actor != repository.actorId || !_canManageStatuses) { return; }
    final active = previous?['active'] != true;
    final text = await showDialog<String>(context: context, builder: (_) =>
      _DocumentExemptionReasonDialog(active: active,
        documentName: requirement['name']?.toString() ?? '書類'));
    if (text == null || !mounted || workerId != _selectedWorkerId || actor != repository.actorId) { return; }
    try {
      await repository.setDocumentExemption(workerId: workerId, requirementId: requirementId,
        active: active, expectedVersion: previous?['version'] as int? ?? 0, reason: text);
      if (!mounted || actor != repository.actorId || workerId != _selectedWorkerId) return;
      await _load();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('免除を保存できませんでした。書類を再読み込みして確認してください。')));
      }
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
    final actor = _loadedActorId;
    void requireActor() {
      if (actor == null || repository.actorId != actor) {
        throw StateError('ログイン情報が変更されました。再読み込みしてください。');
      }
    }

    if (actor == null || repository.actorId != actor) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ログイン情報が変更されました。再読み込みしてください。')),
      );
      return;
    }

    if (workerDocumentHasRegisteredContent(current)) {
      final changes = repository.createChangeRepository();
      try {
        final membership = await repository.membership();
        if (!mounted || !changes.isCurrentActor || actor != repository.actorId || workerId != _selectedWorkerId) return;
        final snapshot = Map<String, dynamic>.from(current ?? const {});
        bool currentTarget() => mounted && actor == repository.actorId && workerId == _selectedWorkerId &&
            snapshot['company_id'] == membership.companyId && snapshot['worker_id'] == workerId &&
            _workers.any((row) => row['id'] == workerId && row['company_id'] == membership.companyId);
        final adminCorrection = await repository.createAdminCorrectionRepository(
          companyId: membership.companyId,
          targetId: snapshot['id'] as String,
          isCurrentTarget: currentTarget,
        );
        if (!mounted) {
          adminCorrection.dispose();
          return;
        }
        final handled = await openWorkerDocumentAdminCorrection(
          context: context,
          repository: adminCorrection,
          snapshot: snapshot,
          documentName: requirement['name']?.toString() ?? '書類',
          isCurrentTarget: currentTarget,
        );
        if (handled) {
          if (mounted) {
            _reload();
          }
          return;
        }
        await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => WorkerDocumentChangePage(
          repository: changes, actor: actor, companyId: membership.companyId, row: current!,
          signedUrl: repository.createSignedAttachmentUrl,
          onVerification: (status, verified) async {
            if (!mounted || !changes.isCurrentActor || workerId != _selectedWorkerId) throw StateError('Scope changed');
            await repository.confirmDocumentStatus(current, status: status, originalVerified: verified);
          },
          isCurrent: () => mounted && actor == repository.actorId && workerId == _selectedWorkerId,
        )));
      } finally { await changes.dispose(); }
      if (mounted) _reload();
      return;
    }

    var savingPhotos = false;
    List<WorkerDocumentPhoto>? selectedPhotos;
    var status = current?['status']?.toString() ?? 'not_submitted';
    var originalVerified = current?['original_verified'] == true;
    DateTime? expiresAt = _parseDate(current?['expires_at']);
    final notesController = TextEditingController(
      text: current?['notes']?.toString() ?? '',
    );

    final save = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(requirement['name']?.toString() ?? '書類'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text([workerDocumentScopeLabel(requirement['scope']),
                  requirement['is_required'] == true ? '必須' : '任意'].join(' / ')),
                for (final date in DataDateLabels.labels(createdAt: requirement['created_at'],
                    updatedAt: requirement['updated_at']))
                  Align(alignment: Alignment.centerLeft, child: Text('${SkoLanguageController.tr('書類項目')} $date')),
                for (final date in DataDateLabels.labels(createdAt: current?['created_at'],
                    updatedAt: current?['updated_at']))
                  Align(alignment: Alignment.centerLeft, child: Text(date)),
                DropdownButtonFormField<String>(
                  key: ValueKey('status:$status'),
                  initialValue: status,
                  decoration: const InputDecoration(labelText: '状態'),
                  items: const [
                    DropdownMenuItem(
                      value: 'not_submitted',
                      child: Text('未提出'),
                    ),
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
                    subtitle: Text(
                      expiresAt == null ? '未設定' : _formatDate(expiresAt!),
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
                ],
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('原本確認済み'),
                  value: originalVerified,
                  onChanged: (value) =>
                      setDialogState(() => originalVerified = value ?? false),
                ),
                TextField(
                  controller: notesController,
                  decoration: const InputDecoration(labelText: '備考'),
                  maxLines: 3,
                ),
                if (workerDocumentPaths(current).isNotEmpty)
                  Text('登録写真 ${workerDocumentPaths(current).length}枚'),
              ],
            ),
          ),
          actions: [
            TextButton.icon(
              onPressed: savingPhotos
                  ? null
                  : () async {
                      setDialogState(() => savingPhotos = true);
                      try {
                        requireActor();
                        final photos = await editWorkerDocumentPhotos(
                          dialogContext,
                          paths: workerDocumentPaths(current),
                          signedUrl: (path) async {
                            requireActor();
                            final url = await repository
                                .createSignedAttachmentUrl(path);
                            requireActor();
                            return url;
                          },
                          canEdit: repository.photoEditingAvailable,
                          initialPhotos: selectedPhotos,
                        );
                        if (photos == null || !dialogContext.mounted) return;
                        requireActor();
                        setDialogState(() {
                          selectedPhotos = photos;
                          if (current == null &&
                              photos.isNotEmpty &&
                              status == 'not_submitted') {
                            status = 'submitted';
                          }
                        });
                      } catch (error) {
                        if (dialogContext.mounted) {
                          ScaffoldMessenger.of(dialogContext).showSnackBar(
                            SnackBar(content: Text('写真を選択できませんでした: $error')),
                          );
                        }
                      } finally {
                        if (dialogContext.mounted) {
                          setDialogState(() => savingPhotos = false);
                        }
                      }
                    },
              icon: const Icon(Icons.photo_library_outlined),
              label: Text(
                repository.photoEditingAvailable
                    ? '写真を登録・編集${selectedPhotos == null ? '' : ' (${selectedPhotos!.length}枚・保存前)'}'
                    : '写真を確認',
              ),
            ),
            TextButton(
              onPressed: savingPhotos
                  ? null
                  : () => Navigator.pop(dialogContext, false),
              child: const Text('キャンセル'),
            ),
            FilledButton(
              onPressed: savingPhotos
                  ? null
                  : () => Navigator.pop(dialogContext, true),
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
      requireActor();
      if (selectedPhotos != null && repository.photoEditingAvailable) {
        await repository.saveManagedDocumentPhotos(
          workerId: workerId,
          requirementId: requirementId,
          status: status,
          expiresAt: expiresAt,
          originalVerified: originalVerified,
          notes: notes,
          photos: selectedPhotos!,
          expectedRow: current,
        );
      } else {
        await repository.updateStatus(
          workerId: workerId,
          requirementId: requirementId,
          status: status,
          expiresAt: expiresAt,
          originalVerified: originalVerified,
          notes: notes,
        );
      }
      requireActor();
      _reload();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('保存できませんでした: $error')));
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

DateTime _dateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);

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

String? _expiryHint(Map<String, dynamic> requirement, DateTime? expiry, DateTime now) {
  if (requirement['expiry_required'] != true || expiry == null) { return null; }
  final days = expiry.difference(_dateOnly(now)).inDays;
  if (days < 0) { return '期限切れ'; }
  if (days == 0) { return '本日期限'; }
  if (days <= _reminderDays(requirement)) { return 'あと$days日'; }
  return null;
}

class _DocumentExemptionReasonDialog extends StatefulWidget {
  const _DocumentExemptionReasonDialog({required this.active, required this.documentName});
  final bool active;
  final String documentName;
  @override
  State<_DocumentExemptionReasonDialog> createState() => _DocumentExemptionReasonDialogState();
}

class _DocumentExemptionReasonDialogState extends State<_DocumentExemptionReasonDialog> {
  final _reason = TextEditingController();
  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.active ? 'この社員の提出を免除' : '提出免除を解除'),
    content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
      Text('${widget.documentName}\nこの社員だけに適用します。登録済み書類・写真は保持します。'),
      TextField(controller: _reason, maxLength: 500, minLines: 2, maxLines: 4,
        onChanged: (_) => setState(() {}),
        decoration: const InputDecoration(labelText: '理由（必須）')),
    ])),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('キャンセル')),
      FilledButton(onPressed: _reason.text.trim().isEmpty ? null
          : () => Navigator.pop(context, _reason.text.trim()),
        child: Text(widget.active ? '免除を保存' : '免除を解除')),
    ],
  );
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

class WorkerDocumentRegistrationActions extends StatelessWidget {
  const WorkerDocumentRegistrationActions({
    super.key,
    required this.canManage,
    required this.photoEditingAvailable,
    required this.onAddRequirement,
  });
  final bool canManage;
  final bool photoEditingAvailable;
  final VoidCallback onAddRequirement;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('本人の提出は「自分の書類を登録」から開けます。'),
        if (canManage)
          OutlinedButton.icon(
            onPressed: onAddRequirement,
            icon: const Icon(Icons.add),
            label: const Text('必要書類の項目を追加'),
          ),
        if (canManage) const Text('各項目の登録ボタンから、状態と写真をまとめて登録できます。'),
        if (!photoEditingAvailable)
          const Text(WorkerDocumentRepository.photoPreparationMessage),
      ],
    ),
  );
}

class WorkerDocumentEntryChoices extends StatelessWidget {
  const WorkerDocumentEntryChoices({
    super.key,
    required this.canManageRequirements,
    required this.onOpenWorkers,
    required this.onOpenSettings,
  });
  final bool canManageRequirements;
  final VoidCallback onOpenWorkers;
  final VoidCallback onOpenSettings;
  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      Card(
        child: ListTile(
          leading: const Icon(Icons.person_search_outlined),
          title: Text(SkoLanguageController.tr('従業員データ編集')),
          subtitle: Text(SkoLanguageController.tr('従業員を検索して、提出済みの書類を確認・編集')),
          trailing: const Icon(Icons.chevron_right),
          onTap: onOpenWorkers,
        ),
      ),
      if (canManageRequirements)
        Card(
          child: ListTile(
            leading: const Icon(Icons.tune_outlined),
            title: Text(SkoLanguageController.tr('必要書類設定')),
            subtitle: Text(SkoLanguageController.tr('社内・取引先の書類項目を追加・編集・表示設定')),
            trailing: const Icon(Icons.chevron_right),
            onTap: onOpenSettings,
          ),
        ),
    ],
  );
}




