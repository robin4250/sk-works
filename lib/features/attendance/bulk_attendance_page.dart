import 'package:flutter/material.dart';

import '../daily_reports/signature_capture_page.dart';
import 'attendance_cloud_repository.dart';
import 'past_attendance_request_repository.dart';

class BulkAttendancePage extends StatefulWidget {
  const BulkAttendancePage({super.key, required this.repository});

  final AttendanceCloudRepository repository;

  @override
  State<BulkAttendancePage> createState() => _BulkAttendancePageState();
}

class _BulkAttendancePageState extends State<BulkAttendancePage> {
  final _approvalRepository = PastAttendanceRequestRepository.maybeCreate();
  final _selectedDays = <int>{};
  final _selectedWorkers = <String>{};
  final _dayDetails = <int, _BulkDayDetails>{};
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

  @override
  void dispose() {
    for (final details in _dayDetails.values) {
      details.dispose();
    }
    super.dispose();
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
    final next = DateTime(_month.year, _month.month + delta);
    final now = DateTime.now();
    final currentMonth = DateTime(now.year, now.month);
    if (next.isAfter(currentMonth)) return;
    setState(() {
      _month = next;
      _selectedDays.clear();
      for (final details in _dayDetails.values) {
        details.dispose();
      }
      _dayDetails.clear();
    });
  }

  void _setDaySelected(int day, bool selected) {
    setState(() {
      if (selected) {
        _selectedDays.add(day);
        _dayDetails.putIfAbsent(day, _BulkDayDetails.new);
      } else {
        _selectedDays.remove(day);
        _dayDetails.remove(day)?.dispose();
      }
    });
  }

  double _parseHours(TextEditingController controller, String label, int day) {
    final text = controller.text.trim();
    if (text.isEmpty) return 0;
    final value = double.tryParse(text);
    if (value == null || value < 0) {
      throw FormatException('$day日の$labelは0以上の数値で入力してください。');
    }
    return value;
  }

  int _parseAllowance(TextEditingController controller, int day) {
    final text = controller.text.trim();
    if (text.isEmpty) return 0;
    final value = int.tryParse(text.replaceAll(',', ''));
    if (value == null || value < 0) {
      throw FormatException('$day日の手当は0以上の整数で入力してください。');
    }
    return value;
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

    try {
      for (final day in days) {
        final details = _dayDetails.putIfAbsent(day, _BulkDayDetails.new);
        final overtimeHours = _parseHours(details.overtime, '残業', day);
        final earlyHours = _parseHours(details.early, '早出', day);
        final nightHours = _parseHours(details.night, '夜勤', day);
        final allowanceYen = _parseAllowance(details.allowance, day);

        for (final worker in workers) {
          records.add({
            'date': _dateText(day),
            'workerName': worker,
            'siteName': _site,
            'manDays': 1.0,
            'overtimeHours': overtimeHours,
            'earlyHours': earlyHours,
            'nightHours': nightHours,
            'allowanceYen': allowanceYen,
            'notes': details.notes.text.trim(),
          });
        }
      }
    } on FormatException catch (error) {
      _show(error.message);
      return;
    }

    final approvalRepository = _approvalRepository;
    if (approvalRepository == null) {
      _show('過去のまとめて出勤申請を利用できません。');
      return;
    }

    final signature = await Navigator.of(context).push<SignatureResult>(
      MaterialPageRoute(
        builder: (_) => const SignatureCapturePage(),
      ),
    );
    if (signature == null || !mounted) return;

    setState(() => _saving = true);
    try {
      await approvalRepository.submit(
        items: records,
        signerName: signature.signerName,
        signatureJson: signature.toJson(),
      );
      if (!mounted) return;
      Navigator.of(context).pop(records.length);
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      _show('過去のまとめて出勤を申請できませんでした: $error');
    }
  }

  void _show(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Widget _numberField({
    required TextEditingController controller,
    required String label,
    String? suffix,
  }) {
    return TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        labelText: label,
        suffixText: suffix,
        border: const OutlineInputBorder(),
      ),
    );
  }

  Widget _dayDetailCard(int day) {
    final details = _dayDetails.putIfAbsent(day, _BulkDayDetails.new);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ExpansionTile(
        key: ValueKey('bulk-day-$day'),
        title: Text('${_dateText(day)} の詳細'),
        subtitle: const Text('残業・早出・夜勤・手当を日ごとに設定'),
        childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
        children: [
          Row(
            children: [
              Expanded(
                child: _numberField(
                  controller: details.overtime,
                  label: '残業',
                  suffix: '時間',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _numberField(
                  controller: details.early,
                  label: '早出',
                  suffix: '時間',
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _numberField(
                  controller: details.night,
                  label: '夜勤',
                  suffix: '時間',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: details.allowance,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: '手当',
                    suffixText: '円',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            controller: details.notes,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: '備考',
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final selectedDays = _selectedDays.toList()..sort();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
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
          label: Text(_saving ? '申請中…' : 'まとめてサインして申請'),
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
                              style: Theme.of(context)
                                  .textTheme
                                  .titleLarge
                                  ?.copyWith(fontWeight: FontWeight.bold),
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
                                Builder(
                                  builder: (context) {
                                    final date =
                                        DateTime(_month.year, _month.month, day);
                                    final enabled = date.isBefore(today);
                                    return FilterChip(
                                      label: Text('$day日'),
                                      selected: _selectedDays.contains(day),
                                      onSelected: enabled
                                          ? (selected) =>
                                              _setDaySelected(day, selected)
                                          : null,
                                    );
                                  },
                                ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<String>(
                        initialValue: _site,
                        decoration: const InputDecoration(
                          labelText: '現場',
                          border: OutlineInputBorder(),
                        ),
                        items: _sites
                            .map((site) => DropdownMenuItem(
                                  value: site,
                                  child: Text(site),
                                ))
                            .toList(growable: false),
                        onChanged: (value) => setState(() => _site = value),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        '作業員（複数選択）',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
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
                                  controlAffinity:
                                      ListTileControlAffinity.leading,
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
                      if (selectedDays.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        Text(
                          '日ごとの入力',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        for (final day in selectedDays) _dayDetailCard(day),
                      ],
                      const SizedBox(height: 12),
                      Text(
                        '選択: ${_selectedDays.length}日 × ${_selectedWorkers.length}人 = ${_selectedDays.length * _selectedWorkers.length}件',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        '選択した日付・作業員を1回のまとめてサインで申請します。承認完了後に正式な出勤データへ反映します。',
                      ),
                    ],
                  ),
      ),
    );
  }
}

class _BulkDayDetails {
  final overtime = TextEditingController(text: '0');
  final early = TextEditingController(text: '0');
  final night = TextEditingController(text: '0');
  final allowance = TextEditingController(text: '0');
  final notes = TextEditingController();

  void dispose() {
    overtime.dispose();
    early.dispose();
    night.dispose();
    allowance.dispose();
    notes.dispose();
  }
}
