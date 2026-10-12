import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'daily_report_pdf_service.dart';
import 'daily_report_month_zip.dart';

import 'daily_report_month_repository.dart';
import 'daily_report_page.dart';

class DailyReportMonthPage extends StatefulWidget {
  const DailyReportMonthPage({super.key, this.initialMonth, this.initialDate, this.workerId,
    @visibleForTesting this.repositoryForTesting,
    @visibleForTesting this.previewBuilderForTesting,
  });
  final DateTime? initialMonth;
  final DateTime? initialDate;
  final String? workerId;
  final DailyReportMonthRepository? repositoryForTesting;
  final Widget Function(DailyReportMonthDocument)? previewBuilderForTesting;
  @override
  State<DailyReportMonthPage> createState() => _DailyReportMonthPageState();
}

class _DailyReportMonthPageState extends State<DailyReportMonthPage> {
  late final _repository = widget.repositoryForTesting ?? DailyReportMonthRepository.maybeCreate();
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  List<DailyReportMonthEntry> _entries = [];
  String? _actor, _error;
  DateTime? _selectedDate;
  String? _openingEntryId;
  bool _loading = true, _exporting = false;
  int _generation = 0;
  @override
  void initState() {
    super.initState();
    final initial = widget.initialDate ?? widget.initialMonth ?? DateTime.now();
    _month = DateTime(initial.year, initial.month);
    _selectedDate = widget.initialDate == null ? null : DateTime(initial.year, initial.month, initial.day);
    try {
      _actor = _repository?.actor;
    } catch (_) {
      _actor = null;
    }
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
      final allEntries = await repository.list(_month, workerId: widget.workerId);
      final selectedDate = _selectedDate;
      final entries = selectedDate == null ? allEntries : allEntries.where((entry) =>
        entry.date.year == selectedDate.year && entry.date.month == selectedDate.month &&
        entry.date.day == selectedDate.day).toList();
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
        _openingEntryId != null ||
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
          zipName: _selectedDate == null
              ? '${month.year}-${month.month.toString().padLeft(2, '0')}_日報.zip'
              : '${DailyReportMonthRepository.dateKey(_selectedDate!)}_日報.zip',
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
    if (_loading || _exporting || _openingEntryId != null) return;
    setState(() {
      if (_selectedDate != null) {
        _selectedDate = DateTime(_selectedDate!.year, _selectedDate!.month, _selectedDate!.day + offset);
        _month = DateTime(_selectedDate!.year, _selectedDate!.month);
      } else {
        _month = DateTime(_month.year, _month.month + offset);
      }
    });
    _load();
  }

  Future<void> _openEntry(DailyReportMonthEntry entry) async {
    final repository = _repository;
    final actor = _actor;
    if (repository == null || actor == null || _loading || _exporting || _openingEntryId != null) return;
    setState(() => _openingEntryId = entry.id);
    try {
      final document = await repository.loadOne(entry, expectedActor: actor);
      repository.checkActor(actor);
      if (!mounted) return;
      final report = document.report;
      await Navigator.of(context).push<void>(MaterialPageRoute(builder: (_) =>
        widget.previewBuilderForTesting?.call(document) ?? DailyReportPrintPreviewPage(
          date: report.date, siteName: report.siteName, workers: report.workers,
          workDescription: report.workDescription, report: report,
          evidence: document.evidence.map((photo) => photo.record).toList(),
          resolvedEvidence: document.evidence,
        )));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('選んだ日報を取得できませんでした。一覧を再読み込みしてください。'),
        ));
      }
    } finally {
      if (mounted) {
        setState(() => _openingEntryId = null);
      }
    }
  }

  void _help() => showDialog<void>(context: context, builder: (context) => AlertDialog(
    title: const Text('日報一覧の使い方'),
    content: const Text('訪問先ごとの日報と、退勤時のルート日報を別々に表示します。日報を選ぶと、保存済みの内容とサインでプレビューを開きます。下の印刷ボタンで1件ずつ印刷でき、共有ボタンから「ファイルに保存」を選べます。まとめて保存はZIP形式です。'),
    actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('閉じる'))],
  ));

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('日報一覧・保存'), actions: [
      IconButton(tooltip: '日報一覧のヘルプ', onPressed: _help, icon: const Icon(Icons.help_outline)),
    ]),
    body: Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              onPressed: _loading || _exporting ? null : () => _move(-1),
              icon: const Icon(Icons.chevron_left),
            ),
            Expanded(child: FittedBox(fit: BoxFit.scaleDown, child: Text(_selectedDate == null
                ? '${_month.year}年${_month.month}月'
                : DailyReportMonthRepository.dateKey(_selectedDate!)))),
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
                      : '${_selectedDate == null ? 'この月' : 'この日'}をまとめて保存・共有 (${_entries.length}件)',
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
                        onTap: _exporting || _openingEntryId != null ? null : () => _openEntry(item),
                        subtitle: Text(
                          '${DailyReportMonthRepository.dateKey(item.date)} / ${item.kindLabel} / ${const ['signed', 'completed'].contains(item.status) ? '署名済み' : '保存済み'}',
                        ),
                        trailing: _openingEntryId == item.id
                            ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                            : IconButton(tooltip: '表示・印刷・保存', icon: const Icon(Icons.picture_as_pdf_outlined),
                                onPressed: _exporting || _openingEntryId != null ? null : () => _openEntry(item)),
                      );
                    },
                  ),
                ),
        ),
      ],
    ),
  );
}
