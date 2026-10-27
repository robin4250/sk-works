import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import '../../international/language_controller.dart';

import 'daily_report_calendar_model.dart';
import 'daily_report_month_repository.dart';
import 'daily_report_save_badge.dart';
import 'daily_report_page.dart';

/// Resolves saved IDs independently and keeps the opening destination/status category.
class DailyReportSavedPreviewPager extends StatefulWidget {
  const DailyReportSavedPreviewPager({super.key, required this.repository,
    required this.actor, required this.entries, required this.initialEntryId,
    this.workerId, this.initialEntryIsVisit, this.allPeriodNavigation = false,
    this.previewBuilderForTesting, this.editBuilderForTesting,
    this.previewWithZoomBuilderForTesting});
  final DailyReportMonthRepository repository;
  final String actor;
  final List<DailyReportMonthEntry> entries;
  final String initialEntryId;
  final String? workerId;
  final bool? initialEntryIsVisit;
  final bool allPeriodNavigation;
  final Widget Function(DailyReportMonthDocument)? previewBuilderForTesting;
  final Widget Function(DailyReportMonthEntry)? editBuilderForTesting;
  @visibleForTesting
  final Widget Function(DailyReportMonthDocument, ValueChanged<bool>)? previewWithZoomBuilderForTesting;
  @override
  State<DailyReportSavedPreviewPager> createState() => _DailyReportSavedPreviewPagerState();
}

class _DailyReportSavedPreviewPagerState extends State<DailyReportSavedPreviewPager> {
  late final DailyReportMonthEntry? _anchor = widget.entries.where((e) => e.id == widget.initialEntryId && (widget.initialEntryIsVisit == null || e.isVisit == widget.initialEntryIsVisit)).firstOrNull;
  late final _category = _anchor?.saveState;
  late final String? _destination = switch (_anchor) { final value? => dailyReportDestinationKey(value), null => null };
  late List<DailyReportMonthEntry> _entries = chronologicalDailyReports(widget.entries.where((e) =>
    e.saveState == _category && dailyReportDestinationKey(e) == _destination));
  late int _index = _entries.indexWhere((entry) => entry.id == widget.initialEntryId && entry.isVisit == _anchor?.isVisit);
  DailyReportMonthDocument? _document;
  String? _error, _historyWarning;
  bool _loading = true;
  late bool _historyComplete = !widget.allPeriodNavigation;
  int _generation = 0, _historyGeneration = 0;
  bool _zoomed = false;
  double _horizontalDistance = 0;

  @override
  void initState() {
    super.initState();
    if (widget.allPeriodNavigation) { _loadHistory(); } else { _load(); }
  }

  Future<void> _loadHistory() async {
    final generation = ++_historyGeneration;
    final selectedId = _index >= 0 && _index < _entries.length ? '${_entries[_index].isVisit}:${_entries[_index].id}' : '${_anchor?.isVisit}:${widget.initialEntryId}';
    setState(() { _loading = true; _historyWarning = null; });
    try {
      final anchor = _anchor;
      if (anchor == null) throw StateError('Missing report');
      widget.repository.checkActor(widget.actor);
      final result = await widget.repository.listSiteHistory(anchor, workerId: widget.workerId);
      widget.repository.checkActor(widget.actor);
      if (!mounted || generation != _historyGeneration) return;
      if (result.entries.any((e) => e.saveState != _category || dailyReportDestinationKey(e) != _destination)) {
        throw StateError('History binding changed');
      }
      final seen = <String>{};
      final entries = result.entries.toList();
      for (final entry in entries) {
        if (!seen.add('${entry.isVisit}:${entry.id}')) throw StateError('Duplicate history');
      }
      if (!result.complete) {
        for (final entry in _entries) {
          if (seen.add('${entry.isVisit}:${entry.id}')) entries.add(entry);
        }
      }
      setState(() {
        _entries = chronologicalDailyReports(entries);
        _index = _entries.indexWhere((e) => '${e.isVisit}:${e.id}' == selectedId);
        _historyComplete = result.complete;
        _historyWarning = result.warning;
      });
      if (_index < 0) {
        setState(() { _document = null; _error = '保存状態が変わりました。一覧へ戻って再読み込みしてください。'; _loading = false; });
        return;
      }
    } catch (_) {
      if (!mounted || generation != _historyGeneration) return;
      setState(() {
        _historyComplete = false;
        _historyWarning = '全期間を取得できません。前後の日報の範囲は未確認です。';
      });
    }
    if (mounted && generation == _historyGeneration) await _load();
  }

  Future<void> _load() async {
    final generation = ++_generation;
    setState(() { _loading = true; _error = null; _document = null; _zoomed = false; _horizontalDistance = 0; });
    try {
      if (_index < 0 || _index >= _entries.length) throw StateError('Missing report');
      final selected = _entries[_index];
      final document = await widget.repository.loadOne(selected, expectedActor: widget.actor);
      widget.repository.checkActor(widget.actor);
      if (!mounted || generation != _generation) return;
      final report = document.report;
      final actual = DailyReportMonthEntry(id: report.id, date: report.date, name: report.siteName, status: report.status,
        reporterSigned: report.reporterSignatureJson != null,
        supervisorSigned: report.responsibleSignatureJson != null || report.signatureJson != null);
      if (report.id != selected.id || actual.saveState != _category) {
        setState(() => _error = '保存状態が変わりました。一覧へ戻って再読み込みしてください。');
      } else {
        setState(() => _document = document);
      }
    } catch (_) {
      if (!mounted || generation != _generation) return;
      setState(() => _error = '選んだ日報を取得できませんでした。一覧を再読み込みしてください。');
    } finally {
      if (mounted && generation == _generation) setState(() => _loading = false);
    }
  }

  void _select(int index) {
    if (_loading || index < 0 || index >= _entries.length) return;
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
      if (mounted) {
        if (widget.allPeriodNavigation) { await _loadHistory(); } else { await _load(); }
      }
    } catch (_) {
      if (mounted) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(SkoLanguageController.tr('日報を編集できませんでした。ログイン状態を確認してください。')))); }
    }
  }

  void _zoomChanged(bool zoomed) {
    if (!mounted || _zoomed == zoomed) return;
    if (SchedulerBinding.instance.schedulerPhase == SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _zoomChanged(zoomed));
      return;
    }
    setState(() { _zoomed = zoomed; _horizontalDistance = 0; });
  }

  @override
  Widget build(BuildContext context) {
    SkoLanguageController.watch(context);
    final entry = _index >= 0 && _index < _entries.length ? _entries[_index] : null;
    final document = _document;
    final category = _category;
    Widget preview;
    if (_loading) {
      preview = const Scaffold(body: Center(child: CircularProgressIndicator()));
    } else if (_error != null || document == null) {
      preview = Scaffold(appBar: AppBar(title: Text(SkoLanguageController.tr('日報プレビュー'))),
        body: Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(SkoLanguageController.tr(_error ?? '日報を取得できませんでした。')),
          TextButton(onPressed: widget.allPeriodNavigation ? _loadHistory : _load, child: Text(SkoLanguageController.tr('再読み込み'))),
        ]))));
    } else {
      final report = document.report;
      preview = widget.previewWithZoomBuilderForTesting?.call(document, _zoomChanged) ??
        widget.previewBuilderForTesting?.call(document) ?? DailyReportPrintPreviewPage(
          key: ValueKey(report.id), date: report.date, siteName: report.siteName,
          workers: report.workers, workDescription: report.workDescription, report: report,
          evidence: document.evidence.map((photo) => photo.record).toList(),
          resolvedEvidence: document.evidence, onEdit: _edit, onZoomChanged: _zoomChanged);
    }
    Widget arrow({required bool newer}) {
      final nextIndex = _index + (newer ? 1 : -1);
      final available = entry != null && nextIndex >= 0 && nextIndex < _entries.length;
      return Tooltip(message: newer ? '新しい日報へ（右スライド）' : '古い日報へ（左スライド）', child: OutlinedButton(
        key: ValueKey(newer ? 'daily-report-next' : 'daily-report-previous'),
        style: OutlinedButton.styleFrom(minimumSize: const Size(64, 64), padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6)),
        onPressed: _loading || !available ? null : () => _select(nextIndex),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(newer ? Icons.chevron_right : Icons.chevron_left, size: 36),
          Text(newer ? '新しい' : '古い', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
        ])));
    }
    return GestureDetector(key: const ValueKey('daily-report-preview-swipe'),
      onHorizontalDragStart: _zoomed ? null : (_) => _horizontalDistance = 0,
      onHorizontalDragUpdate: _zoomed ? null : (details) => _horizontalDistance += details.delta.dx,
      onHorizontalDragCancel: _zoomed ? null : () => _horizontalDistance = 0,
      onHorizontalDragEnd: _zoomed ? null : (details) {
        final velocity = details.primaryVelocity ?? 0;
        final direction = _horizontalDistance.abs() >= 40 ? _horizontalDistance : velocity.abs() > 200 ? velocity : 0.0;
        _horizontalDistance = 0;
        if (direction > 0) { _select(_index + 1); }
        if (direction < 0) { _select(_index - 1); }
      },
      child: Column(children: [Expanded(child: preview),
        Material(color: Theme.of(context).colorScheme.surface, child: SafeArea(top: false, child: Padding(
          padding: const EdgeInsets.all(8), child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (_historyWarning != null) Row(children: [Expanded(child: Text(_historyWarning!,
              style: TextStyle(color: Theme.of(context).colorScheme.error))),
              TextButton(onPressed: _loading ? null : _loadHistory, child: const Text('再取得'))]),
            if (entry != null) Text(entry.name, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
            Row(children: [arrow(newer: false), Expanded(child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(entry == null ? '' : '${entry.date.year}年', style: const TextStyle(fontSize: 16)),
              Text(entry == null ? '' : '${entry.date.month}月${entry.date.day}日', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
              Text(entry == null ? '' : '${_index + 1} / ${_entries.length}件${_historyComplete ? '' : '（取得済み）'}',
                style: const TextStyle(fontSize: 13)),
              if (category != null) DailyReportSaveBadge(state: category),
            ])), arrow(newer: true)]),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text(_index == 0 ? _historyComplete ? '最も古い日報' : '範囲未確認' : ''),
              Text(entry != null && _index == _entries.length - 1 ? _historyComplete ? '最も新しい日報' : '範囲未確認' : ''),
            ]),
          ]))))]));
  }
}
