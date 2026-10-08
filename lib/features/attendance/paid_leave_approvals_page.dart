import 'package:flutter/material.dart';

import '../../international/language_controller.dart';
import '../notifications/notification_bell.dart';
import 'paid_leave_repository.dart';

class PaidLeaveApprovalsPage extends StatefulWidget {
  const PaidLeaveApprovalsPage({super.key, this.initialRequestId});

  final String? initialRequestId;

  @override
  State<PaidLeaveApprovalsPage> createState() =>
      _PaidLeaveApprovalsPageState();
}

class _PaidLeaveApprovalsPageState extends State<PaidLeaveApprovalsPage> {
  final _repository = PaidLeaveRepository.maybeCreate();
  List<PaidLeaveApprovalBatch> _items = const [];
  bool _loading = true;
  bool _busy = false;
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
        _error = '有給申請の承認を利用できません。';
      });
      return;
    }
    try {
      final target = widget.initialRequestId;
      final items = target == null
          ? await repository.loadPendingApprovals()
          : await repository.loadApprovalTarget(target);
      if (!mounted) return;
      setState(() {
        _items = items;
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

  Future<void> _open(PaidLeaveApprovalBatch item) async {
    final repository = _repository;
    if (repository == null) return;
    // Notification targets already carry dates from their permitted RLS read.
    final dates = item.leaveDates ??
        await repository.loadBatchDates(item.batchId);
    if (!mounted) return;

    final note = TextEditingController();
    final decision = await showDialog<bool?>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('${item.requestedByName} / ${item.dateCount}日'),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final date in dates)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(_date(date)),
                  ),
                if (item.reason.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text('理由：${item.reason}'),
                ],
                const SizedBox(height: 12),
                if (item.canDecide) TextField(
                  controller: note,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: '承認・却下メモ（任意）',
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('閉じる'),
          ),
          if (item.canDecide) OutlinedButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('却下'),
          ),
          if (item.canDecide) FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('承認'),
          ),
        ],
      ),
    );
    final noteText = note.text;
    note.dispose();
    if (decision == null || !item.canDecide) return;

    setState(() => _busy = true);
    try {
      await repository.decide(
        batchId: item.batchId,
        approve: decision,
        note: noteText,
      );
      await _load();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    SkoLanguageController.watch(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          '有給申請の承認待ち',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        actions: const [SkoNotificationBell()],
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(child: Text(_error!, textAlign: TextAlign.center))
                : _items.isEmpty
                    ? Center(child: Text(SkoLanguageController.tr(
                        widget.initialRequestId == null
                          ? '承認待ちの有給申請はありません'
                          : '対象の申請を表示できません。閲覧権限を確認してください。'))))
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: ListView.separated(
                          padding: const EdgeInsets.all(12),
                          itemCount: _items.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final item = _items[index];
                            return Card(
                              child: ListTile(
                                enabled: !_busy,
                                leading: const CircleAvatar(
                                  child: Icon(Icons.event_available_outlined),
                                ),
                                title: Text(
                                  item.requestedByName,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                subtitle: Text(
                                  '${item.dateCount}日 / ${_date(item.firstDate)}'
                                  '${item.firstDate == item.lastDate ? '' : '〜${_date(item.lastDate)}'}'
                                  ' / ${SkoLanguageController.tr(switch (item.status) {
                                    'approved' => '承認済み',
                                    'rejected' => '却下済み',
                                    'pending' => '承認待ち',
                                    _ => '申請状態を確認してください',
                                  })}',
                                ),
                                trailing: const Icon(Icons.chevron_right),
                                onTap: () => _open(item),
                              ),
                            );
                          },
                        ),
                      ),
      ),
    );
  }

  static String _date(DateTime value) =>
      '${value.year}/${value.month.toString().padLeft(2, '0')}/${value.day.toString().padLeft(2, '0')}';
}
