import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'daily_report_pdf_service.dart';
import 'daily_report_month_zip.dart';

import 'daily_report_month_repository.dart';

class DailyReportMonthPage extends StatefulWidget {
  const DailyReportMonthPage({super.key});
  @override
  State<DailyReportMonthPage> createState() => _DailyReportMonthPageState();
}

class _DailyReportMonthPageState extends State<DailyReportMonthPage> {
  final _repository = DailyReportMonthRepository.maybeCreate();
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  List<DailyReportMonthEntry> _entries = [];
  String? _actor, _error;
  bool _loading = true, _exporting = false;
  int _generation = 0;
  @override
  void initState() {
    super.initState();
    _actor = _repository?.client.auth.currentUser?.id;
    _load();
  }

  Future<void> _load() async {
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
      _entries = [];
    });
    try {
      final repository = _repository;
      final actor = _actor;
      if (repository == null || actor == null) {
        throw StateError('ログインを確認してください。');
      }
      repository.checkActor(actor);
      final entries = await repository.list(_month);
      repository.checkActor(actor);
      if (!mounted || generation != _generation) return;
      setState(() => _entries = entries);
    } catch (_) {
      if (!mounted || generation != _generation) return;
      setState(() => _error = '日報一覧を取得できません。ログイン状態を確認して再読み込みしてください。');
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _export() async {
    final repository = _repository;
    final actor = _actor;
    if (repository == null ||
        actor == null ||
        _loading ||
        _exporting ||
        _entries.isEmpty) {
      return;
    }
    final month = _month;
    final entries = List<DailyReportMonthEntry>.of(_entries);
    setState(() => _exporting = true);
    try {
      repository.checkActor(actor);
      final temp = await getTemporaryDirectory();
      repository.checkActor(actor);
      final directory = await temp.createTemp('sko-daily-month-');
      try {
        final zip = await DailyReportMonthZip.create(
          directory: directory,
          zipName:
              '${month.year}-${month.month.toString().padLeft(2, '0')}_日報.zip',
          entries: entries,
          checkActor: () => repository.checkActor(actor),
          build: (entry) async {
            final document = await repository.loadOne(
              entry,
              expectedActor: actor,
            );
            final report = document.report;
            return DailyReportPdfService.buildPdf(
              date: report.date,
              siteName: report.siteName,
              workers: report.workers,
              workDescription: report.workDescription,
              report: report,
              evidence: document.evidence,
            );
          },
        );
        repository.checkActor(actor);
        if (!mounted) return;
        final box = context.findRenderObject() as RenderBox?;
        await SharePlus.instance.share(
          ShareParams(
            files: [XFile(zip.path, mimeType: 'application/zip')],
            sharePositionOrigin: box == null
                ? null
                : box.localToGlobal(Offset.zero) & box.size,
          ),
        );
      } finally {
        try {
          await directory.delete(recursive: true);
        } catch (_) {}
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              '日報または保存済み写真を取得できませんでした。一部だけの保存は行いません。一覧を再読み込みしてください。',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  void _move(int offset) {
    if (_loading || _exporting) return;
    setState(() => _month = DateTime(_month.year, _month.month + offset));
    _load();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('日報一覧・月まとめ保存')),
    body: Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              onPressed: _loading || _exporting ? null : () => _move(-1),
              icon: const Icon(Icons.chevron_left),
            ),
            Text('${_month.year}年${_month.month}月'),
            IconButton(
              onPressed: _loading || _exporting ? null : () => _move(1),
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              const Text(
                'この月に閲覧できる保存済み日報と写真証跡を、日別PDFを1つのZIPにまとめます。共有画面から「ファイルに保存」も選べます。',
              ),
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: _loading || _exporting || _entries.isEmpty
                    ? null
                    : _export,
                icon: const Icon(Icons.ios_share),
                label: Text(
                  _exporting
                      ? '日報・写真を読み込み中…'
                      : 'この月をまとめて保存・共有 (${_entries.length}件)',
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_error!),
                      TextButton(onPressed: _load, child: const Text('再読み込み')),
                    ],
                  ),
                )
              : _entries.isEmpty
              ? const Center(child: Text('この月の保存済み日報はありません。'))
              : RefreshIndicator(
                  onRefresh: _exporting ? () async {} : _load,
                  child: ListView.builder(
                    itemCount: _entries.length,
                    itemBuilder: (context, index) {
                      final item = _entries[index];
                      return ListTile(
                        title: Text(item.name),
                        subtitle: Text(
                          '${DailyReportMonthRepository.dateKey(item.date)} / ${item.status == 'signed' ? '署名済み' : '保存済み'}',
                        ),
                      );
                    },
                  ),
                ),
        ),
      ],
    ),
  );
}
