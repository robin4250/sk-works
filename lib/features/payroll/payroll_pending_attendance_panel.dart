import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../attendance/attendance_protected_routes.dart';
import '../attendance/attendance_management_repository.dart';

/// Management-only guidance. This never creates work quantities or payroll rows.
class PayrollPendingAttendancePanel extends StatefulWidget {
  const PayrollPendingAttendancePanel({super.key, required this.statementId,
    required this.onReturn, this.repository});
  final String statementId;
  final Future<void> Function() onReturn;
  final AttendanceManagementRepository? repository;

  @override
  State<PayrollPendingAttendancePanel> createState() => _PayrollPendingAttendancePanelState();
}

class _PayrollPendingAttendancePanelState extends State<PayrollPendingAttendancePanel> {
  late final _repository = widget.repository ?? AttendanceManagementRepository.maybeCreate();
  StreamSubscription<AuthState>? _subscription;
  PayrollPendingAttendance? _pending;
  int _generation = 0;
  bool _loading = true, _opening = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _subscription = _repository?.authChanges.listen((_) => _load());
    _load();
  }

  @override
  void didUpdateWidget(covariant PayrollPendingAttendancePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.statementId != widget.statementId) _load();
  }

  Future<void> _load() async {
    final generation = ++_generation;
    setState(() { _pending = null; _error = null; _loading = true; });
    try {
      final pending = await _repository?.loadPayrollPendingDays(widget.statementId);
      if (!mounted || generation != _generation) return;
      setState(() => _pending = pending);
    } catch (_) {
      if (!mounted || generation != _generation) return;
      setState(() => _error = '未確定の勤務を確認できませんでした。');
    } finally {
      if (mounted && generation == _generation) setState(() => _loading = false);
    }
  }

  Future<void> _open(DateTime date) async {
    if (_opening || _loading || _pending == null) return;
    final generation = _generation, pending = _pending!;
    setState(() => _opening = true);
    try {
      // Re-check authorization and the date before leaving the payroll screen.
      final current = await _repository?.loadPayrollPendingDays(widget.statementId);
      if (!mounted || generation != _generation) return;
      if (current == null || current.workerId != pending.workerId || !current.dates.contains(date)) {
        await _load();
        return;
      }
      await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) =>
        attendanceManagementDestination(repository: _repository, initialWorkerId: current.workerId, initialDate: date)));
      if (!mounted || generation != _generation) return;
      await widget.onReturn();
      if (mounted) await _load();
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() { _pending = null; _error = '勤務を開けませんでした。再確認してください。'; });
      }
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  void dispose() {
    _generation++;
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pending = _pending;
    if (_loading || (_error == null && (pending == null || pending.dates.isEmpty))) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: ExpansionTile(
        dense: true,
        tilePadding: const EdgeInsets.symmetric(horizontal: 4),
        leading: const Icon(Icons.pending_actions_outlined),
        title: Text(_error ?? '未確定の勤務 ${pending!.dates.length}日'),
        children: [
          if (_error != null)
            TextButton(onPressed: _load, child: const Text('再確認'))
          else ...[
            const Padding(padding: EdgeInsets.all(8), child: Text(
              '出退勤の打刻がありますが、給与用の勤務記録が未確定です。日付を選び、現場・人工・作業内容を確認してください。')),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 160),
              child: SingleChildScrollView(child: Wrap(spacing: 8, children: [
                for (final date in pending!.dates)
                  TextButton(onPressed: _opening ? null : () => _open(date),
                    child: Text('${date.month}/${date.day} 勤務を確認')),
              ])),
            ),
          ],
        ],
      ),
    );
  }
}
