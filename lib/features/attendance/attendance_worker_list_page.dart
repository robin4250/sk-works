import 'dart:async';

import '../shared/related_action_footer.dart';

import 'package:flutter/material.dart';

import '../notifications/notification_bell.dart';
import '../../international/language_controller.dart';
import 'attendance_pdf_service.dart';
import 'partner_attendance_month_page.dart';
import 'worker_attendance_sheet_page.dart';
import 'worker_attendance_sheet_repository.dart';

class AttendanceWorkerListPage extends StatefulWidget {
  const AttendanceWorkerListPage({super.key, this.onOpenManagement});
  final Future<void> Function()? onOpenManagement;

  @override
  State<AttendanceWorkerListPage> createState() =>
      _AttendanceWorkerListPageState();
}

class _AttendanceWorkerListPageState extends State<AttendanceWorkerListPage> {
  final _repository = WorkerAttendanceSheetRepository.maybeCreate();

  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  List<AttendanceWorker> _workers = const [];
  bool _loading = true;
  bool _partners = false;
  int _generation = 0;
  StreamSubscription? _partnerAuth;
  String _partnerText(String ja, String en) =>
      SkoLanguageController.isEnglish ? en : ja;
  List<PartnerAttendanceWorker> _partnerWorkers = const [];
  bool _printing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _partnerAuth = _repository?.partnerAuthChanges.listen((_) {
      if (!mounted) return;
      if (_partners &&
          _partnerWorkers.any(
            (worker) => !_repository.partnerWorkerIsCurrent(worker),
          )) {
        _generation++;
        setState(() {
          _partnerWorkers = const [];
          _loading = false;
          _error = _partnerText(
            'ログイン状態が変わりました。再読み込みしてください。',
            'Your sign-in session changed. Reload this page.',
          );
        });
      }
    });
    _load();
  }

  @override
  void dispose() {
    _partnerAuth?.cancel();
    super.dispose();
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

    final generation = ++_generation;
    final partners = _partners;
    setState(() {
      _workers = const [];
      _partnerWorkers = const [];
      _loading = true;
      _error = null;
    });
    try {
      final workers = partners
          ? const <AttendanceWorker>[]
          : await repository.loadCompanyWorkers();
      final partnerWorkers = partners
          ? await repository.loadPartnerWorkers()
          : const <PartnerAttendanceWorker>[];
      if (!mounted || generation != _generation || partners != _partners) {
        return;
      }
      setState(() {
        _workers = workers;
        _partnerWorkers = partnerWorkers;
        _loading = false;
      });
    } catch (error) {
      if (!mounted || generation != _generation || partners != _partners) {
        return;
      }
      setState(() {
        _loading = false;
        _error = partners
            ? _partnerText(
                '出勤記録を読み込めませんでした。ログイン状態と会社を確認して再試行してください。',
                'Attendance records could not be loaded. Check your sign-in and company, then try again.',
              )
            : error.toString();
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
      final rows = <({String workerName, WorkerAttendanceMonth data})>[];
      for (final worker in _workers) {
        final data = await repository.loadMonth(_month, workerId: worker.id);
        rows.add((workerName: worker.name, data: data));
      }
      if (!mounted) return;
      await AttendancePdfService.printWorkers(_month, rows);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('出勤表一覧を印刷できませんでした: $error')));
    } finally {
      if (mounted) setState(() => _printing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    SkoLanguageController.watch(context);
    return Scaffold(
      bottomNavigationBar: widget.onOpenManagement == null
          ? null
          : RelatedActionFooter(
              label: '勤怠管理',
              icon: Icons.manage_history_outlined,
              onPressed: widget.onOpenManagement!,
            ),
      appBar: AppBar(
        title: const Text(
          '出勤表一覧',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        actions: [
          IconButton(
            tooltip: '全社員の出勤表をまとめて印刷',
            onPressed: _partners || _loading || _workers.isEmpty || _printing
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
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: SegmentedButton<bool>(
                segments: [
                  ButtonSegment(
                    value: false,
                    label: Text(_partnerText('社員', 'Employees')),
                  ),
                  ButtonSegment(
                    value: true,
                    label: Text(_partnerText('協力会社', 'Partner companies')),
                  ),
                ],
                selected: {_partners},
                onSelectionChanged: _printing
                    ? null
                    : (selection) {
                        setState(() {
                          _partners = selection.single;
                        });
                        _load();
                      },
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
                            Text(
                              _partners
                                  ? _partnerText(
                                      '出勤記録を読み込めませんでした。ログイン状態と会社を確認して再試行してください。',
                                      'Attendance records could not be loaded. Check your sign-in and company, then try again.',
                                    )
                                  : _error!,
                              textAlign: TextAlign.center,
                            ),
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
                  : _partners
                  ? _partnerWorkers.isEmpty
                        ? Center(
                            child: Text(
                              _partnerText(
                                '協力会社の作業者が登録されていません',
                                'No partner workers are registered.',
                              ),
                            ),
                          )
                        : ListView.builder(
                            itemCount: _partnerWorkers.length,
                            itemBuilder: (context, index) {
                              final worker = _partnerWorkers[index];
                              return ListTile(
                                title: Text(worker.name),
                                subtitle: Text(
                                  '${_partnerText('協力会社', 'Partner company')}: ${worker.partnerName}',
                                  softWrap: true,
                                ),
                                trailing: const Icon(Icons.chevron_right),
                                onTap: () => Navigator.of(context).push<void>(
                                  MaterialPageRoute(
                                    builder: (_) => PartnerAttendanceMonthPage(
                                      worker: worker,
                                      initialMonth: _month,
                                    ),
                                  ),
                                ),
                              );
                            },
                          )
                  : _workers.isEmpty
                  ? const Center(child: Text('社員が登録されていません'))
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 24),
                      itemCount: _workers.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 6),
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
                            trailing: const Icon(Icons.chevron_right),
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
