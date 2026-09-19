import 'package:flutter/material.dart';

import 'worker_attendance_sheet_repository.dart';

class WorkerAttendanceSheetPage extends StatefulWidget {
  const WorkerAttendanceSheetPage({super.key});

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
        _error = 'クラウド接続を確認できません。';
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final data = await repository.loadMonth(_month);
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
        title: const Text(
          '出勤表',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        actions: [
          IconButton(
            tooltip: '月間カレンダー',
            onPressed: _loading ? null : _showMonthCalendar,
            icon: const Icon(Icons.calendar_month_outlined),
          ),
          IconButton(
            tooltip: 'お知らせ',
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('お知らせ画面は共通通知センターに接続予定です')),
              );
            },
            icon: const Badge(
              isLabelVisible: false,
              child: Icon(Icons.notifications_outlined),
            ),
          ),
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
            tooltip: '前の月',
            onPressed: onPrevious,
            icon: const Icon(Icons.chevron_left),
          ),
          Expanded(
            child: Text(
              '${month.year}年${month.month}月',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
            ),
          ),
          IconButton(
            tooltip: '次の月',
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
            label: Text('${index + 1}週'),
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
  });

  final DateTime month;
  final List<DateTime> week;
  final WorkerAttendanceMonth data;

  static const _weekdayNames = ['月', '火', '水', '木', '金', '土', '日'];

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 24),
      itemCount: week.length,
      separatorBuilder: (_, __) => const SizedBox(height: 7),
      itemBuilder: (context, index) {
        final date = week[index];
        final inMonth = date.month == month.month && date.year == month.year;
        final day = data.days[DateTime(date.year, date.month, date.day)];

        return _AttendanceDayCard(
          date: date,
          weekday: _weekdayNames[index],
          inMonth: inMonth,
          day: day,
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
  });

  final DateTime date;
  final String weekday;
  final bool inMonth;
  final WorkerAttendanceDay? day;

  @override
  Widget build(BuildContext context) {
    final worked = day?.worked == true;
    final colors = Theme.of(context).colorScheme;
    final faded = !inMonth;

    return Opacity(
      opacity: faded ? 0.42 : 1,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                width: 52,
                child: Column(
                  children: [
                    Text(
                      '${date.day}',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                    ),
                    Text(
                      weekday,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: weekday == '日'
                            ? colors.error
                            : colors.onSurfaceVariant,
                      ),
                    ),
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
                      worked ? (day?.siteName ?? '現場') : '休み',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 15,
                        color: worked
                            ? colors.onSurface
                            : colors.onSurfaceVariant,
                      ),
                    ),
                    if (worked) ...[
                      const SizedBox(height: 5),
                      Wrap(
                        spacing: 4,
                        runSpacing: 4,
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
                            '出 ${_time(day?.clockIn)}',
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '退 ${_time(day?.clockOut)}',
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      )
                    : const Text(
                        '休み',
                        textAlign: TextAlign.right,
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _tags(WorkerAttendanceDay day) {
    final tags = <Widget>[];
    if (day.overtimeHours > 0) {
      tags.add(_MiniTag('残${_number(day.overtimeHours)}'));
    }
    if (day.earlyHours > 0) {
      tags.add(_MiniTag('早${_number(day.earlyHours)}'));
    }
    if (day.nightHours > 0) {
      tags.add(_MiniTag('夜${_number(day.nightHours)}'));
    }
    if (day.allowanceYen > 0) {
      tags.add(const _MiniTag('手1'));
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

class WorkerAttendanceMonthPage extends StatelessWidget {
  const WorkerAttendanceMonthPage({
    super.key,
    required this.month,
    required this.data,
  });

  final DateTime month;
  final WorkerAttendanceMonth data;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${month.year}年${month.month}月'),
        actions: [
          IconButton(
            tooltip: 'お知らせ',
            onPressed: () {},
            icon: const Icon(Icons.notifications_outlined),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 28),
          children: [
            _MonthCalendar(month: month, data: data),
            const SizedBox(height: 14),
            _MonthlySummary(data: data),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => WorkerAttendancePrintPreviewPage(
                    month: month,
                    data: data,
                  ),
                ),
              ),
              icon: const Icon(Icons.print_outlined),
              label: const Text('A4印刷プレビュー'),
            ),
          ],
        ),
      ),
    );
  }
}

class _MonthCalendar extends StatelessWidget {
  const _MonthCalendar({required this.month, required this.data});

  final DateTime month;
  final WorkerAttendanceMonth data;

  static const _weekdays = ['月', '火', '水', '木', '金', '土', '日'];

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
                for (final label in _weekdays)
                  Center(
                    child: Text(
                      label,
                      style: const TextStyle(fontWeight: FontWeight.w900),
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
  });

  final DateTime date;
  final bool inMonth;
  final WorkerAttendanceDay? day;

  @override
  Widget build(BuildContext context) {
    final worked = day?.worked == true;
    final siteName = day?.siteName?.trim() ?? '';
    final shortSite = siteName.isEmpty
        ? ''
        : siteName.characters.take(2).toString();

    return Opacity(
      opacity: inMonth ? 1 : 0.35,
      child: Container(
        margin: const EdgeInsets.all(1.5),
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          border: Border.all(color: Theme.of(context).dividerColor),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          children: [
            Align(
              alignment: Alignment.topRight,
              child: Text(
                '${date.day}',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                ),
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
            const Spacer(),
          ],
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
            _SummaryPill(label: '出勤', value: '${data.workedDays}日'),
            _SummaryPill(
              label: '残業',
              value: '${_number(data.overtimeHours)}時間',
            ),
            _SummaryPill(
              label: '早出',
              value: '${_number(data.earlyHours)}時間',
            ),
            _SummaryPill(
              label: '夜間',
              value: '${_number(data.nightHours)}時間',
            ),
            if (data.allowanceYen > 0)
              _SummaryPill(
                label: '手当',
                value: '¥${data.allowanceYen}',
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
      appBar: AppBar(title: const Text('A4プレビュー')),
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
                          '出勤表  ${month.year}年${month.month}月',
                          textAlign: TextAlign.center,
                          style: Theme.of(context)
                              .textTheme
                              .titleLarge
                              ?.copyWith(fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 14),
                        Text(
                          '出勤 ${data.workedDays}日 / 残業 ${data.overtimeHours}時間',
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
                                    '${day.date.month}/${day.date.day}  '
                                    '${day.siteName ?? '休み'}  '
                                    '${_time(day.clockIn)}〜${_time(day.clockOut)}',
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
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('実機ではiOS印刷ダイアログへ接続します'),
                  ),
                );
              },
              icon: const Icon(Icons.print),
              label: const Text('印刷'),
            ),
          ],
        ),
      ),
    );
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
            const Text(
              '出勤表を読み込めませんでした',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('再読み込み'),
            ),
          ],
        ),
      ),
    );
  }
}
