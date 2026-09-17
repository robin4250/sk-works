import 'package:flutter/material.dart';

import 'attendance_cloud_repository.dart';
import 'attendance_page.dart';

class AttendanceCloudPage extends StatefulWidget {
  const AttendanceCloudPage({super.key});

  @override
  State<AttendanceCloudPage> createState() => _AttendanceCloudPageState();
}

class _AttendanceCloudPageState extends State<AttendanceCloudPage> {
  final _repository = AttendanceCloudRepository.maybeCreate();
  final _entries = <AttendanceEntry>[];
  bool _loading = true;
  String _query = '';
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final repository = _repository;
    if (repository == null) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Supabase接続が利用できません。';
      });
      return;
    }
    try {
      final rows = await repository.loadAll();
      final loaded = rows.map(AttendanceEntry.fromJson).toList();
      if (!mounted) return;
      setState(() {
        _entries
          ..clear()
          ..addAll(loaded);
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
      appBar: AppBar(
        title: const Text('勤怠・人工'),
        actions: [
          IconButton(
            tooltip: '再読み込み',
            onPressed: _loading
                ? null
                : () {
                    setState(() => _loading = true);
                    _load();
                  },
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
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
                  Expanded(child: _SummaryCard(label: '人工合計', value: _formatNumber(totalManDays))),
                  const SizedBox(width: 8),
                  Expanded(child: _SummaryCard(label: '残業合計', value: '${_formatNumber(totalOvertime)}h')),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? _ErrorState(message: _error!, onRetry: _load)
                      : filtered.isEmpty
                          ? const Center(child: Text('勤怠データはまだありません'))
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
                                    title: Text('${entry.date}  ${entry.workerName}', style: const TextStyle(fontWeight: FontWeight.w700)),
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
    final draft = await Navigator.of(context).push<AttendanceEntry>(
      MaterialPageRoute(builder: (_) => const AttendanceFormPage()),
    );
    final repository = _repository;
    if (draft == null || repository == null) return;
    try {
      final row = await repository.insert(draft.toJson());
      final saved = AttendanceEntry.fromJson(row);
      if (!mounted) return;
      setState(() => _entries.insert(0, saved));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('勤怠をクラウドに登録しました')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('登録できませんでした: $error')),
      );
    }
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
                  await _delete(entry);
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

  Future<void> _delete(AttendanceEntry entry) async {
    final repository = _repository;
    if (repository == null) return;
    try {
      await repository.delete(entry.id);
      if (!mounted) return;
      setState(() => _entries.removeWhere((item) => item.id == entry.id));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('勤怠を削除しました')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('削除できませんでした: $error')),
      );
    }
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
            const Icon(Icons.cloud_off_outlined, size: 42),
            const SizedBox(height: 12),
            const Text('クラウドデータを読み込めませんでした'),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('再試行'),
            ),
          ],
        ),
      ),
    );
  }
}
