import 'package:flutter/material.dart';

import '../notifications/notification_bell.dart';
import '../../international/language_controller.dart';
import '../daily_reports/daily_report_page.dart';
import 'attendance_pdf_service.dart';
import 'japan_holiday.dart';
import 'worker_attendance_sheet_repository.dart';

class WorkerAttendanceSheetPage extends StatefulWidget {
  const WorkerAttendanceSheetPage({
    super.key,
    this.workerId,
    this.workerName,
  });

  final String? workerId;
  final String? workerName;

  @override
  State<WorkerAttendanceSheetPage> createState() =>
      _WorkerAttendanceSheetPageState();
}

class _WorkerAttendanceSheetPageState extends State<WorkerAttendanceSheetPage> {
  final _repository = WorkerAttendanceSheetRepository.maybeCreate();

  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  WorkerAttendanceMonth? _data;
  bool _loading = true;
  String? _error;
  int _selectedWeek = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final repository = _repository;
    if (repository == null) {
      setState(() {
        _loading = false;
        _error = SkoLanguageController.tr('クラウド接続を確認できません。');
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final data = await repository.loadMonth(
        _month,
        workerId: widget.workerId,
      );
      if (!mounted) return;
      final weeks = _weeksForMonth(_month);
      setState(() {
        _data = data;
        _selectedWeek = _selectedWeek.clamp(0, weeks.length - 1);
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _openDailyReport(DateTime date) async {
    final repository = _repository;
    if (repository == null) return;
    final target = await repository.findDailyReportForDate(
      date,
      workerId: widget.workerId,
    );
    if (target == null || !mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DailyReportPage(
          initialDate: date,
          initialSiteId: target.siteId,
          initialRouteAssignmentId: target.routeAssignmentId,
        ),
      ),
    );
  }

  Future<void> _changeMonth(int delta) async {
    setState(() {
      _month = DateTime(_month.year, _month.month + delta);
      _selectedWeek = 0;
    });
    await _load();
  }

  List<List<DateTime>> _weeksForMonth(DateTime month) {
    final first = DateTime(month.year, month.month, 1);
    final last = DateTime(month.year, month.month + 1, 0);
    final gridStart = first.subtract(Duration(days: first.weekday - 1));
    final gridEnd = last.add(Duration(days: 7 - last.weekday));

    final days = <DateTime>[];
    for (
      var day = gridStart;
      !day.isAfter(gridEnd);
      day = day.add(const Duration(days: 1))
    ) {
      days.add(day);
    }

    return [
      for (var i = 0; i < days.length; i += 7)
        days.sublist(i, i + 7),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final weeks = _weeksForMonth(_month);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.workerName?.trim().isNotEmpty == true
              ? '${widget.workerName}・${SkoLanguageController.tr('出勤表')}'
              : SkoLanguageController.tr('出勤表'),
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        actions: [
          IconButton(
            tooltip: SkoLanguageController.tr('月間カレンダー'),
            onPressed: _loading ? null : _showMonthCalendar,
            icon: const Icon(Icons.calendar_month_outlined),
          ),
          const SkoNotificationBell(),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            _MonthHeader(
              month: _month,
              onPrevious: () => _changeMonth(-1),
              onNext: () => _changeMonth(1),
            ),
            _WeekTabs(
              count: weeks.length,
              selected: _selectedWeek,
              onChanged: (index) => setState(() => _selectedWeek = index),
            ),
            const Divider(height: 1),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? _ErrorState(message: _error!, onRetry: _load)
                      : _WeekList(
                          month: _month,
                          week: weeks[_selectedWeek],
                          data: _data!,
                          onDateTap: _openDailyReport,
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showMonthCalendar() async {
    final data = _data;
    if (data == null) return;

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => WorkerAttendanceMonthPage(
          month: _month,
          data: data,
          workerId: widget.workerId,
          workerName: widget.workerName,
        ),
      ),
    );
  }
}

class _MonthHeader extends StatelessWidget {
  const _MonthHeader({
    required this.month,
    required this.onPrevious,
    required this.onNext,
  });

  final DateTime month;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 4),
      child: Row(
        children: [
          IconButton(
            tooltip: SkoLanguageController.tr('前の月'),
            onPressed: onPrevious,
            icon: const Icon(Icons.chevron_left),
          ),
          Expanded(
            child: Text(
              SkoLanguageController.isEnglish
                  ? '${month.month}/${month.year}'
                  : '${month.year}年${month.month}月',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
            ),
          ),
          IconButton(
            tooltip: SkoLanguageController.tr('次の月'),
            onPressed: onNext,
            icon: const Icon(Icons.chevron_right),
          ),
        ],
      ),
    );
  }
}

class _WeekTabs extends StatelessWidget {
  const _WeekTabs({
    required this.count,
    required this.selected,
    required this.onChanged,
  });

  final int count;
  final int selected;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        scrollDirection: Axis.horizontal,
        itemCount: count,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (context, index) {
          final active = index == selected;
          return ChoiceChip(
            label: Text(SkoLanguageController.isEnglish ? 'Week ${index + 1}' : '${index + 1}週'),
            selected: active,
            onSelected: (_) => onChanged(index),
          );
        },
      ),
    );
  }
}

class _WeekList extends StatelessWidget {
  const _WeekList({
    required this.month,
    required this.week,
    required this.data,
    required this.onDateTap,
  });

  final DateTime month;
  final List<DateTime> week;
  final WorkerAttendanceMonth data;
  final ValueChanged<DateTime> onDateTap;

  static const _weekdayNamesJa = ['月', '火', '水', '木', '金', '土', '日'];
  static const _weekdayNamesEn = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final verticalPadding = 4.0;
        final itemHeight =
            (constraints.maxHeight - verticalPadding) / week.length;
        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(12, 2, 12, 2),
          physics: const NeverScrollableScrollPhysics(),
          itemExtent: itemHeight,
          itemCount: week.length,
          itemBuilder: (context, index) {
            final date = week[index];
            final inMonth =
                date.month == month.month && date.year == month.year;
            final day = data.days[DateTime(date.year, date.month, date.day)];

            return _AttendanceDayCard(
              date: date,
              weekday: (SkoLanguageController.isEnglish ? _weekdayNamesEn : _weekdayNamesJa)[index],
              inMonth: inMonth,
              day: day,
              onTap: () => onDateTap(date),
            );
          },
        );
      },
    );
  }
}

class _AttendanceDayCard extends StatelessWidget {
  const _AttendanceDayCard({
    required this.date,
    required this.weekday,
    required this.inMonth,
    required this.day,
    required this.onTap,
  });

  final DateTime date;
  final String weekday;
  final bool inMonth;
  final WorkerAttendanceDay? day;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final worked = day?.worked == true;
    final colors = Theme.of(context).colorScheme;
    final faded = !inMonth;
    final holidayName = JapanHoliday.name(date);
    final isHoliday = holidayName != null;
    final now = DateTime.now();
    final isToday = date.year == now.year &&
        date.month == now.month &&
        date.day == now.day;

    return Opacity(
      opacity: faded ? 0.42 : 1,
      child: Padding(
        padding: EdgeInsets.zero,
        child: Card(
          margin: EdgeInsets.zero,
          clipBehavior: Clip.none,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.zero,
            child: Card(
              elevation: 0,
              margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: isToday ? colors.primary : colors.outlineVariant,
            width: isToday ? 2.5 : 1,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 5, 10, 5),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                width: 46,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '${date.day}',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w900,
                            color: isHoliday || date.weekday == DateTime.sunday
                                ? colors.error
                                : date.weekday == DateTime.saturday
                                    ? Colors.blue.shade700
                                    : null,
                          ),
                    ),
                    Text(
                      weekday,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: isHoliday || weekday == '日'
                            ? colors.error
                            : weekday == '土'
                                ? Colors.blue.shade700
                                : colors.onSurfaceVariant,
                      ),
                    ),
                    if (holidayName != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        holidayName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: colors.error,
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          height: 1.05,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 5,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      worked ? (day?.siteName ?? SkoLanguageController.tr('現場')) : SkoLanguageController.tr('休み'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 14,
                        color: worked
                            ? colors.onSurface
                            : colors.onSurfaceVariant,
                      ),
                    ),
                    if (worked) ...[
                      const SizedBox(height: 2),
                      Wrap(
                        spacing: 4,
                        runSpacing: 2,
                        children: _tags(day!),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 82,
                child: worked
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            SkoLanguageController.isEnglish ? 'In ${_time(day?.clockIn)}' : '出 ${_time(day?.clockIn)}',
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 11,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            SkoLanguageController.isEnglish ? 'Out ${_time(day?.clockOut)}' : '退 ${_time(day?.clockOut)}',
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      )
                    : Text(
                        SkoLanguageController.tr('休み'),
                        textAlign: TextAlign.right,
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
              ),
            ],
          ),
        ),
            ),
          ),
        ),
      ),
      ),
    );
  }

  List<Widget> _tags(WorkerAttendanceDay day) {
    final tags = <Widget>[];
    if (day.overtimeHours > 0) {
      tags.add(_MiniTag(SkoLanguageController.isEnglish ? 'OT ${_number(day.overtimeHours)}' : '残${_number(day.overtimeHours)}'));
    }
    if (day.earlyHours > 0) {
      tags.add(_MiniTag(SkoLanguageController.isEnglish ? 'Early ${_number(day.earlyHours)}' : '早${_number(day.earlyHours)}'));
    }
    if (day.nightHours > 0) {
      tags.add(_MiniTag(SkoLanguageController.isEnglish ? 'Night ${_number(day.nightHours)}' : '夜${_number(day.nightHours)}'));
    }
    if (day.hasAllowance) {
      final names = day.allowanceNames.isEmpty
          ? <String>[SkoLanguageController.tr('手当')]
          : day.allowanceNames;
      for (final name in names) {
        final unit = day.allowanceUnits[name] ?? '回';
        tags.add(_MiniTag('${name}1$unit'));
      }
    }
    return tags;
  }

  String _time(DateTime? value) {
    if (value == null) return '--:--';
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(value.hour)}:${two(value.minute)}';
  }

  String _number(double value) {
    if (value == value.roundToDouble()) return value.toInt().toString();
    return value
        .toStringAsFixed(2)
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');
  }
}

class _MiniTag extends StatelessWidget {
  const _MiniTag(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: colors.secondaryContainer,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: colors.onSecondaryContainer,
          fontSize: 11,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class WorkerAttendanceMonthPage extends StatefulWidget {
  const WorkerAttendanceMonthPage({
    super.key,
    required this.month,
    required this.data,
    this.workerId,
    this.workerName,
  });

  final DateTime month;
  final WorkerAttendanceMonth data;
  final String? workerId;
  final String? workerName;

  @override
  State<WorkerAttendanceMonthPage> createState() =>
      _WorkerAttendanceMonthPageState();
}

class _WorkerAttendanceMonthPageState
    extends State<WorkerAttendanceMonthPage> {
  final _repository = WorkerAttendanceSheetRepository.maybeCreate();

  Future<void> _openDailyReport(DateTime date) async {
    final repository = _repository;
    if (repository == null) return;
    final target = await repository.findDailyReportForDate(
      date,
      workerId: widget.workerId,
    );
    if (target == null || !mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DailyReportPage(
          initialDate: date,
          initialSiteId: target.siteId,
        ),
      ),
    );
  }

  late DateTime _month;
  late WorkerAttendanceMonth _data;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _month = DateTime(widget.month.year, widget.month.month);
    _data = widget.data;
  }

  Future<void> _changeMonth(int delta) async {
    final repository = _repository;
    if (repository == null || _loading) return;

    final next = DateTime(_month.year, _month.month + delta);
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final data = await repository.loadMonth(
        next,
        workerId: widget.workerId,
      );
      if (!mounted) return;
      setState(() {
        _month = next;
        _data = data;
        _loading = false;
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
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.workerName?.trim().isNotEmpty == true
              ? '${widget.workerName}・${SkoLanguageController.isEnglish ? '${_month.month}/${_month.year}' : '${_month.year}年${_month.month}月'}'
              : (SkoLanguageController.isEnglish
                  ? '${_month.month}/${_month.year}'
                  : '${_month.year}年${_month.month}月'),
        ),
        actions: [
          const SkoNotificationBell(),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 28),
          children: [
            _MonthHeader(
              month: _month,
              onPrevious: _loading ? () {} : () => _changeMonth(-1),
              onNext: _loading ? () {} : () => _changeMonth(1),
            ),
            if (_loading) ...[
              const SizedBox(height: 4),
              const LinearProgressIndicator(),
            ],
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
            ],
            const SizedBox(height: 6),
            _MonthCalendar(
              month: _month,
              data: _data,
              onDateTap: _openDailyReport,
            ),
            const SizedBox(height: 14),
            _MonthlySummary(data: _data),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _loading
                  ? null
                  : () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => WorkerAttendancePrintPreviewPage(
                            month: _month,
                            data: _data,
                          ),
                        ),
                      ),
              icon: const Icon(Icons.print_outlined),
              label: Text(SkoLanguageController.tr('A4印刷プレビュー')),
            ),
          ],
        ),
      ),
    );
  }
}

class _MonthCalendar extends StatelessWidget {
  const _MonthCalendar({
    required this.month,
    required this.data,
    required this.onDateTap,
  });

  final DateTime month;
  final WorkerAttendanceMonth data;
  final ValueChanged<DateTime> onDateTap;

  static const _weekdaysJa = ['月', '火', '水', '木', '金', '土', '日'];
  static const _weekdaysEn = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  List<DateTime> _days() {
    final first = DateTime(month.year, month.month, 1);
    final last = DateTime(month.year, month.month + 1, 0);
    final start = first.subtract(Duration(days: first.weekday - 1));
    final end = last.add(Duration(days: 7 - last.weekday));

    final result = <DateTime>[];
    for (
      var day = start;
      !day.isAfter(end);
      day = day.add(const Duration(days: 1))
    ) {
      result.add(day);
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final days = _days();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          children: [
            GridView.count(
              crossAxisCount: 7,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              childAspectRatio: 1.9,
              children: [
                for (final label in (SkoLanguageController.isEnglish ? _weekdaysEn : _weekdaysJa))
                  Center(
                    child: Text(
                      label,
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        color: label == '日'
                            ? Theme.of(context).colorScheme.error
                            : label == '土'
                                ? Colors.blue.shade700
                                : null,
                      ),
                    ),
                  ),
              ],
            ),
            const Divider(height: 1),
            GridView.count(
              crossAxisCount: 7,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              childAspectRatio: 0.78,
              children: [
                for (final date in days)
                  _MonthCalendarCell(
                    date: date,
                    inMonth: date.month == month.month,
                    day: data.days[DateTime(date.year, date.month, date.day)],
                    onTap: () => onDateTap(date),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MonthCalendarCell extends StatelessWidget {
  const _MonthCalendarCell({
    required this.date,
    required this.inMonth,
    required this.day,
    required this.onTap,
  });

  final DateTime date;
  final bool inMonth;
  final WorkerAttendanceDay? day;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final worked = day?.worked == true;
    final siteName = day?.siteName?.trim() ?? '';
    final shortSite = siteName.isEmpty
        ? ''
        : siteName.characters.take(2).toString();
    final holidayName = JapanHoliday.name(date);
    final isHoliday = holidayName != null;
    final now = DateTime.now();
    final isToday = date.year == now.year &&
        date.month == now.month &&
        date.day == now.day;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Opacity(
        opacity: inMonth ? 1 : 0.35,
        child: Container(
        margin: const EdgeInsets.all(1.5),
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          border: Border.all(
            color: isToday
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).dividerColor,
            width: isToday ? 2.5 : 1,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          children: [
            Align(
              alignment: Alignment.topRight,
              child: Text(
                '${date.day}',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  color: isHoliday || date.weekday == DateTime.sunday
                      ? Theme.of(context).colorScheme.error
                      : date.weekday == DateTime.saturday
                          ? Colors.blue.shade700
                          : null,
                ),
              ),
            ),
            if (holidayName != null)
              Text(
                holidayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontSize: 8,
                  fontWeight: FontWeight.w800,
                  height: 1,
                ),
              ),
            const Spacer(),
            Text(
              worked ? shortSite : '休',
              maxLines: 1,
              overflow: TextOverflow.clip,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w900,
                color: worked
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            if (day?.hasAllowance == true)
              Text(
                (day!.allowanceNames.isEmpty
                        ? const <String>['手当']
                        : day!.allowanceNames)
                    .map((name) => '${name}1${day!.allowanceUnits[name] ?? '回'}')
                    .join(' '),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 8, fontWeight: FontWeight.w900),
              )
            else
              const SizedBox(height: 10),
            const Spacer(),
          ],
        ),
        ),
      ),
    );
  }
}

class _MonthlySummary extends StatelessWidget {
  const _MonthlySummary({required this.data});

  final WorkerAttendanceMonth data;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            if (data.workedDays > 0)
              _SummaryPill(label: SkoLanguageController.tr('出勤'), value: SkoLanguageController.isEnglish ? '${data.workedDays} days' : '${data.workedDays}日'),
            if (data.overtimeHours > 0)
              _SummaryPill(
                label: SkoLanguageController.tr('残業'),
                value: SkoLanguageController.isEnglish ? '${_number(data.overtimeHours)} hours' : '${_number(data.overtimeHours)}時間',
              ),
            if (data.earlyHours > 0)
              _SummaryPill(
                label: SkoLanguageController.tr('早出'),
                value: SkoLanguageController.isEnglish ? '${_number(data.earlyHours)} hours' : '${_number(data.earlyHours)}時間',
              ),
            if (data.nightHours > 0)
              _SummaryPill(
                label: SkoLanguageController.tr('夜間'),
                value: SkoLanguageController.isEnglish ? '${_number(data.nightHours)} hours' : '${_number(data.nightHours)}時間',
              ),
            for (final entry in data.allowanceCounts.entries)
              _SummaryPill(
                label: entry.key,
                value:
                    '${entry.value}${data.allowanceUnits[entry.key] ?? '回'}',
              ),
          ],
        ),
      ),
    );
  }

  static String _number(double value) {
    if (value == value.roundToDouble()) return value.toInt().toString();
    return value
        .toStringAsFixed(2)
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');
  }
}

class _SummaryPill extends StatelessWidget {
  const _SummaryPill({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(
        '$label  $value',
        style: const TextStyle(fontWeight: FontWeight.w800),
      ),
    );
  }
}

class WorkerAttendancePrintPreviewPage extends StatelessWidget {
  const WorkerAttendancePrintPreviewPage({
    super.key,
    required this.month,
    required this.data,
  });

  final DateTime month;
  final WorkerAttendanceMonth data;

  @override
  Widget build(BuildContext context) {
    final rows = data.days.values.toList()
      ..sort((a, b) => a.date.compareTo(b.date));

    return Scaffold(
      appBar: AppBar(title: Text(SkoLanguageController.tr('A4プレビュー'))),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            AspectRatio(
              aspectRatio: 1 / 1.414,
              child: Card(
                child: InteractiveViewer(
                  minScale: 0.8,
                  maxScale: 4,
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          SkoLanguageController.isEnglish
                              ? 'Attendance  ${month.month}/${month.year}'
                              : '出勤表  ${month.year}年${month.month}月',
                          textAlign: TextAlign.center,
                          style: Theme.of(context)
                              .textTheme
                              .titleLarge
                              ?.copyWith(fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 14),
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          children: [
                            if (data.workedDays > 0)
                              Text(SkoLanguageController.isEnglish ? 'Attendance ${data.workedDays} days' : '出勤 ${data.workedDays}日'),
                            if (data.overtimeHours > 0)
                              Text(SkoLanguageController.isEnglish ? 'Overtime ${_number(data.overtimeHours)} hours' : '残業 ${_number(data.overtimeHours)}時間'),
                            if (data.earlyHours > 0)
                              Text(SkoLanguageController.isEnglish ? 'Early ${_number(data.earlyHours)} hours' : '早出 ${_number(data.earlyHours)}時間'),
                            if (data.nightHours > 0)
                              Text(SkoLanguageController.isEnglish ? 'Night ${_number(data.nightHours)} hours' : '夜間 ${_number(data.nightHours)}時間'),
                            for (final entry in data.allowanceCounts.entries)
                              Text(
                                '${entry.key} ${entry.value}${data.allowanceUnits[entry.key] ?? '回'}',
                              ),
                          ],
                        ),
                        const Divider(height: 20),
                        Expanded(
                          child: ListView(
                            physics: const NeverScrollableScrollPhysics(),
                            children: [
                              for (final day in rows)
                                Padding(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 2),
                                  child: Text(
                                    [
                                      '${day.date.month}/${day.date.day}',
                                      day.siteName ?? SkoLanguageController.tr('休み'),
                                      '${_time(day.clockIn)}〜${_time(day.clockOut)}',
                                      if (day.overtimeHours > 0)
                                        '残${_number(day.overtimeHours)}',
                                      if (day.earlyHours > 0)
                                        '早${_number(day.earlyHours)}',
                                      if (day.nightHours > 0)
                                        '夜${_number(day.nightHours)}',
                                      if (day.hasAllowance)
                                        ...(day.allowanceNames.isEmpty
                                            ? const <String>['手当1']
                                            : day.allowanceNames.map(
                                                (name) =>
                                                    '${name}1${day.allowanceUnits[name] ?? ''}',
                                              )),
                                    ].join('  '),
                                    style: const TextStyle(fontSize: 11),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: () => AttendancePdfService.printMonth(
                month,
                data,
                workerName: widget.workerName,
              ),
              icon: const Icon(Icons.print),
              label: Text(SkoLanguageController.tr('印刷')),
            ),
          ],
        ),
      ),
    );
  }

  static String _number(double value) {
    if (value == value.roundToDouble()) return value.toInt().toString();
    return value
        .toStringAsFixed(2)
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');
  }

  static String _time(DateTime? value) {
    if (value == null) return '--:--';
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(value.hour)}:${two(value.minute)}';
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
            const Icon(Icons.cloud_off_outlined, size: 44),
            const SizedBox(height: 12),
            Text(
              SkoLanguageController.tr('出勤表を読み込めませんでした'),
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: Text(SkoLanguageController.tr('再読み込み')),
            ),
          ],
        ),
      ),
    );
  }
}
