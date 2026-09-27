import 'package:flutter/material.dart';

import 'attendance_cloud_repository.dart';
import 'attendance_page.dart';

class PastAttendanceEntryPage extends StatefulWidget {
  const PastAttendanceEntryPage({super.key});

  @override
  State<PastAttendanceEntryPage> createState() => _PastAttendanceEntryPageState();
}

class _PastAttendanceEntryPageState extends State<PastAttendanceEntryPage> {
  final _repository = AttendanceCloudRepository.maybeCreate();
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  bool _saving = false;
  int _savedCount = 0;

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
      for (var i = 0; i < days.length; i += 7) days.sublist(i, i + 7),
    ];
  }

  void _changeMonth(int delta) {
    final candidate = DateTime(_month.year, _month.month + delta);
    final currentMonth = DateTime(DateTime.now().year, DateTime.now().month);
    if (candidate.isAfter(currentMonth)) return;
    setState(() => _month = candidate);
  }

  bool _isPastDay(DateTime day) {
    final today = DateTime.now();
    final normalizedToday = DateTime(today.year, today.month, today.day);
    final normalizedDay = DateTime(day.year, day.month, day.day);
    return normalizedDay.isBefore(normalizedToday);
  }

  String _dateText(DateTime day) =>
      '${day.year.toString().padLeft(4, '0')}/${day.month.toString().padLeft(2, '0')}/${day.day.toString().padLeft(2, '0')}';

  Future<void> _openDay(DateTime day) async {
    if (!_isPastDay(day) || _saving) return;

    final entry = await Navigator.of(context).push<AttendanceEntry>(
      MaterialPageRoute(
        builder: (_) => _PastAttendanceFormPage(date: _dateText(day)),
      ),
    );
    if (entry == null) return;

    final repository = _repository;
    if (repository == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('クラウド接続を確認できません。')),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      await repository.insert(entry.toJson());
      if (!mounted) return;
      setState(() => _savedCount++);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${entry.date} の過去出勤を登録しました')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('登録できませんでした: $error')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final weeks = _weeksForMonth(_month);
    final now = DateTime.now();
    final currentMonth = DateTime(now.year, now.month);
    final canGoNext = _month.isBefore(currentMonth);

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          '過去の出勤を登録',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 4),
              child: Row(
                children: [
                  IconButton(
                    tooltip: '前の月',
                    onPressed: _saving ? null : () => _changeMonth(-1),
                    icon: const Icon(Icons.chevron_left),
                  ),
                  Expanded(
                    child: Text(
                      '${_month.year}年${_month.month}月',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                    ),
                  ),
                  IconButton(
                    tooltip: '次の月',
                    onPressed: _saving || !canGoNext
                        ? null
                        : () => _changeMonth(1),
                    icon: const Icon(Icons.chevron_right),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      const Icon(Icons.history_outlined),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          '1か月分をスクロールして、登録したい過去の日付を押してください。',
                        ),
                      ),
                      if (_savedCount > 0)
                        Text(
                          '登録 $_savedCount件',
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                itemCount: weeks.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, weekIndex) {
                  final week = weeks[weekIndex];
                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(10, 10, 10, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '第${weekIndex + 1}週',
                            style: const TextStyle(fontWeight: FontWeight.w900),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              for (final day in week)
                                Expanded(
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 2),
                                    child: _DayCell(
                                      day: day,
                                      inMonth: day.month == _month.month,
                                      enabled: day.month == _month.month && _isPastDay(day),
                                      onTap: () => _openDay(day),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ],
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
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.inMonth,
    required this.enabled,
    required this.onTap,
  });

  final DateTime day;
  final bool inMonth;
  final bool enabled;
  final VoidCallback onTap;

  static const _weekdays = ['月', '火', '水', '木', '金', '土', '日'];

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        constraints: const BoxConstraints(minHeight: 76),
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: Theme.of(context).dividerColor,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              _weekdays[day.weekday - 1],
              style: TextStyle(
                fontSize: 11,
                color: inMonth
                    ? Theme.of(context).colorScheme.onSurface
                    : Theme.of(context).disabledColor,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${day.day}',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w900,
                color: enabled
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).disabledColor,
              ),
            ),
            const SizedBox(height: 3),
            Icon(
              enabled ? Icons.add_circle_outline : Icons.remove_circle_outline,
              size: 17,
              color: enabled
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).disabledColor,
            ),
          ],
        ),
      ),
    );
  }
}

class _PastAttendanceFormPage extends StatefulWidget {
  const _PastAttendanceFormPage({required this.date});

  final String date;

  @override
  State<_PastAttendanceFormPage> createState() => _PastAttendanceFormPageState();
}

class _PastAttendanceFormPageState extends State<_PastAttendanceFormPage> {
  final _formKey = GlobalKey<FormState>();
  final _worker = TextEditingController();
  final _site = TextEditingController();
  final _manDays = TextEditingController(text: '1');
  final _overtime = TextEditingController(text: '0');
  final _early = TextEditingController(text: '0');
  final _night = TextEditingController(text: '0');
  final _allowance = TextEditingController(text: '0');
  final _notes = TextEditingController();

  @override
  void dispose() {
    for (final controller in [
      _worker,
      _site,
      _manDays,
      _overtime,
      _early,
      _night,
      _allowance,
      _notes,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('${widget.date} の出勤')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: ListTile(
                  leading: const Icon(Icons.event_outlined),
                  title: const Text('登録日'),
                  subtitle: Text(widget.date),
                ),
              ),
              const SizedBox(height: 14),
              _requiredField(_worker, '作業員'),
              const SizedBox(height: 14),
              _requiredField(_site, '現場'),
              const SizedBox(height: 14),
              _numberField(_manDays, '人工'),
              const SizedBox(height: 14),
              _numberField(_overtime, '残業時間'),
              const SizedBox(height: 14),
              _numberField(_early, '早出時間'),
              const SizedBox(height: 14),
              _numberField(_night, '夜間時間'),
              const SizedBox(height: 14),
              TextField(
                controller: _allowance,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: '手当（円）'),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _notes,
                maxLines: 3,
                decoration: const InputDecoration(labelText: '備考'),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: _submit,
                icon: const Icon(Icons.save_outlined),
                label: const Text('この日の出勤を登録'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  TextFormField _requiredField(TextEditingController controller, String label) {
    return TextFormField(
      controller: controller,
      decoration: InputDecoration(labelText: label),
      validator: (value) =>
          value == null || value.trim().isEmpty ? '$labelを入力してください' : null,
    );
  }

  TextFormField _numberField(TextEditingController controller, String label) {
    return TextFormField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(labelText: label),
      validator: (value) {
        final number = double.tryParse(value ?? '');
        if (number == null || number < 0) return '0以上の数値を入力してください';
        return null;
      },
    );
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    Navigator.of(context).pop(
      AttendanceEntry(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        date: widget.date,
        workerName: _worker.text.trim(),
        siteName: _site.text.trim(),
        manDays: double.parse(_manDays.text),
        overtimeHours: double.parse(_overtime.text),
        earlyHours: double.parse(_early.text),
        nightHours: double.parse(_night.text),
        allowanceYen: int.tryParse(_allowance.text) ?? 0,
        notes: _notes.text.trim(),
      ),
    );
  }
}
