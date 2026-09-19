import 'package:flutter/material.dart';

import 'site_cloud_repository.dart';
import 'site_page.dart';

class SiteCloudPage extends StatefulWidget {
  const SiteCloudPage({super.key});

  @override
  State<SiteCloudPage> createState() => _SiteCloudPageState();
}

class _SiteCloudPageState extends State<SiteCloudPage> {
  final _repository = SiteCloudRepository.maybeCreate();
  final _sites = <SiteRecord>[];
  String _query = '';
  SiteStatus? _filter;
  bool _loading = true;
  bool _canManageSites = false;
  bool _canCreateSites = false;
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
        repository.canManageSites(),
        repository.canCreateSites(),
      ]);
      final rows = values[0] as List<Map<String, dynamic>>;
      final loaded = rows.map(SiteRecord.fromJson).toList();
      if (!mounted) return;
      setState(() {
        _sites
          ..clear()
          ..addAll(loaded);
        _canManageSites = values[1] as bool;
        _canCreateSites = values[2] as bool;
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
    final filtered = _sites.where((site) {
      final matchesStatus = _filter == null || site.status == _filter;
      final haystack = [
        site.name,
        site.customerName,
        site.address,
        site.managerName,
        site.notes,
      ].join(' ').toLowerCase();
      return matchesStatus && (needle.isEmpty || haystack.contains(needle));
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(_canManageSites ? '管理者用現場データ' : '現場'),
        actions: [
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
        onPressed: _loading || !_canCreateSites ? null : _add,
        icon: const Icon(Icons.add_business),
        label: const Text('現場登録'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: TextField(
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: '現場名・得意先・担当者・住所で検索',
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
                  for (final status in SiteStatus.values) ...[
                    ChoiceChip(
                      label: Text(status.label),
                      selected: _filter == status,
                      onSelected: (_) => setState(() => _filter = status),
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
                                final site = filtered[index];
                                return Card(
                                  child: ListTile(
                                    leading: const CircleAvatar(
                                      child: Icon(Icons.apartment_outlined),
                                    ),
                                    title: Text(
                                      site.name,
                                      style: const TextStyle(fontWeight: FontWeight.w700),
                                    ),
                                    subtitle: Text([
                                      site.customerName,
                                      site.status.label,
                                      if (site.managerName.isNotEmpty) site.managerName,
                                    ].join(' / ')),
                                    trailing: const Icon(Icons.chevron_right),
                                    onTap: () => _showDetails(site),
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
    final draft = await Navigator.of(context).push<SiteRecord>(
      MaterialPageRoute(builder: (_) => const SiteFormPage()),
    );
    final repository = _repository;
    if (draft == null || repository == null) return;
    try {
      final row = await repository.insert(draft.toJson());
      final saved = SiteRecord.fromJson(row);
      if (!mounted) return;
      setState(() => _sites.insert(0, saved));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('現場をクラウドに登録しました')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('登録できませんでした: $error')),
      );
    }
  }

  void _showDetails(SiteRecord site) {
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
              Text(site.name, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              Text('得意先: ${site.customerName}'),
              Text('状態: ${site.status.label}'),
              if (site.managerName.isNotEmpty) Text('担当者: ${site.managerName}'),
              if (site.address.isNotEmpty) Text('住所: ${site.address}'),
              if (site.startDate.isNotEmpty) Text('開始日: ${site.startDate}'),
              if (site.endDate.isNotEmpty) Text('終了日: ${site.endDate}'),
              if (site.notes.isNotEmpty) Text('備考: ${site.notes}'),
              const SizedBox(height: 16),
              if (_canManageSites)
                OutlinedButton.icon(
                onPressed: () async {
                  Navigator.pop(sheetContext);
                  await _delete(site);
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

  Future<void> _delete(SiteRecord site) async {
    final repository = _repository;
    if (repository == null) return;
    try {
      await repository.delete(site.id);
      if (!mounted) return;
      setState(() => _sites.removeWhere((item) => item.id == site.id));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('現場を削除しました')),
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
