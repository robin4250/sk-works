import 'package:flutter/material.dart';
import '../../international/language_controller.dart';

import 'daily_report_calendar_model.dart';
import 'daily_report_month_repository.dart';
import 'daily_report_page.dart';

/// Resolves each saved ID separately; an old response never replaces a later selection.
class DailyReportSavedPreviewPager extends StatefulWidget {
  const DailyReportSavedPreviewPager({super.key, required this.repository,
    required this.actor, required this.entries, required this.initialEntryId,
    this.previewBuilderForTesting, this.editBuilderForTesting});
  final DailyReportMonthRepository repository;
  final String actor;
  final List<DailyReportMonthEntry> entries;
  final String initialEntryId;
  final Widget Function(DailyReportMonthDocument)? previewBuilderForTesting;
  final Widget Function(DailyReportMonthEntry)? editBuilderForTesting;

  @override
  State<DailyReportSavedPreviewPager> createState() => _DailyReportSavedPreviewPagerState();
}

class _DailyReportSavedPreviewPagerState extends State<DailyReportSavedPreviewPager> {
  late final _entries = chronologicalDailyReports(widget.entries);
  late int _index = _entries.indexWhere((entry) => entry.id == widget.initialEntryId);
  DailyReportMonthDocument? _document;
  String? _error;
  bool _loading = true;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final generation = ++_generation;
    setState(() { _loading = true; _error = null; _document = null; });
    try {
      if (_index < 0 || _index >= _entries.length) throw StateError('Missing report');
      final document = await widget.repository.loadOne(_entries[_index], expectedActor: widget.actor);
      widget.repository.checkActor(widget.actor);
      if (!mounted || generation != _generation) return;
      setState(() => _document = document);
    } catch (_) {
      if (!mounted || generation != _generation) return;
      setState(() => _error = '選んだ日報を取得できませんでした。一覧を再読み込みしてください。');
    } finally {
      if (mounted && generation == _generation) setState(() => _loading = false);
    }
  }

  void _select(int? index) {
    if (_loading || index == null || index < 0 || index >= _entries.length) return;
    setState(() => _index = index);
    _load();
  }

  Future<void> _edit() async {
    if (_loading || _document == null) return;
    final entry = _entries[_index];
    try {
      widget.repository.checkActor(widget.actor);
      await Navigator.of(context).push<void>(MaterialPageRoute(builder: (_) =>
        widget.editBuilderForTesting?.call(entry) ?? DailyReportPage(
          initialDate: entry.date, initialSiteId: entry.siteId,
          initialRouteAssignmentId: entry.routeId, initialReportId: entry.id,
          routeVisitContext: entry.visitContext)));
      widget.repository.checkActor(widget.actor);
      if (mounted) await _load();
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(SkoLanguageController.tr('日報を編集できませんでした。ログイン状態を確認してください。'))));
    }
  }

  @override
  Widget build(BuildContext context) {
    SkoLanguageController.watch(context);
    final entry = _index >= 0 && _index < _entries.length ? _entries[_index] : null;
    final next = nextDailyReportDay(_entries, _index);
    final document = _document;
    Widget preview;
    if (_loading) {
      preview = const Scaffold(body: Center(child: CircularProgressIndicator()));
    } else if (_error != null || document == null) {
      preview = Scaffold(appBar: AppBar(title: Text(SkoLanguageController.tr('日報プレビュー'))),
        body: Center(child: Padding(padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(SkoLanguageController.tr(_error ?? '日報を取得できませんでした。')),
            TextButton(onPressed: _load, child: Text(SkoLanguageController.tr('再読み込み'))),
          ]))));
    } else {
      final report = document.report;
      preview = widget.previewBuilderForTesting?.call(document) ?? DailyReportPrintPreviewPage(
        key: ValueKey(report.id), date: report.date, siteName: report.siteName,
        workers: report.workers, workDescription: report.workDescription, report: report,
        evidence: document.evidence.map((photo) => photo.record).toList(),
        resolvedEvidence: document.evidence, onEdit: _edit);
    }
    return GestureDetector(
      key: const ValueKey('daily-report-preview-swipe'),
      onHorizontalDragEnd: (details) {
        final velocity = details.primaryVelocity ?? 0;
        if (velocity > 200) _select(next); // User-requested right swipe: next report day.
        if (velocity < -200) _select(_index - 1); // Left swipe: previous older record.
      },
      child: Column(children: [
        Expanded(child: preview),
        Material(color: Theme.of(context).colorScheme.surface,
          child: SafeArea(top: false, child: Padding(padding: const EdgeInsets.all(8),
            child: Row(children: [
              IconButton(tooltip: SkoLanguageController.tr('古い日報へ（左スライド）'),
                onPressed: _loading || _index <= 0 ? null : () => _select(_index - 1),
                icon: const Icon(Icons.chevron_left)),
              Expanded(child: Text(entry == null ? '' :
                '${DailyReportMonthRepository.dateKey(entry.date)}\n${entry.name}',
                textAlign: TextAlign.center, maxLines: 3,
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold))),
              IconButton(tooltip: SkoLanguageController.tr('次の日へ（右スライド）'),
                onPressed: _loading || next == null ? null : () => _select(next),
                icon: const Icon(Icons.chevron_right)),
            ])))),
      ]),
    );
  }
}
