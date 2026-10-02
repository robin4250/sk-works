import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../domain/company_data_transfer.dart';
import '../notifications/notification_bell.dart';
import '../../international/language_controller.dart';
import '../common/data_date_labels.dart';
import '../qualifications/qualification_send_page.dart';
import 'employee_personnel_detail_page.dart';
import 'employee_personnel_print_page.dart';
import 'member_permission_page.dart';
import 'personnel_bundle_send_page.dart';
import 'personnel_export_page.dart';
import 'people_cloud_repository.dart';
import 'people_page.dart';
import 'phone_display.dart';
import 'worker_document_send_page.dart';

class PeopleCloudPage extends StatefulWidget {
  const PeopleCloudPage({super.key});

  @override
  State<PeopleCloudPage> createState() => _PeopleCloudPageState();
}

class _PeopleCloudPageState extends State<PeopleCloudPage> {
  final _repository = PeopleCloudRepository.maybeCreate();
  final _records = <PersonRecord>[];
  String _query = '';
  PersonKind? _filter;
  bool _loading = true;
  bool _canManagePeople = false;
  String _companyName = '';
  String? _error;

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
        repository.canManagePeople(),
        repository.companyName(),
      ]);
      final rows = values[0] as List<Map<String, dynamic>>;
      final loaded = rows.map(PersonRecord.fromJson).toList();
      if (!mounted) return;
      setState(() {
        _records
          ..clear()
          ..addAll(loaded);
        _canManagePeople = values[1] as bool;
        _companyName = values[2] as String;
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
    final needle = _query.trim().toLowerCase();
    final filtered = _records.where((record) {
      final matchesKind = _filter == null || record.kind == _filter;
      final haystack = [
        record.name,
        record.companyName,
        record.phone,
        record.email,
        record.role,
        record.notes,
      ].join(' ').toLowerCase();
      return matchesKind && (needle.isEmpty || haystack.contains(needle));
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(SkoLanguageController.tr('社員')),
        actions: [
          const SkoNotificationBell(),
          IconButton(
            tooltip: 'A4横プレビュー確認後に送信',
            onPressed: _loading || _records.isEmpty
                ? null
                : () => _openExportWithScope(PersonnelExportOperation.send),
            icon: const Icon(Icons.send_outlined),
          ),
          IconButton(
            tooltip: 'A4横プレビュー・印刷',
            onPressed: _loading || _records.isEmpty
                ? null
                : () => _openExportWithScope(PersonnelExportOperation.print),
            icon: const Icon(Icons.print_outlined),
          ),
          if (_canManagePeople)
            IconButton(
              tooltip: '利用者の権限設定',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const MemberPermissionPage(),
                ),
              ),
              icon: const Icon(Icons.manage_accounts_outlined),
            ),
          IconButton(
            tooltip: SkoLanguageController.tr('再読み込み'),
            onPressed: _loading ? null : () {
              setState(() => _loading = true);
              _load();
            },
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _loading || !_canManagePeople ? null : _add,
        icon: const Icon(Icons.person_add_alt_1),
        label: Text(SkoLanguageController.tr('新規登録')),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: TextField(
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search),
                  hintText: SkoLanguageController.isEnglish ? 'Search by name, company, phone, etc.' : '氏名・会社名・電話番号などで検索',
                ),
                onChanged: (value) => setState(() => _query = value),
              ),
            ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  ChoiceChip(
                    label: Text(SkoLanguageController.tr('すべて')),
                    selected: _filter == null,
                    onSelected: (_) => setState(() => _filter = null),
                  ),
                  const SizedBox(width: 8),
                  for (final kind in PersonKind.values) ...[
                    ChoiceChip(
                      label: Text(kind.label),
                      selected: _filter == kind,
                      onSelected: (_) => setState(() => _filter = kind),
                    ),
                    const SizedBox(width: 8),
                  ],
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
                          ? Center(child: Text(SkoLanguageController.tr('登録はまだありません')))
                          : ListView.separated(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
                              itemCount: filtered.length,
                              separatorBuilder: (_, __) => const SizedBox(height: 8),
                              itemBuilder: (context, index) {
                                final record = filtered[index];
                                final subtitleParts = <String>[
                                  record.kind.label,
                                  if (record.companyName.isNotEmpty) record.companyName,
                                  if (record.role.isNotEmpty) record.role,
                                ];
                                return Card(
                                  child: ListTile(
                                    leading: CircleAvatar(
                                      child: Icon(
                                        record.kind == PersonKind.partnerCompany
                                            ? Icons.business_outlined
                                            : Icons.person_outline,
                                      ),
                                    ),
                                    title: Text(
                                      record.name,
                                      style: const TextStyle(fontWeight: FontWeight.w700),
                                    ),
                                    subtitle: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(subtitleParts.join(' / ')),
                                        if (record.phone.isNotEmpty)
                                          InkWell(
                                            onTap: () => _callPhone(
                                              record.phone,
                                            ),
                                            child: Padding(
                                              padding:
                                                  const EdgeInsets.only(top: 4),
                                              child: Row(
                                                mainAxisSize:
                                                    MainAxisSize.min,
                                                children: [
                                                  const Icon(
                                                    Icons.phone_outlined,
                                                    size: 16,
                                                  ),
                                                  const SizedBox(width: 4),
                                                  Text(
                                                    domesticPhoneDisplay(
                                                      record.phone,
                                                    ),
                                                    style: TextStyle(
                                                      color: Theme.of(context)
                                                          .colorScheme
                                                          .primary,
                                                      decoration:
                                                          TextDecoration
                                                              .underline,
                                                      fontWeight:
                                                          FontWeight.w700,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                    trailing: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        if (record.phone.isNotEmpty)
                                          IconButton(
                                            tooltip: SkoLanguageController.isEnglish ? 'Call' : '電話をかける',
                                            onPressed: () =>
                                                _callPhone(record.phone),
                                            icon: const Icon(Icons.phone_outlined),
                                          ),
                                        const Icon(Icons.chevron_right),
                                      ],
                                    ),
                                    onTap: !_canManagePeople
                                        ? null
                                        : () {
                                            if (record.kind ==
                                                PersonKind.partnerCompany) {
                                              _showDetails(record);
                                              return;
                                            }
                                            Navigator.of(context).push(
                                              MaterialPageRoute(
                                                builder: (_) =>
                                                    EmployeePersonnelDetailPage(
                                                  record: record,
                                                  allEmployees: _records
                                                      .where(
                                                        (item) =>
                                                            item.kind !=
                                                            PersonKind.partnerCompany,
                                                      )
                                                      .toList(growable: false),
                                                  companyName: _companyName,
                                                ),
                                              ),
                                            );
                                          },
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

  Future<void> _add() async {
    final draft = await Navigator.of(context).push<PersonRecord>(
      MaterialPageRoute(builder: (_) => const PersonFormPage()),
    );
    if (draft == null || _repository == null) return;
    try {
      final row = await _repository.insert(draft.toJson());
      final saved = PersonRecord.fromJson(row);
      if (!mounted) return;
      setState(() => _records.insert(0, saved));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('クラウドに登録しました')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('登録できませんでした: $error')),
      );
    }
  }

  void _showDetails(PersonRecord record) {
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
              Text(record.name, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              Text('区分: ${record.kind.label}'),
              if (record.companyName.isNotEmpty) Text('会社: ${record.companyName}'),
              if (record.role.isNotEmpty) Text('役割・職種: ${record.role}'),
              if (record.phone.isNotEmpty)
                TextButton.icon(
                  onPressed: () => _callPhone(record.phone),
                  icon: const Icon(Icons.phone_outlined),
                  label: Text(
                    '電話: ${domesticPhoneDisplay(record.phone)}',
                  ),
                ),
              if (record.email.isNotEmpty) Text('メール: ${record.email}'),
              if (record.notes.isNotEmpty) Text('備考: ${record.notes}'),
              for (final label in DataDateLabels.labels(
                createdAt: record.createdAt,
                updatedAt: record.updatedAt,
              ))
                Text(label),
              const SizedBox(height: 16),
              if (record.kind != PersonKind.partnerCompany) ...[
                FilledButton.icon(
                  onPressed: () {
                    Navigator.pop(sheetContext);
                    _openPersonExport(record);
                  },
                  icon: const Icon(Icons.ios_share_outlined),
                  label: Text(SkoLanguageController.tr('送信・印刷')),
                ),
                const SizedBox(height: 8),
              ],
              if (_canManagePeople)
                OutlinedButton.icon(
                onPressed: () async {
                  Navigator.pop(sheetContext);
                  await _delete(record);
                },
                icon: const Icon(Icons.delete_outline),
                label: Text(SkoLanguageController.tr('削除')),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openExportWithScope(
    PersonnelExportOperation operation,
  ) async {
    final employees = _records
        .where((record) => record.kind != PersonKind.partnerCompany)
        .toList(growable: false);
    if (employees.isEmpty || !mounted) return;

    final all = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.groups_2_outlined),
              title: Text(SkoLanguageController.tr('社員一覧')),
              subtitle: const Text('全社員をA4横向きでプレビュー'),
              onTap: () => Navigator.pop(sheetContext, true),
            ),
            ListTile(
              leading: const Icon(Icons.person_outline),
              title: Text(SkoLanguageController.tr('個別')),
              subtitle: const Text('社員を1名選んでA4横向きでプレビュー'),
              onTap: () => Navigator.pop(sheetContext, false),
            ),
          ],
        ),
      ),
    );
    if (all == null || !mounted) return;

    if (all) {
      await _openExport(operation);
      return;
    }

    final selected = await showModalBottomSheet<PersonRecord>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(sheetContext).height * 0.72,
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
            itemCount: employees.length,
            separatorBuilder: (_, __) => const SizedBox(height: 6),
            itemBuilder: (_, index) {
              final record = employees[index];
              return ListTile(
                leading: const CircleAvatar(
                  child: Icon(Icons.person_outline),
                ),
                title: Text(record.name),
                subtitle: Text(
                  [
                    record.kind.label,
                    if (record.role.trim().isNotEmpty) record.role,
                  ].join(' / '),
                ),
                onTap: () => Navigator.pop(sheetContext, record),
              );
            },
          ),
        ),
      ),
    );
    if (selected == null || !mounted) return;
    await _openExport(operation, initialRecord: selected);
  }

  Future<void> _openExport(
    PersonnelExportOperation operation, {
    PersonRecord? initialRecord,
  }) async {
    final records = initialRecord == null
        ? _records
            .where((record) => record.kind != PersonKind.partnerCompany)
            .toList(growable: false)
        : [initialRecord];
    if (records.isEmpty || !mounted) return;

    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => EmployeePersonnelPrintPage(
          companyName: _companyName,
          records: records,
          action: operation == PersonnelExportOperation.send
              ? EmployeePersonnelPreviewAction.send
              : EmployeePersonnelPreviewAction.print,
          onConfirmSend: operation == PersonnelExportOperation.send
              ? (previewContext) async {
                  await Navigator.of(previewContext).push<bool>(
                    MaterialPageRoute(
                      builder: (_) => PersonnelBundleSendPage(
                        workerIds: records.map((record) => record.id).toSet(),
                      ),
                    ),
                  );
                }
              : null,
        ),
      ),
    );
  }

  Future<void> _openPersonExport(PersonRecord record) async {
    final operation = await showModalBottomSheet<PersonnelExportOperation>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.send_outlined),
              title: Text(SkoLanguageController.tr('親会社に送る')),
              subtitle: const Text('送信内容を選び、送信先を確認してから確定します'),
              onTap: () => Navigator.pop(
                sheetContext,
                PersonnelExportOperation.send,
              ),
            ),
            ListTile(
              leading: const Icon(Icons.print_outlined),
              title: Text(SkoLanguageController.tr('印刷')),
              subtitle: const Text('印刷内容を確認してから印刷画面を開きます'),
              onTap: () => Navigator.pop(
                sheetContext,
                PersonnelExportOperation.print,
              ),
            ),
          ],
        ),
      ),
    );
    if (operation == null || !mounted) return;

    if (operation == PersonnelExportOperation.print) {
      await _openExport(operation, initialRecord: record);
      return;
    }

    final kind = await showModalBottomSheet<TransferPayloadKind>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.person_pin_outlined),
              title: Text(SkoLanguageController.tr('一式')),
              subtitle: const Text('基本情報＋資格＋元請向け書類'),
              onTap: () => Navigator.pop(
                sheetContext,
                TransferPayloadKind.personnelBundle,
              ),
            ),
            ListTile(
              leading: const Icon(Icons.badge_outlined),
              title: Text(SkoLanguageController.tr('資格のみ')),
              onTap: () => Navigator.pop(
                sheetContext,
                TransferPayloadKind.qualificationsOnly,
              ),
            ),
            ListTile(
              leading: const Icon(Icons.description_outlined),
              title: Text(SkoLanguageController.tr('書類のみ')),
              onTap: () => Navigator.pop(
                sheetContext,
                TransferPayloadKind.documentsOnly,
              ),
            ),
          ],
        ),
      ),
    );
    if (kind == null || !mounted) return;

    final workerIds = <String>{record.id};
    final page = switch (kind) {
      TransferPayloadKind.personnelBundle =>
        PersonnelBundleSendPage(workerIds: workerIds),
      TransferPayloadKind.qualificationsOnly =>
        QualificationSendPage(workerIds: workerIds),
      TransferPayloadKind.documentsOnly =>
        WorkerDocumentSendPage(workerIds: workerIds),
    };
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => page),
    );
  }
  Future<void> _callPhone(String phone) async {
    final domestic = domesticPhoneDisplay(phone);
    final dial = domestic.replaceAll(RegExp(r'[^0-9+]'), '');
    if (dial.isEmpty) return;
    final uri = Uri(scheme: 'tel', path: dial);
    if (!await launchUrl(uri) && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('電話を開始できませんでした')),
      );
    }
  }

  Future<void> _delete(PersonRecord record) async {
    final repository = _repository;
    if (repository == null) return;
    try {
      await repository.delete(record.toJson());
      if (!mounted) return;
      setState(() => _records.removeWhere((item) => item.id == record.id));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('削除しました')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('削除できませんでした: $error')),
      );
    }
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
            Text(SkoLanguageController.tr('クラウドデータを読み込めませんでした')),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: Text(SkoLanguageController.tr('再試行')),
            ),
          ],
        ),
      ),
    );
  }
}
