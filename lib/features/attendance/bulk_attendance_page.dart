import 'package:flutter/material.dart';

import 'attendance_cloud_repository.dart';

class BulkAttendancePage extends StatefulWidget {
  const BulkAttendancePage({super.key, required this.repository});

  final AttendanceCloudRepository repository;

  @override
  State<BulkAttendancePage> createState() => _BulkAttendancePageState();
}

class _BulkAttendancePageState extends State<BulkAttendancePage> {
  final _selectedDays = <int>{};
  final _selectedWorkers = <String>{};
  List<String> _workers = const [];
  List<String> _sites = const [];
  String? _site;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  late DateTime _month;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _month = DateTime(now.year, now.month);
    _loadLookups();
  }

  Future<void> _loadLookups() async {
    try {
      final values = await Future.wait([
        widget.repository.loadActiveWorkerNames(),
        widget.repository.loadSiteNames(),
      ]);
      if (!mounted) return;
      setState(() {
        _workers = values[0];
        _sites = values[1];
        _site = _sites.isEmpty ? null : _sites.first;
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

  int get _daysInMonth => DateUtils.getDaysInMonth(_month.year, _month.month);

  String _dateText(int day) =>
      '${_month.year.toString().padLeft(4, '0')}/${_month.month.toString().padLeft(2, '0')}/${day.toString().padLeft(2, '0')}';

  void _changeMonth(int delta) {
    setState(() {
      _month = DateTime(_month.year, _month.month + delta);
      _selectedDays.clear();
    });
  }

  Future<void> _save() async {
    if (_site == null || _site!.isEmpty) {
      _show('現場を選択してください。');
      return;
    }
    if (_selectedDays.isEmpty) {
      _show('日付を1日以上選択してください。');
      return;
    }
    if (_selectedWorkers.isEmpty) {
      _show('作業員を1人以上選択してください。');
      return;
    }

    final records = <Map<String, dynamic>>[];
    final days = _selectedDays.toList()..sort();
    final workers = _selectedWorkers.toList()..sort();
    for (final day in days) {
      for (final worker in workers) {
        records.add({
          'date': _dateText(day),
          'workerName': worker,
          'siteName': _site,
          'manDays': 1.0,
          'overtimeHours': 0.0,
          'earlyHours': 0.0,
          'nightHours': 0.0,
          'allowanceYen': 0,
          'notes': '',
        });
      }
    }

    setState(() => _saving = true);
    try {
      final saved = await widget.repository.insertMany(records);
      if (!mounted) return;
      Navigator.of(context).pop(saved.length);
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      _show('一括登録できませんでした: $error');
    }
  }

  void _show(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('おまとめ出勤')),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: FilledButton.icon(
          onPressed: _loading || _saving ? null : _save,
          icon: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.done_all),
          label: Text(_saving ? '登録中…' : 'まとめて登録'),
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
                          const SizedBox(height: 16),
                          FilledButton(
                            onPressed: () {
                              setState(() {
                                _loading = true;
                                _error = null;
                              });
                              _loadLookups();
                            },
                            child: const Text('再試行'),
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                    children: [
                      Row(
                        children: [
                          IconButton(
                            tooltip: '前の月',
                            onPressed: () => _changeMonth(-1),
                            icon: const Icon(Icons.chevron_left),
                          ),
                          Expanded(
                            child: Text(
                              '${_month.year}年${_month.month}月',
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                            ),
                          ),
                          IconButton(
                            tooltip: '次の月',
                            onPressed: () => _changeMonth(1),
                            icon: const Icon(Icons.chevron_right),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (var day = 1; day <= _daysInMonth; day++)
                                FilterChip(
                                  label: Text('$day日'),
                                  selected: _selectedDays.contains(day),
                                  onSelected: (selected) {
                                    setState(() {
                                      if (selected) {
                                        _selectedDays.add(day);
                                      } else {
                                        _selectedDays.remove(day);
                                      }
                                    });
                                  },
                                ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<String>(
                        value: _site,
                        decoration: const InputDecoration(
                          labelText: '現場',
                          border: OutlineInputBorder(),
                        ),
                        items: _sites
                            .map((site) => DropdownMenuItem(value: site, child: Text(site)))
                            .toList(growable: false),
                        onChanged: (value) => setState(() => _site = value),
                      ),
                      const SizedBox(height: 16),
                      Text('作業員（複数選択）', style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 8),
                      if (_workers.isEmpty)
                        const Text('登録可能な作業員がいません。')
                      else
                        Card(
                          child: Column(
                            children: [
                              for (final worker in _workers)
                                CheckboxListTile(
                                  value: _selectedWorkers.contains(worker),
                                  title: Text(worker),
                                  controlAffinity: ListTileControlAffinity.leading,
                                  onChanged: (selected) {
                                    setState(() {
                                      if (selected == true) {
                                        _selectedWorkers.add(worker);
                                      } else {
                                        _selectedWorkers.remove(worker);
                                      }
                                    });
                                  },
                                ),
                            ],
                          ),
                        ),
                      const SizedBox(height: 12),
                      Text(
                        '選択: ${_selectedDays.length}日 × ${_selectedWorkers.length}人 = ${_selectedDays.length * _selectedWorkers.length}件',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 8),
                      const Text('残業・早出・夜勤・手当と共通サインは次の実装段階で、日ごとに編集できるよう追加します。'),
                    ],
                  ),
      ),
    );
  }
}
