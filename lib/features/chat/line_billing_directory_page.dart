import 'package:flutter/material.dart';
import 'line_import_repository.dart';
import 'line_import_page.dart';
import 'line_historical_invoice_page.dart';
import 'line_source_upload_page.dart';
import 'line_release_access.dart';

enum LineBillingDirectoryKind { monthly, invoices, rates }
typedef LineReadingRulesBuilder = Widget Function(BuildContext context, String groupId, List<Map<String,dynamic>> sources);

class LineBillingDirectoryPage extends StatelessWidget {
  const LineBillingDirectoryPage({super.key, required this.kind, this.readingRulesBuilder, this.repositoryOverride});
  final LineBillingDirectoryKind kind;
  final LineReadingRulesBuilder? readingRulesBuilder;
  @visibleForTesting
  final LineImportRepository? repositoryOverride;
  @override
  Widget build(BuildContext context) => LineReleaseBoundary(builder: (_) =>
    _Directory(kind: kind, readingRulesBuilder: readingRulesBuilder, repositoryOverride: repositoryOverride));
}

class _Directory extends StatefulWidget {
  const _Directory({required this.kind, this.readingRulesBuilder, this.repositoryOverride});
  final LineBillingDirectoryKind kind;
  final LineReadingRulesBuilder? readingRulesBuilder;
  final LineImportRepository? repositoryOverride;
  @override
  State<_Directory> createState() => _DirectoryState();
}

class _DirectoryState extends State<_Directory> {
  late final _repository = widget.repositoryOverride ?? LineImportRepository.maybeCreate();
  final _entries = <Map<String, dynamic>>[];
  List<Map<String,dynamic>> _destinations = const [];
  bool _loading = true;
  String? _error;
  String get _title => switch (widget.kind) {
    LineBillingDirectoryKind.monthly => '月単位の一覧表',
    LineBillingDirectoryKind.invoices => '月単位の請求書一覧',
    LineBillingDirectoryKind.rates => '現場別の単価設定',
  };
  @override
  void initState() { super.initState(); _load(); }
  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      if (_repository == null) throw StateError('Login required');
      final destinations = await _repository.destinations();
      _destinations = destinations;
      final entries = <Map<String, dynamic>>[];
      for (final group in destinations) {
        for (final raw in (group['months'] as List? ?? const [])) {
          final month = DateTime.tryParse('${raw['month']}');
          if (month == null) continue;
          final base = <String, dynamic>{'group_id': group['id'], 'group_name': group['name'], 'month': month};
          if (widget.kind != LineBillingDirectoryKind.rates) {
            entries.add({...base, 'row_count': raw['row_count']});
            continue;
          }
          final workspace = await _repository.load('${group['id']}', 'invoice', month);
          final names = <String>{};
          for (final row in workspace['candidate_rows'] as List) {
            if (row['excluded'] == true) continue;
            final name = '${row['formal_site_name'] ?? row['site_name'] ?? ''}'.trim();
            final site = '${row['site_id'] ?? ''}'.trim();
            if (name.isEmpty || !names.add(site.isEmpty ? name : site)) continue;
            entries.add({...base, 'site_name': name, 'site_id': site,
              'confirmed': row['confirmed'] == true && site.isNotEmpty});
          }
        }
      }
      entries.sort((a,b) => widget.kind == LineBillingDirectoryKind.rates
        ? '${a['site_name']}'.compareTo('${b['site_name']}') != 0
          ? '${a['site_name']}'.compareTo('${b['site_name']}')
          : (b['month'] as DateTime).compareTo(a['month'] as DateTime)
        : (b['month'] as DateTime).compareTo(a['month'] as DateTime));
      final sites = <String>{};
      final visible = widget.kind == LineBillingDirectoryKind.rates
        ? entries.where((entry) => sites.add('${entry['group_id']}:${entry['site_id'] == '' ? entry['site_name'] : entry['site_id']}')).toList()
        : entries;
      if (mounted) setState(() { _entries.clear(); _entries.addAll(visible); });
    } catch (_) {
      if (mounted) setState(() => _error = '保存済みの取込データを確認できません。権限・接続を確認して再読み込みしてください。');
    } finally { if (mounted) setState(() => _loading = false); }
  }
  Future<void> _open(Map<String,dynamic> entry) async {
    final group = '${entry['group_id']}';
    final month = entry['month'] as DateTime;
    final Widget page;
    if (widget.kind == LineBillingDirectoryKind.monthly ||
        (widget.kind == LineBillingDirectoryKind.rates && entry['confirmed'] != true)) {
      page = LineImportPage.monthly(initialGroupId: group, initialMonth: month);
    } else if (widget.kind == LineBillingDirectoryKind.invoices) {
      page = LineHistoricalInvoicePage(initialGroupId: group, initialMonth: month);
    } else {
      page = LineHistoricalInvoicePage.rates(initialGroupId: group,
        initialMonth: month, initialSiteId: '${entry['site_id']}');
    }
    await Navigator.of(context).push<void>(MaterialPageRoute(builder: (_) => page));
    if (mounted) await _load();
  }
  Future<void> _openRules() async {
    final builder = widget.readingRulesBuilder;
    if (builder == null || _repository == null) return;
    final group = await showDialog<Map<String,dynamic>>(context: context, builder: (dialogContext) => SimpleDialog(
      title: const Text('読み取りルールを設定する履歴'), children: [
        for (final destination in _destinations) SimpleDialogOption(
          onPressed: () => Navigator.pop(dialogContext,destination), child: Text('${destination['name']}')),
      ]));
    if (group == null || !mounted) return;
    setState(() { _loading = true; _error = null; });
    try {
      final sources = <String,Map<String,dynamic>>{};
      for (final raw in group['months'] as List? ?? const []) {
        final month = DateTime.tryParse('${raw['month']}');
        if (month == null) continue;
        final workspace = await _repository.load('${group['id']}', 'invoice', month);
        for (final source in workspace['source_messages'] as List) {
          final row = Map<String,dynamic>.from(source as Map);
          sources['${row['id']}'] = row;
        }
      }
      if (!mounted) return;
      await Navigator.of(context).push<void>(MaterialPageRoute(builder: (context) => builder(context,'${group['id']}',sources.values.toList())));
    } catch (_) {
      if (mounted) setState(() => _error = '読み取りルール用の元データを取得できませんでした。');
    } finally { if (mounted) setState(() => _loading = false); }
  }
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(_title), actions: [IconButton(
      onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh))]),
    body: ListView(padding: const EdgeInsets.all(16), children: [
      if (_loading) const LinearProgressIndicator(),
      if (_error != null) Text(_error!),
      if (widget.kind == LineBillingDirectoryKind.rates && widget.readingRulesBuilder != null)
        OutlinedButton.icon(onPressed: _loading ? null : _openRules,
          icon: const Icon(Icons.tune), label: const Text('初期設定・読み取りルール')),
      if (!_loading && _error == null && _entries.isEmpty) ...[
        const Text('取り込んだデータはまだありません。元データ取込から新規ファイルを選んでください。'),
        FilledButton(onPressed: () async {
          await Navigator.of(context).push<void>(MaterialPageRoute(builder: (_) => const LineSourceUploadPage()));
          if (mounted) await _load();
        }, child: const Text('元データ取込へ')),
      ],
      for (final entry in _entries) Card(child: ListTile(
        title: Text(widget.kind == LineBillingDirectoryKind.rates ? '${entry['site_name']}'
          : '${(entry['month'] as DateTime).year}年${(entry['month'] as DateTime).month}月'),
        subtitle: Text('${entry['group_name']} ／ ${(entry['month'] as DateTime).year}年${(entry['month'] as DateTime).month}月'
          '${widget.kind == LineBillingDirectoryKind.rates && entry['confirmed'] != true ? '・月別表で現場・数量を確認' : ''}'),
        trailing: const Icon(Icons.chevron_right), onTap: () => _open(entry))),
    ]),
  );
}
