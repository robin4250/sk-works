import 'package:flutter/material.dart';

import '../notifications/notification_bell.dart';
import '../../international/language_controller.dart';
import 'site_cloud_repository.dart';
import 'site_detail_page.dart';
import 'site_map_page.dart';
import 'site_page.dart';
import 'registered_site_search.dart';
import 'site_compact_controls.dart';

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
    final filtered = filterRegisteredSites(_sites, query: _query, status: _filter);
    final controlHeight = siteControlHeight(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(SkoLanguageController.tr('現場データ')),
        actions: [
          const SkoNotificationBell(),
          IconButton(
            tooltip: SkoLanguageController.tr('再読み込み'),
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
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 88),
        child: SizedBox(
          width: MediaQuery.sizeOf(context).width - 32,
          child: Row(
            children: [
              Expanded(
                child: SiteCompactAction(
                  height: controlHeight,
                  controlKey: 'site_map',
                  onPressed: _loading
                      ? null
                      : () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const GeneralSiteMapPage(),
                            ),
                          ),
                  icon: const Icon(Icons.map_outlined),
                  label: Text(SkoLanguageController.tr('現場マップ')),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SiteCompactAction(
                  height: controlHeight,
                  controlKey: 'site_register',
                  onPressed: _loading || !_canCreateSites ? null : _add,
                  icon: const Icon(Icons.add_business),
                  label: Text(SkoLanguageController.tr('現場登録')),
                ),
              ),
            ],
          ),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: TextField(
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search),
                  helperText: SkoLanguageController.tr(
                    '登録済み現場ID・正式名でも検索できます',
                  ),
                  hintText: SkoLanguageController.tr(
                    '現場名・取引先・担当者・住所・最寄駅で検索',
                  ),
                ),
                onChanged: (value) => setState(() => _query = value),
              ),
            ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  SiteCompactFilter(
                    height: controlHeight,
                    label: Text(SkoLanguageController.tr('すべて')),
                    selected: _filter == null,
                    onSelected: (_) => setState(() => _filter = null),
                  ),
                  const SizedBox(width: 8),
                  for (final status in SiteStatus.values) ...[
                    SiteCompactFilter(
                      height: controlHeight,
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
                          ? Center(child: Text(SkoLanguageController.tr('登録はまだありません')))
                          : ListView.separated(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
                              itemCount: filtered.length,
                              separatorBuilder: (_, __) => const SizedBox(height: 8),
                              itemBuilder: (context, index) {
                                final site = filtered[index];
                                return SiteCompactCard(
                                  height: controlHeight,
                                  name: site.name,
                                  details: [
                                    site.customerName,
                                    site.status.label,
                                    if (site.managerName.isNotEmpty) site.managerName,
                                  ].join(' / '),
                                  onTap: () => Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => SiteDetailPage(
                                        site: site,
                                        canManage: _canManageSites,
                                        onComplete: () => _complete(site),
                                      ),
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

  Future<void> _add() async {
    final repository = _repository;
    if (repository == null) return;
    final saved = await Navigator.of(context).push<SiteRecord>(
      MaterialPageRoute(
        builder: (_) => SiteFormPage(
          onSave: (draft) async {
            final row = await repository.insert(draft.toJson());
            final result = SiteRecord.fromJson(row);
            if (result.id.isEmpty) throw StateError('保存結果を確認できません。');
            return result;
          },
        ),
      ),
    );
    if (!mounted || saved == null) return;
    setState(() => _sites.insert(0, saved));
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('現場の登録が完了しました'),
        content: Text('「${saved.name}」を登録しました。現場一覧から詳細・写真を確認できます。'),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('現場一覧へ'),
          ),
        ],
      ),
    );
  }

  Future<void> _complete(SiteRecord site) async {
    final repository = _repository;
    if (repository == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(SkoLanguageController.tr('現場終了の確認')),
        content: Text(
          '「${site.name}」を終了します。現場チャットは削除せず、履歴を残したままアーカイブします。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(SkoLanguageController.tr('戻る')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(SkoLanguageController.tr('現場を終了')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await repository.complete(site.id);
    if (!mounted) return;
    await _load();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(SkoLanguageController.tr('現場を終了し、チャットをアーカイブしました'))),
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
