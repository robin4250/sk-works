import 'package:flutter/material.dart';

import '../notifications/notification_bell.dart';
import 'attendance_pdf_service.dart';
import 'worker_attendance_sheet_page.dart';
import 'worker_attendance_sheet_repository.dart';

class AttendanceWorkerListPage extends StatefulWidget {
  const AttendanceWorkerListPage({super.key});

  @override
  State<AttendanceWorkerListPage> createState() =>
      _AttendanceWorkerListPageState();
}

class _AttendanceWorkerListPageState extends State<AttendanceWorkerListPage> {
  final _repository = WorkerAttendanceSheetRepository.maybeCreate();

  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  List<AttendanceWorker> _workers = const [];
  bool _loading = true;
  bool _printing = false;
  String? _error;

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
      final workers = await repository.loadCompanyWorkers();
      if (!mounted) return;
      setState(() {
        _workers = workers;
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

  void _changeMonth(int delta) {
    setState(() {
      _month = DateTime(_month.year, _month.month + delta);
    });
  }

  Future<void> _openWorker(AttendanceWorker worker) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => WorkerAttendanceSheetPage(
          workerId: worker.id,
          workerName: worker.name,
          initialMonth: _month,
        ),
      ),
    );
  }

  Future<void> _printAll() async {
    final repository = _repository;
    if (repository == null || _workers.isEmpty || _printing) return;

    setState(() => _printing = true);
    try {
      final rows =
          <({String workerName, WorkerAttendanceMonth data})>[];
      for (final worker in _workers) {
        final data = await repository.loadMonth(
          _month,
          workerId: worker.id,
        );
        rows.add((workerName: worker.name, data: data));
      }
      if (!mounted) return;
      await AttendancePdfService.printWorkers(_month, rows);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('出勤表一覧を印刷できませんでした: $error')),
      );
    } finally {
      if (mounted) setState(() => _printing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          '出勤表一覧',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        actions: [
          IconButton(
            tooltip: '全社員の出勤表をまとめて印刷',
            onPressed: _loading || _workers.isEmpty || _printing
                ? null
                : _printAll,
            icon: _printing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.print_outlined),
          ),
          const SkoNotificationBell(),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: Row(
                children: [
                  IconButton(
                    tooltip: '前の月',
                    onPressed: _printing ? null : () => _changeMonth(-1),
                    icon: const Icon(Icons.chevron_left),
                  ),
                  Expanded(
                    child: Text(
                      '${_month.year}年${_month.month}月',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                    ),
                  ),
                  IconButton(
                    tooltip: '次の月',
                    onPressed: _printing ? null : () => _changeMonth(1),
                    icon: const Icon(Icons.chevron_right),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
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
                                const SizedBox(height: 12),
                                FilledButton.icon(
                                  onPressed: _load,
                                  icon: const Icon(Icons.refresh),
                                  label: const Text('再読み込み'),
                                ),
                              ],
                            ),
                          ),
                        )
                      : _workers.isEmpty
                          ? const Center(child: Text('社員が登録されていません'))
                          : ListView.separated(
                              padding:
                                  const EdgeInsets.fromLTRB(12, 10, 12, 24),
                              itemCount: _workers.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 6),
                              itemBuilder: (context, index) {
                                final worker = _workers[index];
                                return Card(
                                  child: ListTile(
                                    leading: const CircleAvatar(
                                      child: Icon(Icons.person_outline),
                                    ),
                                    title: Text(
                                      worker.name,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    subtitle: const Text('タップして出勤表を表示'),
                                    trailing:
                                        const Icon(Icons.chevron_right),
                                    onTap: () => _openWorker(worker),
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
