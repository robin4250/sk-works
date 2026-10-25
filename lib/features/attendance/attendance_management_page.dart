import 'package:flutter/material.dart';

import '../notifications/notification_bell.dart';
import '../daily_reports/daily_report_page.dart';
import 'attendance_management_repository.dart';
import 'attendance_checkout_minute_guard.dart';
import '../../international/language_controller.dart';

String attendanceManagementActionErrorMessage(Object error) {
  final raw = error.toString();
  if (raw.contains('shared_report_roster_requires_approved_edit') ||
      raw.contains('shared_report_signed_facts_require_approved_edit')) {
    return 'サイン済み日報に紐づく出勤のため、削除・変更できません。先に対象日報の手直し手続きを確認してください。';
  }
  if (error is StateError || error is FormatException) {
    return dailyReportActionErrorMessage(error);
  }
  return '処理結果を確認できませんでした。通信状態を確認して再読み込みしてください。';
}

class AttendanceManagementPage extends StatefulWidget {
  const AttendanceManagementPage({super.key, this.repository, this.initialWorkerId,
    this.initialDate, this.restrictedRecovery = false});
  final AttendanceManagementRepository? repository;
  final String? initialWorkerId;
  final DateTime? initialDate;
  /// Recovery stays inside the gate's dedicated Navigator. Server permissions
  /// are still checked by the existing management repository on every write.
  final bool restrictedRecovery;

  @override
  State<AttendanceManagementPage> createState() => _AttendanceManagementPageState();
}

class _AttendanceManagementPageState extends State<AttendanceManagementPage> {
  late final _repository = widget.repository ?? AttendanceManagementRepository.maybeCreate();
  List<AttendanceManagementOption> _workers = const [];
  List<AttendanceManagementOption> _sites = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final repository = _repository;
    if (repository == null) {
      setState(() { _loading = false; _error = SkoLanguageController.tr('勤怠管理を利用できません。'); });
      return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      final options = await repository.loadOptions();
      if (!mounted) return;
      if (widget.initialWorkerId != null && !options.workers.any((worker) => worker.id == widget.initialWorkerId)) {
        throw StateError('対象の従業員を勤怠管理で確認できません。');
      }
      setState(() {
        _workers = options.workers;
        _sites = options.sites;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString().replaceFirst('Bad state: ', '');
      });
    }
  }

  @override
  void dispose() {
    FocusManager.instance.primaryFocus?.unfocus();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final repository = _repository;
    return PopScope(
      onPopInvokedWithResult: (_, _) => FocusManager.instance.primaryFocus?.unfocus(),
      child: DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(SkoLanguageController.tr('勤怠管理'), style: const TextStyle(fontWeight: FontWeight.w900)),
          actions: [if (!widget.restrictedRecovery) const SkoNotificationBell()],
          bottom: TabBar(
            tabs: [
              Tab(
                text: SkoLanguageController.tr('個別'),
                icon: const Icon(Icons.person_outline),
              ),
              Tab(
                text: SkoLanguageController.tr('一括'),
                icon: const Icon(Icons.groups_outlined),
              ),
            ],
          ),
        ),
        body: SafeArea(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(_error!, textAlign: TextAlign.center),
                            const SizedBox(height: 12),
                            FilledButton.icon(onPressed: _load, icon: const Icon(Icons.refresh), label: const Text('再試行')),
                          ],
                        ),
                      ),
                    )
                  : repository == null
                      ? Center(child: Text(SkoLanguageController.tr('勤怠管理を利用できません。')))
                      : TabBarView(
                          children: [
                            _IndividualManagementPanel(repository: repository, workers: _workers, sites: _sites, initialWorkerId: widget.initialWorkerId, initialDate: widget.initialDate),
                            _BulkManagementPanel(repository: repository, workers: _workers, sites: _sites),
                          ],
                        ),
        ),
      ),
    ));
  }
}

class _ManagementDatePicker extends StatefulWidget {
  const _ManagementDatePicker({required this.repository, required this.workerId, required this.initialDate});
  final AttendanceManagementRepository repository;
  final String workerId;
  final DateTime initialDate;
  @override State<_ManagementDatePicker> createState() => _ManagementDatePickerState();
}
class _ManagementDatePickerState extends State<_ManagementDatePicker> {
  late DateTime _month = DateTime(widget.initialDate.year, widget.initialDate.month);
  Map<int, Set<String>> _marks = const {};
  bool _loading = true;
  Object? _error;
  int _generation = 0;
  @override void initState() { super.initState(); _load(); }
  Future<void> _load() async {
    final generation = ++_generation;
    setState(() { _loading = true; _error = null; _marks = const {}; });
    try {
      final marks = await widget.repository.loadMonthMarks(workerId: widget.workerId, month: _month);
      if (mounted && generation == _generation) setState(() { _marks = marks; _loading = false; });
    } catch (error) {
      if (mounted && generation == _generation) setState(() { _error = error; _loading = false; });
    }
  }
  void _move(int delta) {
    setState(() => _month = DateTime(_month.year, _month.month + delta));
    _load();
  }
  @override Widget build(BuildContext context) {
    final offset = _month.weekday % 7;
    final days = DateUtils.getDaysInMonth(_month.year, _month.month);
    return AlertDialog(title: const Text('勤務日を選択'), content: SizedBox(width: 340,
      child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          IconButton(tooltip: '前の月', onPressed: _month.year > 2020 || _month.month > 1 ? () => _move(-1) : null, icon: const Icon(Icons.chevron_left)),
          Text('${_month.year}年${_month.month}月'),
          IconButton(tooltip: '次の月', onPressed: _month.year < DateTime.now().year + 5 || _month.month < 12 ? () => _move(1) : null, icon: const Icon(Icons.chevron_right)),
        ]),
        const Text('青● 出勤　橙● 打刻のみ　緑● 承認済み有給', style: TextStyle(fontSize: 11)),
        if (_loading) const LinearProgressIndicator(),
        if (_error != null) ...[
          const Text('勤務日の目印を取得できません。日付は選択できます。'),
          TextButton(onPressed: _load, child: const Text('再読み込み')),
        ],
        Row(children: [for (final day in ['日', '月', '火', '水', '木', '金', '土'])
          Expanded(child: Center(child: Text(day)))]),
        GridView.builder(shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 7, childAspectRatio: .85),
          itemCount: ((offset + days + 6) ~/ 7) * 7,
          itemBuilder: (_, index) {
            final day = index - offset + 1;
            if (day < 1 || day > days) return const SizedBox.shrink();
            final marks = _marks[day] ?? const <String>{};
            final label = [if (marks.contains('work')) '出勤', if (marks.contains('punch')) '打刻のみ', if (marks.contains('leave')) '承認済み有給'].join('・');
            return Semantics(label: '${_month.month}月$day日 $label', button: true,
              child: InkWell(onTap: () => Navigator.pop(context, DateTime(_month.year, _month.month, day)),
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Text('$day'),
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    for (final entry in {'work': Colors.blue, 'punch': Colors.orange, 'leave': Colors.green}.entries)
                      if (marks.contains(entry.key)) Text('●', style: TextStyle(color: entry.value, fontSize: 10)),
                  ]),
                ])));
          }),
      ]))), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('キャンセル'))]);
  }
}

class _IndividualManagementPanel extends StatefulWidget {
  const _IndividualManagementPanel({required this.repository, required this.workers, required this.sites, this.initialWorkerId, this.initialDate});
  final String? initialWorkerId;
  final DateTime? initialDate;
  final AttendanceManagementRepository repository;
  final List<AttendanceManagementOption> workers;
  final List<AttendanceManagementOption> sites;

  @override
  State<_IndividualManagementPanel> createState() => _IndividualManagementPanelState();
}

class _IndividualManagementPanelState extends State<_IndividualManagementPanel> {
  final _form = _ManagementFormState();
  String? _workerId;
  DateTime _date = DateTime.now();
  bool _loadingCell = false;
  bool _cellReady = false;
  int _cellGeneration = 0;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    if (widget.workers.isNotEmpty) {
      _workerId = widget.initialWorkerId ?? widget.workers.first.id;
      final initial = widget.initialDate;
      if (initial != null) _date = DateTime(initial.year, initial.month, initial.day);
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadCell());
    }
  }

  Future<void> _loadCell() async {
    final workerId = _workerId;
    if (workerId == null) return;
    final date = _date;
    final generation = ++_cellGeneration;
    setState(() { _loadingCell = true; _cellReady = false; });
    try {
      final cell = await widget.repository.loadCell(workerId: workerId, date: date);
      if (!mounted || generation != _cellGeneration || workerId != _workerId || date != _date) return;
      setState(() { _form.load(cell); _loadingCell = false; _cellReady = true; });
    } catch (error) {
      if (!mounted || generation != _cellGeneration) return;
      setState(() => _loadingCell = false);
      _show('読み込めませんでした: $error');
    }
  }

  Future<void> _pickDate() async {
    FocusManager.instance.primaryFocus?.unfocus();
    final worker = _workerId;
    if (worker == null) return;
    final value = await showDialog<DateTime>(context: context, builder: (_) =>
      _ManagementDatePicker(repository: widget.repository, workerId: worker, initialDate: _date));
    if (value == null || !mounted) return;
    setState(() => _date = value);
    await _loadCell();
  }

  Future<void> _apply() async {
    final workerId = _workerId;
    if (workerId == null || _busy || _loadingCell || !_cellReady) return;
    final values = _form.values(context, widget.sites);
    if (values == null) return;
    setState(() => _busy = true);
    try {
      await widget.repository.apply(
        action: 'upsert',
        workerIds: [workerId],
        dates: [_date],
        mode: values.mode,
        siteId: values.siteId,
        manDays: values.manDays,
        overtimeHours: values.overtimeHours,
        earlyHours: values.earlyHours,
        nightHours: values.nightHours,
        allowanceNames: values.allowanceNames,
        notes: values.notes,
        workDescription: values.workDescription,
        clockIn: values.clockIn,
        clockOut: values.clockOut,
      );
      if (!mounted) return;
      _show('この日の勤怠・有給・日報を直接更新しました');
      await _loadCell();
    } catch (error) {
      if (mounted) _show(attendanceManagementActionErrorMessage(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    final workerId = _workerId;
    if (workerId == null || _busy || _loadingCell || !_cellReady) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('この日のデータを削除しますか？'),
        content: const Text('出勤・有給・対象従業員の日報行を直接削除します。承認待ちは通りません。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: Text(SkoLanguageController.tr('キャンセル'))),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: Text(SkoLanguageController.tr('削除'))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await widget.repository.apply(action: 'delete', workerIds: [workerId], dates: [_date], mode: 'off');
      if (!mounted) return;
      _show('この日の勤怠・有給・日報を削除しました');
      await _loadCell();
    } catch (error) {
      if (mounted) _show(attendanceManagementActionErrorMessage(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openReport() async {
    final workerId = _workerId;
    final date = _date;
    if (workerId == null || _busy || _loadingCell) return;
    setState(() => _busy = true);
    try {
      final reports = await widget.repository.loadReports(workerId: workerId, date: date);
      if (!mounted || workerId != _workerId || date != _date) return;
      if (reports.isEmpty) {
        _show('選択した従業員・日付の保存済み日報はありません。勤怠の登録だけではサインは作成されません。');
        return;
      }
      final selected = reports.length == 1 ? reports.single :
        await showDialog<AttendanceManagementReport>(context: context, builder: (dialogContext) =>
          SimpleDialog(title: const Text('確認する日報'), children: [
            for (var i = 0; i < reports.length; i++)
              SimpleDialogOption(onPressed: () => Navigator.pop(dialogContext, reports[i]),
                child: Text('${i + 1}. ${reports[i].siteId == null ? 'ルート日報' : widget.sites.where((site) => site.id == reports[i].siteId).firstOrNull?.name ?? '現場日報'}')),
          ]));
      if (selected == null || !mounted) return;
      // Recheck access and membership after an arbitrarily long selection dialog.
      final fresh = await widget.repository.loadReports(workerId: workerId, date: date);
      if (!mounted || workerId != _workerId || date != _date) return;
      if (!fresh.any((report) => report.id == selected.id &&
          report.companyId == selected.companyId && report.siteId == selected.siteId &&
          report.routeId == selected.routeId)) {
        throw StateError('対象の日報が変わりました。読み込み直してください。');
      }
      await Navigator.of(context).push<void>(MaterialPageRoute(builder: (_) => DailyReportPage(
        initialReportId: selected.id, initialDate: selected.date,
        initialSiteId: selected.siteId, initialRouteAssignmentId: selected.routeId)));
      if (mounted) await _loadCell();
    } catch (error) {
      if (mounted) _show('日報を開けませんでした: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _show(String message) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));

  @override
  Widget build(BuildContext context) {
    return ListView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 32),
      children: [
        const _DirectEditWarning(),
        const SizedBox(height: 10),
        DropdownButtonFormField<String>(
          initialValue: _workerId,
          decoration: const InputDecoration(labelText: '従業員', border: OutlineInputBorder()),
          items: [for (final worker in widget.workers) DropdownMenuItem(value: worker.id, child: Text(worker.name))],
          onChanged: _busy ? null : (value) async { setState(() => _workerId = value); await _loadCell(); },
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: _busy ? null : _pickDate,
          icon: const Icon(Icons.calendar_month_outlined),
          label: Text(_dateText(_date)),
        ),
        if (_loadingCell) ...[const SizedBox(height: 8), const LinearProgressIndicator()],
        const SizedBox(height: 12),
        OutlinedButton.icon(onPressed: _busy || _loadingCell ? null : _openReport,
          icon: const Icon(Icons.draw_outlined), label: const Text('この日の日報・共通手当・サインを開く')),
        const Text('社内共通手当は日報内の登録済み手当から選択します。ここで入力する自由名称とは別に保存されます。署名済み内容は保持し、変更には既存の編集承認が必要です。'),
        const SizedBox(height: 12),
        _ManagementForm(form: _form, sites: widget.sites, enabled: !_busy),
        const SizedBox(height: 16),
        FilledButton.icon(onPressed: _busy || _loadingCell ? null : _apply, icon: const Icon(Icons.save_outlined), label: const Text('登録・編集を直接反映')),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _busy || _loadingCell ? null : _delete,
          icon: const Icon(Icons.delete_outline),
          label: const Text('この日の勤怠・有給・日報を削除'),
        ),
      ],
    );
  }
}

class _BulkManagementPanel extends StatefulWidget {
  const _BulkManagementPanel({required this.repository, required this.workers, required this.sites});
  final AttendanceManagementRepository repository;
  final List<AttendanceManagementOption> workers;
  final List<AttendanceManagementOption> sites;

  @override
  State<_BulkManagementPanel> createState() => _BulkManagementPanelState();
}

class _BulkManagementPanelState extends State<_BulkManagementPanel> {
  final _form = _ManagementFormState();
  final Set<String> _workerIds = {};
  final Set<DateTime> _dates = {};
  late DateTime _month;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _month = DateTime(now.year, now.month);
  }

  Future<void> _apply() async {
    if (_busy) return;
    if (_workerIds.isEmpty || _dates.isEmpty) { _show('従業員と日付を1つ以上選択してください'); return; }
    final values = _form.values(context, widget.sites);
    if (values == null) return;
    setState(() => _busy = true);
    try {
      final count = await widget.repository.apply(
        action: 'upsert', workerIds: _workerIds, dates: _dates, mode: values.mode, siteId: values.siteId,
        manDays: values.manDays, overtimeHours: values.overtimeHours, earlyHours: values.earlyHours, nightHours: values.nightHours,
        allowanceNames: values.allowanceNames, notes: values.notes, workDescription: values.workDescription,
        clockIn: values.clockIn, clockOut: values.clockOut,
      );
      if (mounted) _show('$count件を一括で直接更新しました');
    } catch (error) {
      if (mounted) _show('一括更新できませんでした: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    if (_busy) return;
    if (_workerIds.isEmpty || _dates.isEmpty) { _show('従業員と日付を1つ以上選択してください'); return; }
    final total = _workerIds.length * _dates.length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('$total件を一括削除しますか？'),
        content: const Text('選択した従業員・日付の出勤、有給、日報行を直接削除します。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: Text(SkoLanguageController.tr('キャンセル'))),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: Text(SkoLanguageController.tr('一括削除'))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      final count = await widget.repository.apply(action: 'delete', workerIds: _workerIds, dates: _dates, mode: 'off');
      if (mounted) _show('$count件を一括削除しました');
    } catch (error) {
      if (mounted) _show(attendanceManagementActionErrorMessage(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _show(String message) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));

  @override
  Widget build(BuildContext context) {
    final days = DateUtils.getDaysInMonth(_month.year, _month.month);
    return ListView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 32),
      children: [
        const _DirectEditWarning(),
        const SizedBox(height: 10),
        Text('従業員（複数選択）', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
        Card(
          child: Column(
            children: [
              CheckboxListTile(
                value: _workerIds.length == widget.workers.length && widget.workers.isNotEmpty,
                tristate: true,
                title: const Text('全員選択'),
                onChanged: _busy ? null : (value) => setState(() {
                  if (value == true) { _workerIds.addAll(widget.workers.map((e) => e.id)); } else { _workerIds.clear(); }
                }),
              ),
              const Divider(height: 1),
              for (final worker in widget.workers)
                CheckboxListTile(
                  value: _workerIds.contains(worker.id),
                  title: Text(worker.name),
                  dense: true,
                  onChanged: _busy ? null : (value) => setState(() { if (value == true) { _workerIds.add(worker.id); } else { _workerIds.remove(worker.id); } }),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            IconButton(onPressed: _busy ? null : () => setState(() { _month = DateTime(_month.year, _month.month - 1); _dates.clear(); }), icon: const Icon(Icons.chevron_left)),
            Expanded(child: Text('${_month.year}年${_month.month}月', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18))),
            IconButton(onPressed: _busy ? null : () => setState(() { _month = DateTime(_month.year, _month.month + 1); _dates.clear(); }), icon: const Icon(Icons.chevron_right)),
          ],
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Wrap(
              spacing: 6, runSpacing: 6,
              children: [
                for (var day = 1; day <= days; day++)
                  Builder(builder: (context) {
                    final date = DateTime(_month.year, _month.month, day);
                    return FilterChip(
                      label: Text('$day日'), selected: _dates.contains(date),
                      onSelected: _busy ? null : (value) => setState(() { if (value) { _dates.add(date); } else { _dates.remove(date); } }),
                    );
                  }),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        _ManagementForm(form: _form, sites: widget.sites, enabled: !_busy),
        const SizedBox(height: 14),
        Text('選択: ${_workerIds.length}人 × ${_dates.length}日 = ${_workerIds.length * _dates.length}件', style: const TextStyle(fontWeight: FontWeight.w900)),
        const SizedBox(height: 10),
        FilledButton.icon(onPressed: _busy ? null : _apply, icon: const Icon(Icons.done_all), label: Text(SkoLanguageController.tr('一括登録・編集を直接反映'))),
        const SizedBox(height: 8),
        OutlinedButton.icon(onPressed: _busy ? null : _delete, icon: const Icon(Icons.delete_sweep_outlined), label: Text(SkoLanguageController.tr('選択範囲を一括削除'))),
      ],
    );
  }
}

class _DirectEditWarning extends StatelessWidget {
  const _DirectEditWarning();
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Icon(Icons.admin_panel_settings_outlined, color: Theme.of(context).colorScheme.error),
          const SizedBox(width: 10),
          const Expanded(child: Text('管理者・サブ管理者用の直接管理です。承認待ちを通さず、勤怠・有給・日報へ即時反映します。', style: TextStyle(fontWeight: FontWeight.w800))),
        ],
      ),
    ),
  );
}

class _ManagementValues {
  const _ManagementValues({
    required this.mode, required this.siteId, required this.manDays, required this.overtimeHours,
    required this.earlyHours, required this.nightHours, required this.allowanceNames, required this.notes,
    required this.workDescription, required this.clockIn, required this.clockOut,
  });
  final String mode;
  final String? siteId;
  final double manDays;
  final double overtimeHours;
  final double earlyHours;
  final double nightHours;
  final List<String> allowanceNames;
  final String notes;
  final String workDescription;
  final String? clockIn;
  final String? clockOut;
}

class _ManagementFormState {
  String mode = 'work';
  bool hasUnrecordedPunches = false;
  String? siteId;
  final manDays = TextEditingController(text: '1');
  final overtime = TextEditingController(text: '0');
  final early = TextEditingController(text: '0');
  final night = TextEditingController(text: '0');
  final clockIn = TextEditingController(text: '08:00');
  final clockOut = TextEditingController(text: '17:00');
  DateTime? _loadedClockIn;
  DateTime? _loadedClockOut;
  final notes = TextEditingController();
  final workDescription = TextEditingController();
  final List<TextEditingController> allowances = [];

  void load(AttendanceManagementCell cell) {
    mode = cell.mode;
    hasUnrecordedPunches = cell.hasUnrecordedPunches;
    siteId = cell.siteId;
    manDays.text = cell.hasUnrecordedPunches ? '' : _num(cell.manDays);
    overtime.text = _num(cell.overtimeHours);
    early.text = _num(cell.earlyHours);
    night.text = _num(cell.nightHours);
    _loadedClockIn = cell.clockIn;
    _loadedClockOut = cell.clockOut;
    clockIn.text = cell.clockIn == null ? '' : _time(cell.clockIn!);
    clockOut.text = cell.clockOut == null ? '' : _time(cell.clockOut!);
    notes.text = cell.notes;
    workDescription.text = cell.workDescription;
    for (final controller in allowances) { controller.dispose(); }
    allowances
      ..clear()
      ..addAll(cell.allowanceNames.map((name) => TextEditingController(text: name)));
  }

  _ManagementValues? values(BuildContext context, List<AttendanceManagementOption> sites) {
    if (hasUnrecordedPunches && mode != 'work') {
      _message(context, '出退勤の打刻があります。勤務内容を確認して出勤として登録してください。削除する場合は削除ボタンで確認してください。');
      return null;
    }
    if (mode == 'work' && (siteId == null || !sites.any((site) => site.id == siteId))) {
      _message(context, '現場を選択してください');
      return null;
    }
    final parsedManDays = double.tryParse(manDays.text.trim());
    final parsedOvertime = double.tryParse(overtime.text.trim());
    final parsedEarly = double.tryParse(early.text.trim());
    final parsedNight = double.tryParse(night.text.trim());
    if (parsedManDays == null || parsedManDays < 0 || parsedOvertime == null || parsedOvertime < 0 || parsedEarly == null || parsedEarly < 0 || parsedNight == null || parsedNight < 0) {
      _message(context, '人工・残業・早出・夜勤は0以上の数値で入力してください');
      return null;
    }
    if (!_validTime(clockIn.text) || !_validTime(clockOut.text)) {
      _message(context, '出勤・退勤時刻は HH:mm 形式で入力してください');
      return null;
    }
    if (mode == 'work' && clockIn.text.trim().isNotEmpty &&
        clockIn.text.trim() == clockOut.text.trim()) {
      _message(context, sameMinuteCheckoutMessage);
      return null;
    }
    return _ManagementValues(
      mode: mode, siteId: siteId, manDays: parsedManDays, overtimeHours: parsedOvertime, earlyHours: parsedEarly, nightHours: parsedNight,
      allowanceNames: [for (final c in allowances) if (c.text.trim().isNotEmpty) c.text.trim()],
      notes: notes.text.trim(), workDescription: workDescription.text.trim(),
      clockIn: _submittedTime(clockIn.text, _loadedClockIn),
      clockOut: _submittedTime(clockOut.text, _loadedClockOut),
    );
  }

  // Display remains HH:mm; an untouched field retains the original evidence.
  static String? _submittedTime(String value, DateTime? loaded) {
    final text = value.trim();
    if (text.isEmpty) return null;
    if (loaded == null || text != _time(loaded)) return text;
    final seconds = loaded.second.toString().padLeft(2, '0');
    final fraction = (loaded.millisecond * 1000 + loaded.microsecond)
        .toString().padLeft(6, '0');
    return '${_time(loaded)}:$seconds.$fraction';
  }

  static bool _validTime(String value) {
    final text = value.trim();
    if (text.isEmpty) return true;
    final match = RegExp(r'^([01]?[0-9]|2[0-3]):[0-5][0-9]$').firstMatch(text);
    return match != null;
  }
  static String _num(double value) => value == value.roundToDouble() ? value.toInt().toString() : value.toStringAsFixed(2);
  static String _time(DateTime value) =>
      '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
  static void _message(BuildContext context, String message) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

class _ManagementForm extends StatefulWidget {
  const _ManagementForm({required this.form, required this.sites, required this.enabled});
  final _ManagementFormState form;
  final List<AttendanceManagementOption> sites;
  final bool enabled;

  @override
  State<_ManagementForm> createState() => _ManagementFormWidgetState();
}

class _ManagementFormWidgetState extends State<_ManagementForm> {
  @override
  Widget build(BuildContext context) {
    final form = widget.form;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (form.hasUnrecordedPunches) ...[
          const Text('出退勤の打刻がありますが、給与用の勤務記録は未確定です。出勤を選び、現場・人工・作業内容を確認して登録してください。'),
          Text('保存済み打刻　出勤：${form.clockIn.text.isEmpty ? '未確認' : form.clockIn.text}　退勤：${form.clockOut.text.isEmpty ? '未確認' : form.clockOut.text}'),
          const SizedBox(height: 12),
        ],
        SegmentedButton<String>(
          segments: [
            if (form.hasUnrecordedPunches) const ButtonSegment(value: 'pending_work', label: Text('未確定'), icon: Icon(Icons.pending_outlined)),
            const ButtonSegment(value: 'work', label: Text('出勤'), icon: Icon(Icons.work_outline)),
            const ButtonSegment(value: 'paid_leave', label: Text('有給'), icon: Icon(Icons.event_available_outlined)),
            const ButtonSegment(value: 'off', label: Text('休み'), icon: Icon(Icons.free_breakfast_outlined)),
          ],
          selected: {form.mode},
          onSelectionChanged: widget.enabled ? (values) => setState(() => form.mode = values.first) : null,
        ),
        const SizedBox(height: 12),
        if (form.mode == 'work') ...[
          DropdownButtonFormField<String>(
            initialValue: widget.sites.any((site) => site.id == form.siteId) ? form.siteId : null,
            decoration: const InputDecoration(labelText: '現場', border: OutlineInputBorder()),
            items: [for (final site in widget.sites) DropdownMenuItem(value: site.id, child: Text(site.name))],
            onChanged: widget.enabled ? (value) => setState(() => form.siteId = value) : null,
          ),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: _numberField(form.manDays, '人工')),
            const SizedBox(width: 8),
            Expanded(child: _numberField(form.overtime, '残業', suffix: '時間')),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: _numberField(form.early, '早出', suffix: '時間')),
            const SizedBox(width: 8),
            Expanded(child: _numberField(form.night, '夜勤', suffix: '時間')),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: TextField(enabled: widget.enabled, controller: form.clockIn, keyboardType: TextInputType.datetime, decoration: const InputDecoration(labelText: '出勤時刻', hintText: '08:00', border: OutlineInputBorder()))),
            const SizedBox(width: 8),
            Expanded(child: TextField(enabled: widget.enabled, controller: form.clockOut, keyboardType: TextInputType.datetime, decoration: const InputDecoration(labelText: '退勤時刻', hintText: '17:00', border: OutlineInputBorder()))),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            const Expanded(child: Text('手当', style: TextStyle(fontWeight: FontWeight.w900))),
            TextButton.icon(
              onPressed: widget.enabled ? () => setState(() => form.allowances.add(TextEditingController())) : null,
              icon: const Icon(Icons.add),
              label: const Text('手当を追加'),
            ),
          ]),
          if (form.allowances.isEmpty) const Text('手当なし') else
            for (var i = 0; i < form.allowances.length; i++) ...[
              Row(children: [
                Expanded(child: TextField(enabled: widget.enabled, controller: form.allowances[i], decoration: InputDecoration(labelText: '手当${i + 1}', border: const OutlineInputBorder()))),
                IconButton(onPressed: widget.enabled ? () => setState(() => form.allowances.removeAt(i).dispose()) : null, icon: const Icon(Icons.remove_circle_outline)),
              ]),
              const SizedBox(height: 6),
            ],
          TextField(enabled: widget.enabled, controller: form.workDescription, maxLines: 3, decoration: const InputDecoration(labelText: '日報・作業内容', border: OutlineInputBorder())),
          const SizedBox(height: 10),
        ],
        if (form.mode != 'off')
          TextField(enabled: widget.enabled, controller: form.notes, maxLines: 2, decoration: InputDecoration(labelText: form.mode == 'paid_leave' ? '有給メモ' : '勤怠メモ', border: const OutlineInputBorder())),
      ],
    );
  }

  Widget _numberField(TextEditingController controller, String label, {String? suffix}) => TextField(
    enabled: widget.enabled, controller: controller, keyboardType: const TextInputType.numberWithOptions(decimal: true),
    decoration: InputDecoration(labelText: label, suffixText: suffix, border: const OutlineInputBorder()),
  );
}

String _dateText(DateTime value) =>
    '${value.year}/${value.month.toString().padLeft(2, '0')}/${value.day.toString().padLeft(2, '0')}';

