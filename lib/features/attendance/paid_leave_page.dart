import 'package:flutter/material.dart';

import '../notifications/notification_bell.dart';
import 'paid_leave_repository.dart';

class PaidLeavePage extends StatefulWidget {
  const PaidLeavePage({super.key});

  @override
  State<PaidLeavePage> createState() => _PaidLeavePageState();
}

class _PaidLeavePageState extends State<PaidLeavePage> {
  final _repository = PaidLeaveRepository.maybeCreate();
  final _reason = TextEditingController();
  final Set<DateTime> _selected = <DateTime>{};

  late DateTime _month;
  PaidLeaveSummary? _summary;
  List<PaidLeaveRequestRow> _requests = const [];
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _month = DateTime(now.year, now.month);
    _load();
  }

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final repository = _repository;
    if (repository == null) {
      setState(() {
        _loading = false;
        _error = '有給申請を利用できません。';
      });
      return;
    }
    try {
      final values = await Future.wait([
        repository.loadSummary(),
        repository.loadMyRequests(),
      ]);
      if (!mounted) return;
      setState(() {
        _summary = values[0] as PaidLeaveSummary;
        _requests = values[1] as List<PaidLeaveRequestRow>;
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

  void _changeMonth(int delta) {
    setState(() {
      _month = DateTime(_month.year, _month.month + delta);
    });
  }

  Future<void> _submit() async {
    final repository = _repository;
    if (repository == null || _selected.isEmpty || _saving) return;

    setState(() => _saving = true);
    try {
      await repository.submit(
        dates: _selected,
        reason: _reason.text,
      );
      if (!mounted) return;
      setState(() {
        _selected.clear();
        _reason.clear();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('有給申請を送信しました')),
      );
      await _load();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('有給申請を送信できませんでした: $error')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final summary = _summary;
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          '有給申請',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        actions: const [SkoNotificationBell()],
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(child: Text(_error!, textAlign: TextAlign.center))
                : ListView(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
                    children: [
                      if (summary != null)
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Row(
                              children: [
                                Expanded(
                                  child: _Count(
                                    label: '付与',
                                    value: summary.grantedDays,
                                  ),
                                ),
                                Expanded(
                                  child: _Count(
                                    label: '使用',
                                    value: summary.usedDays,
                                  ),
                                ),
                                Expanded(
                                  child: _Count(
                                    label: '残り',
                                    value: summary.remainingDays,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          IconButton(
                            onPressed: () => _changeMonth(-1),
                            icon: const Icon(Icons.chevron_left),
                          ),
                          Expanded(
                            child: Text(
                              '${_month.year}年${_month.month}月',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 19,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: () => _changeMonth(1),
                            icon: const Icon(Icons.chevron_right),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      _MultiDateCalendar(
                        month: _month,
                        selected: _selected,
                        onChanged: (date, selected) {
                          setState(() {
                            final key =
                                DateTime(date.year, date.month, date.day);
                            if (selected) {
                              _selected.add(key);
                            } else {
                              _selected.remove(key);
                            }
                          });
                        },
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _reason,
                        maxLines: 2,
                        decoration: const InputDecoration(
                          labelText: '理由・メモ（任意）',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed:
                            _selected.isEmpty || _saving ? null : _submit,
                        icon: const Icon(Icons.send_outlined),
                        label: Text(
                          _saving
                              ? '申請中…'
                              : '選択した${_selected.length}日を申請',
                        ),
                      ),
                      const SizedBox(height: 20),
                      const Text(
                        '申請履歴',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (_requests.isEmpty)
                        const Text('申請履歴はありません')
                      else
                        for (final row in _requests)
                          Card(
                            child: ListTile(
                              title: Text(_date(row.leaveDate)),
                              subtitle:
                                  row.reason.isEmpty ? null : Text(row.reason),
                              trailing: Text(
                                _status(row.status),
                                style: TextStyle(
                                  fontWeight: FontWeight.w900,
                                  color: row.status == 'approved'
                                      ? Theme.of(context).colorScheme.primary
                                      : row.status == 'rejected'
                                          ? Theme.of(context).colorScheme.error
                                          : null,
                                ),
                              ),
                            ),
                          ),
                    ],
                  ),
      ),
    );
  }

  static String _date(DateTime value) =>
      '${value.year}/${value.month.toString().padLeft(2, '0')}/${value.day.toString().padLeft(2, '0')}';

  static String _status(String value) => switch (value) {
        'approved' => '承認済み',
        'rejected' => '却下',
        'cancelled' => '取消',
        _ => '承認待ち',
      };
}

class _MultiDateCalendar extends StatelessWidget {
  const _MultiDateCalendar({
    required this.month,
    required this.selected,
    required this.onChanged,
  });

  final DateTime month;
  final Set<DateTime> selected;
  final void Function(DateTime date, bool selected) onChanged;

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final todayDate = DateTime(today.year, today.month, today.day);
    final days = DateUtils.getDaysInMonth(month.year, month.month);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (var day = 1; day <= days; day++)
              Builder(
                builder: (context) {
                  final date = DateTime(month.year, month.month, day);
                  final enabled = date.isAfter(todayDate);
                  return FilterChip(
                    label: Text('$day日'),
                    selected: selected.contains(date),
                    onSelected:
                        enabled ? (value) => onChanged(date, value) : null,
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _Count extends StatelessWidget {
  const _Count({required this.label, required this.value});

  final String label;
  final double value;

  @override
  Widget build(BuildContext context) {
    final text = value == value.roundToDouble()
        ? value.toInt().toString()
        : value.toStringAsFixed(1);
    return Column(
      children: [
        Text(label),
        const SizedBox(height: 3),
        Text(
          '$text日',
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }
}
