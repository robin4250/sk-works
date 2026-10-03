import 'package:flutter/material.dart';

import 'paid_leave_repository.dart';

class PaidLeaveCorrectionPage extends StatefulWidget {
  const PaidLeaveCorrectionPage({super.key});

  @override
  State<PaidLeaveCorrectionPage> createState() =>
      _PaidLeaveCorrectionPageState();
}

class _PaidLeaveCorrectionPageState extends State<PaidLeaveCorrectionPage> {
  final _repository = PaidLeaveRepository.maybeCreate();
  final _reason = TextEditingController();
  final Set<DateTime> _selected = <DateTime>{};
  late DateTime _month;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _month = DateTime(now.year, now.month);
  }

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  void _changeMonth(int delta) {
    final next = DateTime(_month.year, _month.month + delta);
    final today = DateTime.now();
    final currentMonth = DateTime(today.year, today.month);
    if (next.isAfter(currentMonth)) return;
    setState(() => _month = next);
  }

  Future<void> _submit() async {
    final repository = _repository;
    if (repository == null || _selected.isEmpty || _saving) return;
    setState(() => _saving = true);
    try {
      await repository.submitRetrospective(
        dates: _selected,
        reason: _reason.text,
      );
      if (!mounted) return;
      Navigator.of(context).pop(_selected.length);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('有給への勤務修正を申請できませんでした: $error')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final todayDate = DateTime(today.year, today.month, today.day);
    final days = DateUtils.getDaysInMonth(_month.year, _month.month);
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          '休み→有給',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
          children: [
            const Card(
              child: Padding(
                padding: EdgeInsets.all(14),
                child: Text(
                  '今日または過去の「休み」を有給へ変更申請します。'
                  'すでに出勤データがある日は、先に通常の勤務修正を行ってください。',
                ),
              ),
            ),
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
                      fontWeight: FontWeight.w900,
                      fontSize: 18,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => _changeMonth(1),
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (var day = 1; day <= days; day++)
                      Builder(
                        builder: (context) {
                          final date = DateTime(_month.year, _month.month, day);
                          final enabled = !date.isAfter(todayDate);
                          return FilterChip(
                            label: Text('$day日'),
                            selected: _selected.contains(date),
                            onSelected: enabled
                                ? (value) => setState(() {
                                      if (value) {
                                        _selected.add(date);
                                      } else {
                                        _selected.remove(date);
                                      }
                                    })
                                : null,
                          );
                        },
                      ),
                  ],
                ),
              ),
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
              onPressed: _selected.isEmpty || _saving ? null : _submit,
              icon: const Icon(Icons.send_outlined),
              label: Text(
                _saving
                    ? '申請中…'
                    : '選択した${_selected.length}日を有給へ勤務修正申請',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
