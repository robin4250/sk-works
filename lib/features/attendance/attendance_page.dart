import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AttendanceEntry {
  const AttendanceEntry({
    required this.id,
    required this.date,
    required this.workerName,
    required this.siteName,
    required this.manDays,
    this.overtimeHours = 0,
    this.earlyHours = 0,
    this.nightHours = 0,
    this.allowanceYen = 0,
    this.notes = '',
  });

  final String id;
  final String date;
  final String workerName;
  final String siteName;
  final double manDays;
  final double overtimeHours;
  final double earlyHours;
  final double nightHours;
  final int allowanceYen;
  final String notes;

  Map<String, Object?> toJson() => {
        'id': id,
        'date': date,
        'workerName': workerName,
        'siteName': siteName,
        'manDays': manDays,
        'overtimeHours': overtimeHours,
        'earlyHours': earlyHours,
        'nightHours': nightHours,
        'allowanceYen': allowanceYen,
        'notes': notes,
      };

  factory AttendanceEntry.fromJson(Map<String, dynamic> json) {
    double number(String key) => (json[key] as num?)?.toDouble() ?? 0;
    return AttendanceEntry(
      id: json['id']?.toString() ?? '',
      date: json['date']?.toString() ?? '',
      workerName: json['workerName']?.toString() ?? '',
      siteName: json['siteName']?.toString() ?? '',
      manDays: number('manDays'),
      overtimeHours: number('overtimeHours'),
      earlyHours: number('earlyHours'),
      nightHours: number('nightHours'),
      allowanceYen: (json['allowanceYen'] as num?)?.toInt() ?? 0,
      notes: json['notes']?.toString() ?? '',
    );
  }
}

class AttendancePage extends StatefulWidget {
  const AttendancePage({super.key});

  @override
  State<AttendancePage> createState() => _AttendancePageState();
}

class _AttendancePageState extends State<AttendancePage> {
  static const _storageKey = 'sk_works_attendance_v2';
  final _entries = <AttendanceEntry>[];
  bool _loading = true;
  String _query = '';

  static const _samples = [
    AttendanceEntry(
      id: 'attendance-1',
      date: '2026/09/17',
      workerName: '山田 太郎',
      siteName: '墨田区〇〇改修工事',
      manDays: 1,
    ),
    AttendanceEntry(
      id: 'attendance-2',
      date: '2026/09/17',
      workerName: '佐藤 次郎',
      siteName: '墨田区〇〇改修工事',
      manDays: 1,
      overtimeHours: 2,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    var loaded = <AttendanceEntry>[];
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_storageKey);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw) as List<dynamic>;
        loaded = decoded
            .map((item) => AttendanceEntry.fromJson(item as Map<String, dynamic>))
            .toList();
      }
    } catch (_) {
      loaded = [];
    }
    if (loaded.isEmpty) loaded = List<AttendanceEntry>.from(_samples);
    if (!mounted) return;
    setState(() {
      _entries
        ..clear()
        ..addAll(loaded);
      _loading = false;
    });
  }

  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _storageKey,
        jsonEncode(_entries.map((entry) => entry.toJson()).toList()),
      );
    } catch (_) {
      // Prototype persistence is best-effort until cloud storage is connected.
    }
  }

  @override
  Widget build(BuildContext context) {
    final needle = _query.trim().toLowerCase();
    final filtered = _entries.where((entry) {
      if (needle.isEmpty) return true;
      return [entry.date, entry.workerName, entry.siteName, entry.notes]
          .join(' ')
          .toLowerCase()
          .contains(needle);
    }).toList();

    final totalManDays = filtered.fold<double>(0, (sum, entry) => sum + entry.manDays);
    final totalOvertime = filtered.fold<double>(0, (sum, entry) => sum + entry.overtimeHours);

    return Scaffold(
      appBar: AppBar(title: const Text('勤怠・人工')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _loading ? null : _add,
        icon: const Icon(Icons.add),
        label: const Text('出面入力'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: TextField(
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: '日付・作業員・現場で検索',
                ),
                onChanged: (value) => setState(() => _query = value),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: _SummaryCard(label: '人工合計', value: _formatNumber(totalManDays)),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _SummaryCard(label: '残業合計', value: '${_formatNumber(totalOvertime)}h'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : filtered.isEmpty
                      ? const Center(child: Text('該当する勤怠データはありません'))
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
                          itemCount: filtered.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final entry = filtered[index];
                            final extras = <String>[
                              '${_formatNumber(entry.manDays)}人工',
                              if (entry.overtimeHours > 0) '残業${_formatNumber(entry.overtimeHours)}h',
                              if (entry.earlyHours > 0) '早出${_formatNumber(entry.earlyHours)}h',
                              if (entry.nightHours > 0) '夜間${_formatNumber(entry.nightHours)}h',
                            ];
                            return Card(
                              child: ListTile(
                                leading: const CircleAvatar(child: Icon(Icons.schedule_outlined)),
                                title: Text(
                                  '${entry.date}  ${entry.workerName}',
                                  style: const TextStyle(fontWeight: FontWeight.w700),
                                ),
                                subtitle: Text('${entry.siteName} / ${extras.join(' / ')}'),
                                trailing: const Icon(Icons.chevron_right),
                                onTap: () => _showDetails(entry),
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

  String _formatNumber(double value) => value == value.roundToDouble()
      ? value.toInt().toString()
      : value.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');

  Future<void> _add() async {
    final entry = await Navigator.of(context).push<AttendanceEntry>(
      MaterialPageRoute(builder: (_) => const AttendanceFormPage()),
    );
    if (entry == null) return;
    setState(() => _entries.insert(0, entry));
    await _save();
  }

  void _showDetails(AttendanceEntry entry) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(entry.workerName, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              Text('日付: ${entry.date}'),
              Text('現場: ${entry.siteName}'),
              Text('人工: ${_formatNumber(entry.manDays)}'),
              Text('残業: ${_formatNumber(entry.overtimeHours)}h'),
              Text('早出: ${_formatNumber(entry.earlyHours)}h'),
              Text('夜間: ${_formatNumber(entry.nightHours)}h'),
              if (entry.allowanceYen != 0) Text('手当: ¥${entry.allowanceYen}'),
              if (entry.notes.isNotEmpty) Text('備考: ${entry.notes}'),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: () async {
                  Navigator.pop(sheetContext);
                  setState(() => _entries.remove(entry));
                  await _save();
                },
                icon: const Icon(Icons.delete_outline),
                label: const Text('削除'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
            Text(label),
          ],
        ),
      ),
    );
  }
}

class AttendanceFormPage extends StatefulWidget {
  const AttendanceFormPage({super.key});

  @override
  State<AttendanceFormPage> createState() => _AttendanceFormPageState();
}

class _AttendanceFormPageState extends State<AttendanceFormPage> {
  final _formKey = GlobalKey<FormState>();
  final _date = TextEditingController();
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
      _date,
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
      appBar: AppBar(title: const Text('勤怠・人工 - 入力')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _requiredField(_date, '日付 (YYYY/MM/DD)'),
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
                label: const Text('登録する'),
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
      validator: (value) => value == null || value.trim().isEmpty ? '$labelを入力してください' : null,
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
        date: _date.text.trim(),
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
