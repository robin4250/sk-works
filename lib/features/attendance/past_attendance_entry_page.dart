import 'package:flutter/material.dart';

import '../daily_reports/daily_report_page.dart';
import 'attendance_cloud_repository.dart';
import 'attendance_page.dart';

class PastAttendanceEntryPage extends StatefulWidget {
  const PastAttendanceEntryPage({super.key});

  @override
  State<PastAttendanceEntryPage> createState() => _PastAttendanceEntryPageState();
}

class _PastAttendanceEntryPageState extends State<PastAttendanceEntryPage> {
  final _repository = AttendanceCloudRepository.maybeCreate();
  final Map<String, _PastDayDraft> _drafts = {};

  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  List<String> _workerNames = const [];
  List<String> _siteNames = const [];
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadChoices();
  }

  Future<void> _loadChoices() async {
    final repository = _repository;
    if (repository == null) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'クラウド接続を確認できません。';
      });
      return;
    }
    try {
      final values = await Future.wait([
        repository.loadActiveWorkerNames(),
        repository.loadSiteNames(),
      ]);
      if (!mounted) return;
      setState(() {
        _workerNames = values[0];
        _siteNames = values[1];
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  List<List<DateTime>> _weeksForMonth(DateTime month) {
    final first = DateTime(month.year, month.month, 1);
    final last = DateTime(month.year, month.month + 1, 0);
    final gridStart = first.subtract(Duration(days: first.weekday - 1));
    final gridEnd = last.add(Duration(days: 7 - last.weekday));
    final days = <DateTime>[];
    for (var day = gridStart;
        !day.isAfter(gridEnd);
        day = day.add(const Duration(days: 1))) {
      days.add(day);
    }
    return [for (var i = 0; i < days.length; i += 7) days.sublist(i, i + 7)];
  }

  bool _isPastDay(DateTime day) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return DateTime(day.year, day.month, day.day).isBefore(today);
  }

  String _key(DateTime day) =>
      '${day.year.toString().padLeft(4, '0')}/${day.month.toString().padLeft(2, '0')}/${day.day.toString().padLeft(2, '0')}';

  String _weekday(DateTime day) => const ['月', '火', '水', '木', '金', '土', '日'][day.weekday - 1];

  void _changeMonth(int delta) {
    final candidate = DateTime(_month.year, _month.month + delta);
    final current = DateTime(DateTime.now().year, DateTime.now().month);
    if (candidate.isAfter(current)) return;
    setState(() => _month = candidate);
  }

  _PastDayDraft _draftFor(DateTime day) =>
      _drafts.putIfAbsent(_key(day), () => _PastDayDraft(date: _key(day)));

  void _toggleDay(DateTime day, bool selected) {
    final draft = _draftFor(day);
    setState(() => draft.selected = selected);
  }

  Future<void> _editDetails(DateTime day) async {
    final draft = _draftFor(day);
    final overtime = TextEditingController(text: _number(draft.overtimeHours));
    final early = TextEditingController(text: _number(draft.earlyHours));
    final night = TextEditingController(text: _number(draft.nightHours));
    final allowance = TextEditingController(text: draft.allowanceYen.toString());
    final notes = TextEditingController(text: draft.notes);
    var siteName = draft.siteName.isNotEmpty
        ? draft.siteName
        : (_siteNames.isNotEmpty ? _siteNames.first : '');

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: EdgeInsets.fromLTRB(
            16,
            0,
            16,
            20 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('${draft.date} の詳細', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  initialValue: siteName.isEmpty ? null : siteName,
                  decoration: const InputDecoration(labelText: '現場'),
                  items: [for (final name in _siteNames) DropdownMenuItem(value: name, child: Text(name))],
                  onChanged: (value) => setSheetState(() => siteName = value ?? ''),
                ),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(child: _numberField(overtime, '残業(h)')),
                  const SizedBox(width: 8),
                  Expanded(child: _numberField(early, '早出(h)')),
                  const SizedBox(width: 8),
                  Expanded(child: _numberField(night, '夜勤(h)')),
                ]),
                const SizedBox(height: 12),
                TextField(
                  controller: allowance,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: '手当（円）'),
                ),
                const SizedBox(height: 12),
                TextField(controller: notes, maxLines: 2, decoration: const InputDecoration(labelText: '備考')),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: siteName.isEmpty ? null : () => Navigator.pop(sheetContext, true),
                  child: const Text('確定'),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (confirmed == true) {
      setState(() {
        draft
          ..selected = true
          ..siteName = siteName
          ..overtimeHours = double.tryParse(overtime.text) ?? 0
          ..earlyHours = double.tryParse(early.text) ?? 0
          ..nightHours = double.tryParse(night.text) ?? 0
          ..allowanceYen = int.tryParse(allowance.text) ?? 0
          ..notes = notes.text.trim();
      });
    }
    for (final controller in [overtime, early, night, allowance, notes]) {
      controller.dispose();
    }
  }

  Widget _numberField(TextEditingController controller, String label) => TextField(
        controller: controller,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(labelText: label),
      );

  Future<void> _selectMembers(DateTime day) async {
    final draft = _draftFor(day);
    final selected = Set<String>.from(draft.workerNames);
    final result = await showModalBottomSheet<Set<String>>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: SizedBox(
            height: MediaQuery.sizeOf(context).height * .72,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Row(
                    children: [
                      Expanded(child: Text('${draft.date} メンバー', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900))),
                      TextButton(
                        onPressed: () => setSheetState(() {
                          selected
                            ..clear()
                            ..addAll(_workerNames);
                        }),
                        child: const Text('全員'),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: ListView(
                    children: [
                      for (final name in _workerNames)
                        CheckboxListTile(
                          value: selected.contains(name),
                          title: Text(name),
                          onChanged: (value) => setSheetState(() {
                            if (value == true) {
                              selected.add(name);
                            } else {
                              selected.remove(name);
                            }
                          }),
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: selected.isEmpty ? null : () => Navigator.pop(sheetContext, selected),
                      child: Text('${selected.length}人を確定'),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (result != null) {
      setState(() {
        draft
          ..selected = true
          ..workerNames = result;
      });
    }
  }

  Future<void> _submit() async {
    final repository = _repository;
    if (repository == null || _saving) return;
    final selected = _drafts.values.where((draft) => draft.selected).toList()
      ..sort((a, b) => a.date.compareTo(b.date));
    if (selected.isEmpty) {
      _message('登録する日付にチェックを入れてください。');
      return;
    }
    for (final draft in selected) {
      if (draft.workerNames.isEmpty) {
        _message('${draft.date} のメンバーを選択してください。');
        return;
      }
      if (draft.siteName.isEmpty) {
        _message('${draft.date} の現場・残業・手当を設定してください。');
        return;
      }
    }

    setState(() => _saving = true);
    var count = 0;
    try {
      for (final draft in selected) {
        for (final workerName in draft.workerNames) {
          final entry = AttendanceEntry(
            id: '${DateTime.now().microsecondsSinceEpoch}-$count',
            date: draft.date,
            workerName: workerName,
            siteName: draft.siteName,
            manDays: 1,
            overtimeHours: draft.overtimeHours,
            earlyHours: draft.earlyHours,
            nightHours: draft.nightHours,
            allowanceYen: draft.allowanceYen,
            notes: draft.notes,
          );
          await repository.insert(entry.toJson());
          count++;
        }
      }
      if (!mounted) return;
      await _showCompleted(selected.first.date, selected.length, count);
    } catch (error) {
      if (!mounted) return;
      _message('登録できませんでした: $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _showCompleted(String firstDate, int dayCount, int entryCount) async {
    final date = _parseDate(firstDate);
    final openReport = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('おまとめ出勤を登録しました'),
        content: Text(
          '$dayCount日分・$entryCount件の出勤を登録しました。\n\n'
          '今回まとめて登録した日付のうち、どれか1日の日報を開いて責任者サインをもらうと、今回まとめた対象日すべてに同じサインが反映されます。\n\n'
          'サインする人が今いない場合は、後から日報を開いてサインできます。\n\n'
          '責任者サインが完了すると、今回登録した出勤が確定します。',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('あとで')),
          FilledButton.icon(
            onPressed: () => Navigator.pop(dialogContext, true),
            icon: const Icon(Icons.description_outlined),
            label: const Text('日報を開く'),
          ),
        ],
      ),
    );
    if (openReport == true && mounted) {
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => DailyReportPage(initialDate: date)),
      );
    }
    if (mounted) Navigator.of(context).pop(true);
  }

  DateTime _parseDate(String value) {
    final parts = value.split('/').map(int.parse).toList();
    return DateTime(parts[0], parts[1], parts[2]);
  }

  void _message(String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  @override
  Widget build(BuildContext context) {
    final weeks = _weeksForMonth(_month);
    final currentMonth = DateTime(DateTime.now().year, DateTime.now().month);
    final selectedCount = _drafts.values.where((draft) => draft.selected).length;

    return Scaffold(
      appBar: AppBar(title: const Text('過去の出勤を登録', style: TextStyle(fontWeight: FontWeight.w900))),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: FilledButton.icon(
          onPressed: _loading || _saving ? null : _submit,
          icon: _saving
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.save_outlined),
          label: Text(_saving ? '登録中…' : '選択した$selectedCount日を登録'),
        ),
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!, textAlign: TextAlign.center)))
                : Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
                        child: Row(
                          children: [
                            IconButton(onPressed: _saving ? null : () => _changeMonth(-1), icon: const Icon(Icons.chevron_left)),
                            Expanded(
                              child: Text('${_month.year}年${_month.month}月', textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
                            ),
                            IconButton(
                              onPressed: _saving || !_month.isBefore(currentMonth) ? null : () => _changeMonth(1),
                              icon: const Icon(Icons.chevron_right),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: ListView(
                          padding: const EdgeInsets.fromLTRB(8, 4, 8, 16),
                          children: [
                            for (var weekIndex = 0; weekIndex < weeks.length; weekIndex++) ...[
                              Padding(
                                padding: const EdgeInsets.fromLTRB(8, 10, 8, 4),
                                child: Text('第${weekIndex + 1}週', style: const TextStyle(fontWeight: FontWeight.w900)),
                              ),
                              for (final day in weeks[weekIndex])
                                if (day.month == _month.month)
                                  _DayRow(
                                    day: day,
                                    enabled: _isPastDay(day),
                                    draft: _drafts[_key(day)],
                                    weekday: _weekday(day),
                                    onSelected: (value) => _toggleDay(day, value),
                                    onDetails: () => _editDetails(day),
                                    onMembers: () => _selectMembers(day),
                                  ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
      ),
    );
  }

  String _number(double value) => value == value.roundToDouble() ? value.toInt().toString() : value.toStringAsFixed(1);
}

class _DayRow extends StatelessWidget {
  const _DayRow({
    required this.day,
    required this.enabled,
    required this.draft,
    required this.weekday,
    required this.onSelected,
    required this.onDetails,
    required this.onMembers,
  });

  final DateTime day;
  final bool enabled;
  final _PastDayDraft? draft;
  final String weekday;
  final ValueChanged<bool> onSelected;
  final VoidCallback onDetails;
  final VoidCallback onMembers;

  @override
  Widget build(BuildContext context) {
    final selected = draft?.selected == true;
    final hasDetails = draft?.siteName.isNotEmpty == true;
    final memberCount = draft?.workerNames.length ?? 0;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 3),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        child: Row(
          children: [
            Checkbox(value: selected, onChanged: enabled ? (value) => onSelected(value == true) : null),
            SizedBox(
              width: 74,
              child: Text(
                '${day.month}/${day.day}（$weekday）',
                style: TextStyle(fontWeight: FontWeight.w900, color: day.weekday == DateTime.sunday ? Colors.red : null),
              ),
            ),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: enabled ? onDetails : null,
                icon: const Icon(Icons.tune, size: 18),
                label: Text(hasDetails ? '${draft!.siteName}・残業/手当' : '現場・残業・手当'),
              ),
            ),
            const SizedBox(width: 6),
            IconButton.filledTonal(
              tooltip: 'メンバー選択',
              onPressed: enabled ? onMembers : null,
              icon: memberCount == 0 ? const Icon(Icons.group_add_outlined) : Badge(label: Text('$memberCount'), child: const Icon(Icons.groups_outlined)),
            ),
          ],
        ),
      ),
    );
  }
}

class _PastDayDraft {
  _PastDayDraft({required this.date});

  final String date;
  bool selected = false;
  Set<String> workerNames = <String>{};
  String siteName = '';
  double overtimeHours = 0;
  double earlyHours = 0;
  double nightHours = 0;
  int allowanceYen = 0;
  String notes = '';
}
