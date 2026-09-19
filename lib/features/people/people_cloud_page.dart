import 'package:flutter/material.dart';

import '../notifications/notification_bell.dart';
import 'people_cloud_repository.dart';
import 'people_page.dart';

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
      ]);
      final rows = values[0] as List<Map<String, dynamic>>;
      final loaded = rows.map(PersonRecord.fromJson).toList();
      if (!mounted) return;
      setState(() {
        _records
          ..clear()
          ..addAll(loaded);
        _canManagePeople = values[1] as bool;
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
        title: const Text('社員・協力会社'),
        actions: [
          const SkoNotificationBell(),
          IconButton(
            tooltip: '再読み込み',
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
        label: const Text('新規登録'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: TextField(
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: '氏名・会社名・電話番号などで検索',
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
                    label: const Text('すべて'),
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
                          ? const Center(child: Text('登録はまだありません'))
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
                                  if (record.phone.isNotEmpty) record.phone,
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
                                    subtitle: Text(subtitleParts.join(' / ')),
                                    trailing: const Icon(Icons.chevron_right),
                                    onTap: () => _showDetails(record),
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
              if (record.phone.isNotEmpty) Text('電話: ${record.phone}'),
              if (record.email.isNotEmpty) Text('メール: ${record.email}'),
              if (record.notes.isNotEmpty) Text('備考: ${record.notes}'),
              const SizedBox(height: 16),
              if (_canManagePeople)
                OutlinedButton.icon(
                onPressed: () async {
                  Navigator.pop(sheetContext);
                  await _delete(record);
                },
                icon: const Icon(Icons.delete_outline),
                label: const Text('削除'),
              ),
            ],
          ),
        ),
      ),
    );
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
