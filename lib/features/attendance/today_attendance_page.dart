import 'package:flutter/material.dart';

import '../notifications/notification_bell.dart';
import 'today_attendance_repository.dart';

class TodayAttendancePage extends StatefulWidget {
  const TodayAttendancePage({super.key});

  @override
  State<TodayAttendancePage> createState() => _TodayAttendancePageState();
}

class _TodayAttendancePageState extends State<TodayAttendancePage> {
  final _repository = TodayAttendanceRepository.maybeCreate();

  TodayAttendanceSnapshot? _snapshot;
  bool _loading = true;
  String? _error;
  int _tabIndex = 0;

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
        _error = 'クラウド接続を確認できません。';
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final snapshot = await repository.loadToday();
      if (!mounted) return;
      setState(() {
        _snapshot = snapshot;
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

  @override
  Widget build(BuildContext context) {
    final snapshot = _snapshot;
    final own = snapshot?.ownCompany ?? const <TodayAttendanceRecord>[];
    final partner =
        snapshot?.subcontractors ?? const <TodayAttendanceRecord>[];
    final selected = _tabIndex == 0 ? own : partner;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          '本日の出勤',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        actions: [
          const SkoNotificationBell(),
          IconButton(
            tooltip: '再読み込み',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? _ErrorState(message: _error!, onRetry: _load)
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 24),
                      children: [
                        _SummaryRow(
                          total: snapshot?.records.length ?? 0,
                          working: snapshot?.records
                                  .where((record) => record.isWorking)
                                  .length ??
                              0,
                          clockedOut: snapshot?.records
                                  .where(
                                    (record) =>
                                        record.lastEventType == 'clock_out',
                                  )
                                  .length ??
                              0,
                        ),
                        const SizedBox(height: 12),
                        SegmentedButton<int>(
                          segments: [
                            ButtonSegment(
                              value: 0,
                              icon: const Icon(Icons.business_outlined),
                              label: Text('自社 ${own.length}'),
                            ),
                            ButtonSegment(
                              value: 1,
                              icon: const Icon(Icons.handshake_outlined),
                              label: Text('下請け ${partner.length}'),
                            ),
                          ],
                          selected: {_tabIndex},
                          onSelectionChanged: (values) {
                            if (values.isEmpty) return;
                            setState(() => _tabIndex = values.first);
                          },
                        ),
                        const SizedBox(height: 12),
                        if (selected.isEmpty)
                          const Card(
                            child: Padding(
                              padding: EdgeInsets.all(22),
                              child: Center(
                                child: Text(
                                  '本日の出勤記録はまだありません',
                                  style: TextStyle(fontWeight: FontWeight.w800),
                                ),
                              ),
                            ),
                          )
                        else
                          for (final record in selected) ...[
                            _AttendanceCard(record: record),
                            const SizedBox(height: 8),
                          ],
                      ],
                    ),
                  ),
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.total,
    required this.working,
    required this.clockedOut,
  });

  final int total;
  final int working;
  final int clockedOut;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: _SummaryTile(label: '合計', value: total)),
        const SizedBox(width: 8),
        Expanded(child: _SummaryTile(label: '出勤中', value: working)),
        const SizedBox(width: 8),
        Expanded(child: _SummaryTile(label: '退勤済', value: clockedOut)),
      ],
    );
  }
}

class _SummaryTile extends StatelessWidget {
  const _SummaryTile({required this.label, required this.value});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        child: Column(
          children: [
            Text(
              '$value人',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AttendanceCard extends StatelessWidget {
  const _AttendanceCard({required this.record});

  final TodayAttendanceRecord record;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final working = record.isWorking;

    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor:
              working ? scheme.primaryContainer : scheme.surfaceContainerHigh,
          child: Icon(
            working ? Icons.login : Icons.logout,
            color: working ? scheme.onPrimaryContainer : scheme.onSurface,
          ),
        ),
        title: Text(
          record.workerName,
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        subtitle: Text(
          [
            if (record.isPartner) record.companyLabel,
            record.siteName ?? '現場未設定',
            '出 ${_time(record.clockInAt)}',
            '退 ${_time(record.clockOutAt)}',
          ].join(' / '),
        ),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
          decoration: BoxDecoration(
            color: working ? scheme.primary : scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(99),
          ),
          child: Text(
            working ? '出勤中' : '退勤済',
            style: TextStyle(
              color: working ? scheme.onPrimary : scheme.onSurfaceVariant,
              fontWeight: FontWeight.w900,
              fontSize: 11,
            ),
          ),
        ),
      ),
    );
  }

  static String _time(DateTime? value) {
    if (value == null) return '--:--';
    String two(int value) => value.toString().padLeft(2, '0');
    return '${two(value.hour)}:${two(value.minute)}';
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
            const Text(
              '本日の出勤を読み込めませんでした',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
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
