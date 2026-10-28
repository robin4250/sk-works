import 'package:flutter/material.dart';
import '../../international/language_controller.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'daily_report_pdf_service.dart';
import 'daily_report_month_zip.dart';

import 'daily_report_month_repository.dart';
import 'daily_report_save_badge.dart';
export 'daily_report_save_badge.dart';
import 'daily_report_page.dart';
import 'daily_report_calendar_model.dart';
import 'daily_report_saved_preview_pager.dart';
import '../route_billing/route_customer_day_quantity_page.dart';
import '../attendance/japan_holiday.dart';
import '../attendance/checkout_report_new_action.dart';

class DailyReportMonthPage extends StatefulWidget {
  const DailyReportMonthPage({super.key, this.initialMonth, this.initialDate, this.workerId,
    @visibleForTesting this.repositoryForTesting,
    @visibleForTesting this.previewBuilderForTesting,
    @visibleForTesting this.quantityBuilderForTesting,
    @visibleForTesting this.pendingBuilderForTesting,
  });
  final DateTime? initialMonth;
  final DateTime? initialDate;
  final String? workerId;
  final DailyReportMonthRepository? repositoryForTesting;
  final Widget Function(DailyReportMonthDocument)? previewBuilderForTesting;
  @visibleForTesting
  final Widget Function(String workerId, DateTime date)? quantityBuilderForTesting;
  final Widget Function(DailyReportMonthEntry)? pendingBuilderForTesting;
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
  bool _loading = true, _exporting = false, _creating = false;
  int _generation = 0;
  bool _showPending = false, _showUnfinished = false, _pendingLoading = false;
  int _pendingGeneration = 0;
  List<DailyReportMonthEntry> _pending = [];
  String? _pendingError, _pendingWarning;
  String? _siteKey, _siteName;
  final Map<String, Future<bool>> _photoPresence = {};
  final Map<String, Future<List<(DailyReportMonthEntry, bool)>>> _dayPresence = {};
  List<DailyReportMonthEntry> get _normalEntries => _entries.where((entry) => _showUnfinished
      ? const [DailyReportSaveState.inputPending, DailyReportSaveState.finalizationPending].contains(entry.saveState)
      : entry.saveState == DailyReportSaveState.saved).toList();
  List<DailyReportMonthEntry> get _visibleEntries => _siteKey == null ? _normalEntries :
      _normalEntries.where((entry) => dailyReportDestinationKey(entry) == _siteKey).toList();
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
      _photoPresence.clear();
      _dayPresence.clear();
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
      setState(() => _entries = selectedDate == null ? chronologicalDailyReports(entries) : entries);
    } catch (_) {
      if (!mounted || generation != _generation) return;
      setState(() => _error = '日報一覧を取得できません。ログイン状態を確認して再読み込みしてください。');
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _loadPending() async {
    final generation = ++_pendingGeneration;
    setState(() { _pendingLoading = true; _pendingError = null; _pendingWarning = null; _pending = []; });
    try {
      final repository = _repository, actor = _actor;
      if (repository == null || actor == null) throw StateError('ログインを確認してください。');
      repository.checkActor(actor);
      final result = await repository.listPending(workerId: widget.workerId);
      repository.checkActor(actor);
      if (!mounted || generation != _pendingGeneration) return;
      setState(() { _pending = result.entries; _pendingWarning = result.visitWarning; });
    } catch (_) {
      if (mounted && generation == _pendingGeneration) setState(() => _pendingError = 'サイン待ちの日報を取得できません。再読み込みしてください。');
    } finally {
      if (mounted && generation == _pendingGeneration) setState(() => _pendingLoading = false);
    }
  }

  Widget _listingControls() => Padding(padding: const EdgeInsets.fromLTRB(12, 8, 12, 4), child: Row(
    children: [
      Expanded(child: ChoiceChip(showCheckmark: false,
        label: const FittedBox(fit: BoxFit.scaleDown, child: Text('保存済', maxLines: 1)),
        selectedColor: Colors.green.shade100,
        labelStyle: TextStyle(color: Colors.green.shade900, fontWeight: FontWeight.bold),
        side: BorderSide(color: Colors.green.shade800), selected: !_showPending && !_showUnfinished,
        onSelected: _exporting || _openingEntryId != null ? null : (_) => setState(() { _showPending = false; _showUnfinished = false; _siteKey = null; _siteName = null; }))),
      const SizedBox(width: 6),
      Expanded(child: ChoiceChip(showCheckmark: false, key: const ValueKey('daily-report-pending-filter'),
        label: const FittedBox(fit: BoxFit.scaleDown, child: Text('サイン待ち', maxLines: 1)),
        selected: _showPending, selectedColor: Colors.red.shade100,
        labelStyle: TextStyle(color: Colors.red.shade900, fontWeight: FontWeight.bold),
        side: BorderSide(color: Colors.red.shade700),
        onSelected: _exporting || _openingEntryId != null ? null : (_) {
          setState(() { _showPending = true; _showUnfinished = false; _siteKey = null; _siteName = null; }); _loadPending();
        })),
      const SizedBox(width: 6),
      Expanded(child: ChoiceChip(showCheckmark: false,
        label: const FittedBox(fit: BoxFit.scaleDown, child: Text('入力待ち', maxLines: 1)), selected: _showUnfinished,
        onSelected: _exporting || _openingEntryId != null ? null : (_) => setState(() {
          _showPending = false; _showUnfinished = true; _siteKey = null; _siteName = null;
        }))),
    ]));

  Widget _withPendingControls(Widget normal) => Column(children: [
    _listingControls(), Expanded(child: _showPending ? _pendingBody() : normal),
  ]);

  Widget _pendingBody() {
    if (_pendingLoading) return const Center(child: CircularProgressIndicator());
    if (_pendingError != null) { return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
      Padding(padding: const EdgeInsets.all(16), child: Text(_pendingError!)),
      TextButton(onPressed: _loadPending, child: const Text('再読み込み')),
    ])); }
    final sites = <String, List<DailyReportMonthEntry>>{};
    for (final entry in _pending) {
      if (entry.saveState != DailyReportSaveState.supervisorPending) continue;
      sites.putIfAbsent(dailyReportDestinationKey(entry), () => []).add(entry);
    }
    return RefreshIndicator(onRefresh: _loadPending, child: ListView(
      physics: const AlwaysScrollableScrollPhysics(), padding: const EdgeInsets.all(12), children: [
        Text('責任者サイン待ち ${_pending.length}件', key: const ValueKey('daily-report-pending-heading'),
          style: TextStyle(color: Colors.red.shade900, fontWeight: FontWeight.bold, fontSize: 20)),
        const Text('すべての月・現場別'),
        if (_pendingWarning != null) Card(color: Colors.amber.shade50, child: Padding(
          padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_pendingWarning!), TextButton(onPressed: _loadPending, child: const Text('再読み込み')),
          ]))),
        if (_pending.isEmpty && _pendingWarning == null) const Padding(padding: EdgeInsets.all(24), child: Text('責任者サイン待ちの日報はありません。')),
        for (final group in sites.entries) Card(child: ExpansionTile(
          key: ValueKey('daily-report-pending-site-${group.key}'), initiallyExpanded: true,
          title: Text(group.value.first.name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          subtitle: Text('サイン待ち ${group.value.length}件', style: TextStyle(color: Colors.red.shade900)),
          children: [for (final entry in group.value) ListTile(
            key: ValueKey('daily-report-pending-entry-${entry.id}'),
            title: Text('${DailyReportMonthRepository.dateKey(entry.date)}・${entry.kindLabel}'),
            subtitle: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (entry.createdAt != null) Text(_createdTime(entry.createdAt!)),
              DailyReportSaveBadge(state: entry.saveState),
            ]),
            trailing: OutlinedButton(onPressed: _openingEntryId != null || _exporting ? null : () => _openPendingEntry(entry),
              child: const Text('サイン')),
            onTap: _openingEntryId != null || _exporting ? null : () => _openReportPager(entry, _pending),
          )],
        )),
      ]));
  }

  Future<void> _openPendingEntry(DailyReportMonthEntry entry) async {
    final repository = _repository, actor = _actor;
    if (repository == null || actor == null || _openingEntryId != null || _pendingLoading || _exporting) return;
    setState(() => _openingEntryId = entry.id);
    try {
      repository.checkActor(actor);
      await Navigator.of(context).push<void>(MaterialPageRoute(builder: (_) =>
        widget.pendingBuilderForTesting?.call(entry) ?? DailyReportPage(initialDate: entry.date,
          initialSiteId: entry.siteId, initialRouteAssignmentId: entry.routeId,
          initialReportId: entry.id, routeVisitContext: entry.visitContext)));
      repository.checkActor(actor);
      if (mounted) { await _loadPending(); await _load(); }
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('日報を開けませんでした。再読み込みしてください。')));
    } finally { if (mounted) setState(() => _openingEntryId = null); }
  }

  Future<void> _export() async {
    final repository = _repository;
    final actor = _actor;
    if (repository == null ||
        actor == null ||
        _loading ||
        _exporting ||
        _openingEntryId != null ||
        _visibleEntries.isEmpty) {
      return;
    }
    final month = _month;
    final entries = List<DailyReportMonthEntry>.of(_visibleEntries);
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
          SnackBar(
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

  Future<void> _openEntry(DailyReportMonthEntry entry) => _openCalendarEntry(entry);

  Future<void> _openQuantities() async {
    final repository = _repository, actor = _actor;
    final workerId = widget.workerId, date = _selectedDate;
    if (repository == null || actor == null || workerId == null || date == null) return;
    try {
      repository.checkActor(actor);
      await Navigator.of(context).push<bool>(MaterialPageRoute<bool>(builder: (_) =>
        widget.quantityBuilderForTesting?.call(workerId, date) ??
        RouteCustomerDayQuantityPage(workerId: workerId, workDate: date)));
      repository.checkActor(actor);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(SkoLanguageController.tr('請求数量を開けませんでした。ログインを確認して再読み込みしてください。'))));
      }
    }
  }

  void _help() => showDialog<void>(context: context, builder: (context) => AlertDialog(
    title: Text(SkoLanguageController.tr('日報一覧の使い方')),
    content: SingleChildScrollView(child: Text(SkoLanguageController.tr('現場を選ぶと、上下にスクロールする月の日付一覧を開きます。日付・曜日は土曜日が青文字、日曜日と日本の祝日が赤文字です。祝日が土曜日と重なる場合は赤文字を優先します。◀・▶で月を切り替え、ヘッダーの「月まとめて共有・保存」で全現場または開いている現場の保存済み日報をZIPにまとめます。日報は面表紙のある帳票を1件と数え、添付写真の枚数は含みません。「写真無し」「写真付き」は日報の区分です。同じ日に複数の日報があれば古い順に選べます。プレビューは通常表示で右スライドすると次の日報登録日、左スライドすると古い日報へ進み、矢印でも切り替えできます。ダブルタップで帳票を拡大中は横移動で帳票内を確認します。再度ダブルタップで通常表示へ戻すと日報をスライド切替できます。拡大中も下の矢印で日報を変更できます。「編集」から選択した日報を開きます。署名済み日報の変更制限はそのままです。「＋」で新規日報を作成します。訪問先ごとの日報と、退勤時のルート日報を別々に表示します。日報を選ぶと、保存済みの内容とサインでプレビューを開きます。下の印刷ボタンで1件ずつ印刷でき、共有ボタンから「ファイルに保存」を選べます。同じ日に同じ現場の日報が複数ある場合は件目の番号で区別できます。作成時刻は日本時間です。まとめて保存はZIP形式です。ルートの日別一覧では「請求数量を申請」から、退勤済みの訪問日報を取引会社ごとにまとめて数量を申請できます。管理者の承認後に請求書の下書きへ反映し、給与や出勤表の人工は変更しません。'))),
    actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text(SkoLanguageController.tr('閉じる')))],
  ));

  Future<void> _newReport() async {
    if (_creating) return;
    setState(() => _creating = true);
    try {
      final handled = await offerNewCheckoutReport(context, month: _month, workerId: widget.workerId);
      if (!mounted) return;
      if (!handled) {
        await Navigator.of(context).push<void>(MaterialPageRoute(builder: (_) => DailyReportPage(
          initialDate: DateTime(_month.year, _month.month, DateTime.now().day.clamp(1,
            DateTime(_month.year, _month.month + 1, 0).day).toInt()),
        )));
      }
      if (mounted) await _load();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('勤務原本と日報作成の状態を確認できません。再読み込みしてください。')));
      }
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  Future<void> _openCalendarEntry(DailyReportMonthEntry entry) => _openReportPager(entry, _visibleEntries);

  Future<void> _openReportPager(DailyReportMonthEntry entry, List<DailyReportMonthEntry> source) async {
    final repository = _repository, actor = _actor;
    if (repository == null || actor == null || _loading || _exporting || _openingEntryId != null) return;
    final entries = List<DailyReportMonthEntry>.of(source);
    setState(() => _openingEntryId = entry.id);
    try {
      repository.checkActor(actor);
      await Navigator.of(context).push<void>(MaterialPageRoute(builder: (_) =>
        DailyReportSavedPreviewPager(repository: repository, actor: actor,
          entries: entries, initialEntryId: entry.id, initialEntryIsVisit: entry.isVisit,
          allPeriodNavigation: true, workerId: widget.workerId,
          previewBuilderForTesting: widget.previewBuilderForTesting,
          editBuilderForTesting: widget.pendingBuilderForTesting)));
      repository.checkActor(actor);
      if (mounted) {
        if (_showPending) await _loadPending();
        await _load();
      }
    } catch (_) {
      if (mounted) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(SkoLanguageController.tr('選んだ日報を取得できませんでした。一覧を再読み込みしてください。')))); }
    } finally {
      if (mounted && _openingEntryId == entry.id) setState(() => _openingEntryId = null);
    }
  }

  Future<List<(DailyReportMonthEntry, bool)>> _classify(List<DailyReportMonthEntry> entries) async {
    final repository = _repository, actor = _actor;
    if (repository == null || actor == null) throw StateError('Report unavailable');
    final classified = <(DailyReportMonthEntry, bool)>[];
    for (final entry in entries) {
      final future = _photoPresence.putIfAbsent(entry.id,
        () => repository.hasPhotos(entry, expectedActor: actor));
      classified.add((entry, await future));
    }
    repository.checkActor(actor);
    return classified;
  }

  Widget _monthBuild(BuildContext context) {
    final busy = _loading || _exporting || _creating;
    final destinations = <String, List<DailyReportMonthEntry>>{};
    for (final entry in _normalEntries) {
      destinations.putIfAbsent(dailyReportDestinationKey(entry), () => []).add(entry);
    }
    final visible = _visibleEntries;
    final byDate = <String, List<DailyReportMonthEntry>>{};
    for (final entry in visible) {
      byDate.putIfAbsent(DailyReportMonthRepository.dateKey(entry.date), () => []).add(entry);
    }
    return PopScope<void>(canPop: _siteKey == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !busy) setState(() { _siteKey = null; _siteName = null; });
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_showPending ? 'サイン待ち' : _siteName ?? SkoLanguageController.tr('日報'), maxLines: 1, overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
          leading: _siteKey == null ? null : IconButton(tooltip: SkoLanguageController.tr('現場一覧へ'),
            onPressed: busy ? null : () => setState(() { _siteKey = null; _siteName = null; }),
            icon: const Icon(Icons.arrow_back)),
          actions: [
            IconButton(tooltip: SkoLanguageController.tr('新規日報'), onPressed: busy ? null : _newReport,
              icon: const Icon(Icons.add)),
            IconButton(tooltip: SkoLanguageController.tr('日報一覧のヘルプ'), onPressed: _help,
              icon: const Icon(Icons.help_outline)),
          ],
          bottom: PreferredSize(preferredSize: Size.fromHeight(_showPending ? 48 : 114 + (MediaQuery.textScalerOf(context).scale(17) - 17).clamp(0, 40).toDouble() * 3),
            child: Padding(padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
              child: Column(children: [
                if (_showPending) const Padding(padding: EdgeInsets.all(10), child: Text('すべての月のサイン待ちを表示'))
                else ...[
                Row(children: [
                  IconButton(tooltip: SkoLanguageController.tr('前の月'), onPressed: busy ? null : () => _move(-1),
                    icon: const Icon(Icons.chevron_left)),
                  Expanded(child: Text(SkoLanguageController.trParams('{year}年{month}月', {'year': _month.year, 'month': _month.month}), textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold))),
                  IconButton(tooltip: SkoLanguageController.tr('次の月'), onPressed: busy ? null : () => _move(1),
                    icon: const Icon(Icons.chevron_right)),
                ]),
                SizedBox(width: double.infinity, child: FilledButton.icon(
                  key: const ValueKey('daily-report-month-share'),
                  onPressed: busy || visible.isEmpty ? null : _export,
                  icon: const Icon(Icons.ios_share),
                  label: Text(SkoLanguageController.tr(_exporting ? '日報・写真を読み込み中…' : '月まとめて共有・保存'), maxLines: 2,
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)))),
              ],
              ]))),
        ),
        body: _withPendingControls(_loading ? const Center(child: CircularProgressIndicator()) : _error != null
          ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(
              mainAxisSize: MainAxisSize.min, children: [Text(SkoLanguageController.tr(_error!)),
                TextButton(onPressed: _load, child: Text(SkoLanguageController.tr('再読み込み')))])))
          : RefreshIndicator(onRefresh: _exporting ? () async {} : _load,
            child: _siteKey == null ? ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(12), children: [
                if (destinations.isEmpty) Padding(padding: const EdgeInsets.all(24),
                  child: Text(SkoLanguageController.tr('この月の保存済み日報はありません。'), style: TextStyle(fontSize: 18))),
                for (final destination in destinations.entries) Card(child: ListTile(
                  key: ValueKey('daily-report-site-${destination.key}'),
                  title: Text(destination.value.first.name,
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  subtitle: Wrap(spacing: 6, runSpacing: 4, children: [
                    Text('日報 ${destination.value.length}件'),
                    for (final state in DailyReportSaveState.values)
                      if (destination.value.any((entry) => entry.saveState == state))
                        DailyReportSaveBadge(state: state, count: destination.value.where((entry) => entry.saveState == state).length),
                  ]),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _exporting ? null : () => setState(() {
                    _siteKey = destination.key; _siteName = destination.value.first.name;
                  }),
                )),
              ]) : ListView.builder(
                key: ValueKey('daily-report-calendar-${_siteKey!}-${_month.year}-${_month.month}'),
                physics: const AlwaysScrollableScrollPhysics(), padding: const EdgeInsets.all(12),
                itemCount: DateTime(_month.year, _month.month + 1, 0).day,
                itemBuilder: (context, index) {
                  final date = DateTime(_month.year, _month.month, index + 1);
                  final entries = byDate[DailyReportMonthRepository.dateKey(date)] ?? const <DailyReportMonthEntry>[];
                  return _calendarDay(date, entries);
                },
              ))),
      ));
  }

  Widget _calendarDay(DateTime date, List<DailyReportMonthEntry> entries) {
    const weekdays = ['月曜日', '火曜日', '水曜日', '木曜日', '金曜日', '土曜日', '日曜日'];
    final holidayName = JapanHoliday.name(date);
    final dateColor = holidayName != null || date.weekday == DateTime.sunday
        ? Theme.of(context).colorScheme.error
        : date.weekday == DateTime.saturday ? Colors.blue.shade700 : null;
    final today = DateTime.now();
    final isToday = today.year == date.year && today.month == date.month && today.day == date.day;
    return Card(key: ValueKey('daily-report-date-${date.day}'), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8),
      side: BorderSide(color: isToday ? Theme.of(context).colorScheme.primary :
        Theme.of(context).colorScheme.outlineVariant, width: isToday ? 2 : 1)),
      child: Padding(padding: const EdgeInsets.all(12), child: Column(
        crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(SkoLanguageController.trParams('{day}日（{weekday}）', {'day': date.day, 'weekday': SkoLanguageController.tr(weekdays[date.weekday - 1])}),
            key: ValueKey('daily-report-date-label-${date.day}'),
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: dateColor)),
          if (entries.isNotEmpty) Text(SkoLanguageController.trParams('日報 {count}件', {'count': entries.length}),
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          if (entries.isNotEmpty) Wrap(spacing: 6, runSpacing: 4, children: [
            for (final state in DailyReportSaveState.values)
              if (entries.any((entry) => entry.saveState == state)) DailyReportSaveBadge(state: state,
                count: entries.where((entry) => entry.saveState == state).length),
          ]),
          if (entries.isEmpty) Text(SkoLanguageController.tr('日報なし'), style: TextStyle(fontSize: 16))
          else FutureBuilder<List<(DailyReportMonthEntry, bool)>>(
            future: _dayPresence.putIfAbsent(entries.map((entry) => entry.id).join('|'), () => _classify(entries)), builder: (context, snapshot) {
              if (snapshot.hasError) {
                return TextButton(onPressed: () {
                for (final entry in entries) { _photoPresence.remove(entry.id); }
                _dayPresence.remove(entries.map((entry) => entry.id).join('|'));
                setState(() {});
                }, child: Text(SkoLanguageController.tr('写真情報を再読み込み')));
              }
              final records = snapshot.data;
              if (records == null) {
                return Padding(padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Text(SkoLanguageController.tr('日報を確認中…'), style: const TextStyle(fontSize: 17)));
              }
              return Wrap(spacing: 8, runSpacing: 8, children: [
                for (final photos in [false, true])
                  if (records.any((record) => record.$2 == photos)) OutlinedButton.icon(
                    key: ValueKey('daily-report-day-${date.day}-${photos ? 'photos' : 'no-photos'}'),
                    onPressed: _exporting ? null : () => _chooseReport(records
                      .where((record) => record.$2 == photos).map((record) => record.$1).toList()),
                    icon: Icon(photos ? Icons.photo_outlined : Icons.description_outlined),
                    label: Text(SkoLanguageController.trParams(photos ? '写真付き {count}件' : '写真無し {count}件', {'count': records.where((record) => record.$2 == photos).length}),
                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold))),
              ]);
            }),
        ])));
  }

  Future<void> _chooseReport(List<DailyReportMonthEntry> entries) async {
    if (entries.length == 1) { await _openCalendarEntry(entries.single); return; }
    final selected = await showModalBottomSheet<DailyReportMonthEntry>(context: context,
      isScrollControlled: true, builder: (sheetContext) => SafeArea(child: Column(
        mainAxisSize: MainAxisSize.min, children: [
          Padding(padding: const EdgeInsets.all(16), child: Text(SkoLanguageController.tr('日報を選択（古い順）'),
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold))),
          Flexible(child: ListView(shrinkWrap: true, children: [
            for (var i = 0; i < entries.length; i++) ListTile(
              key: ValueKey('daily-report-select-${entries[i].id}'),
              title: Text(SkoLanguageController.trParams('{number}件目 / {kind}', {'number': i + 1, 'kind': SkoLanguageController.tr(entries[i].kindLabel)}), style: const TextStyle(fontSize: 18)),
              subtitle: Text(entries[i].createdAt == null ? SkoLanguageController.tr('作成時刻未取得') : _createdTime(entries[i].createdAt!),
                style: const TextStyle(fontSize: 17)),
              trailing: DailyReportSaveBadge(state: entries[i].saveState),
              onTap: () => Navigator.pop(sheetContext, entries[i]),
            ),
          ])),
        ])));
    if (selected != null && mounted) await _openCalendarEntry(selected);
  }

  (String, String, String) _entryGroup(DailyReportMonthEntry entry) =>
      (DailyReportMonthRepository.dateKey(entry.date),
       entry.siteId ?? entry.routeId ?? entry.name, entry.kindLabel);

  String _entrySubtitle(DailyReportMonthEntry entry, int ordinal, int count) {
    final parts = <String>[
      DailyReportMonthRepository.dateKey(entry.date),
      entry.kindLabel,
      if (count > 1) '$ordinal／$count件目',
      if (entry.createdAt != null) _createdTime(entry.createdAt!),
      entry.saveState.label,
    ];
    return parts.join(' / ');
  }

  String _createdTime(DateTime value) {
    final japan = value.toUtc().add(const Duration(hours: 9));
    return SkoLanguageController.trParams('作成 {hour}:{minute}', {'hour': japan.hour.toString().padLeft(2, '0'), 'minute': japan.minute.toString().padLeft(2, '0')});
  }

  @override
  Widget build(BuildContext context) {
    SkoLanguageController.watch(context);
    return _selectedDate != null ? _legacyBuild(context) : _monthBuild(context);
  }

  Widget _legacyBuild(BuildContext context) {
    final counts = <(String, String, String), int>{};
    final ordinals = <(String, String, String), int>{};
    final entryOrdinals = <int>[];
    for (final entry in _visibleEntries) {
      final group = _entryGroup(entry);
      counts[group] = (counts[group] ?? 0) + 1;
      ordinals[group] = (ordinals[group] ?? 0) + 1;
      entryOrdinals.add(ordinals[group]!);
    }
    return Scaffold(
    appBar: AppBar(title: Text(SkoLanguageController.tr('日報一覧・保存')), actions: [
      IconButton(tooltip: SkoLanguageController.tr('日報一覧のヘルプ'), onPressed: _help, icon: const Icon(Icons.help_outline)),
    ]),
    body: _withPendingControls(Column(
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
              Text(
                '${_selectedDate == null ? 'この月' : 'この日'}に閲覧できる保存済み日報と写真証跡を、日報ごとのPDFを1つのZIPにまとめます。共有画面から「ファイルに保存」も選べます。',
              ),
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: _loading || _exporting || _visibleEntries.isEmpty
                    ? null
                    : _export,
                icon: const Icon(Icons.ios_share),
                label: Text(
                  _exporting
                      ? '日報・写真を読み込み中…'
                      : '${_selectedDate == null ? 'この月' : 'この日'}をまとめて保存・共有 (${_visibleEntries.length}件)',
                ),
              ),
              if (_selectedDate != null && widget.workerId != null && _visibleEntries.any((entry) => entry.routeId != null))
                OutlinedButton.icon(onPressed: _loading || _exporting || _openingEntryId != null ? null : _openQuantities,
                  icon: const Icon(Icons.request_quote_outlined), label: Text(SkoLanguageController.tr('請求数量を申請'))),
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
                      Text(SkoLanguageController.tr(_error!)),
                      TextButton(onPressed: _load, child: Text(SkoLanguageController.tr('再読み込み'))),
                    ],
                  ),
                )
              : _visibleEntries.isEmpty
              ? Center(child: Text('${_selectedDate == null ? 'この月' : 'この日'}の保存済み日報はありません。'))
              : RefreshIndicator(
                  onRefresh: _exporting ? () async {} : _load,
                  child: ListView.builder(
                    itemCount: _visibleEntries.length,
                    itemBuilder: (context, index) {
                      final item = _visibleEntries[index];
                      return ListTile(
                        title: Text(item.name),
                        onTap: _exporting || _openingEntryId != null ? null : () => _openEntry(item),
                        subtitle: Text(
                          _entrySubtitle(item, entryOrdinals[index], counts[_entryGroup(item)]!),
                        ),
                        trailing: _openingEntryId == item.id
                            ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                            : Row(mainAxisSize: MainAxisSize.min, children: [DailyReportSaveBadge(state: item.saveState),
                              IconButton(tooltip: SkoLanguageController.tr('表示・印刷・保存'), icon: const Icon(Icons.picture_as_pdf_outlined),
                                onPressed: _exporting || _openingEntryId != null ? null : () => _openEntry(item))]),
                      );
                    },
                  ),
                ),
        ),
      ],
    )),
  );
  }
}




