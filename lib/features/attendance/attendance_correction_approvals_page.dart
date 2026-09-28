import 'package:flutter/material.dart';

import '../notifications/notification_bell.dart';
import 'attendance_correction_approval_repository.dart';

class AttendanceCorrectionApprovalsPage extends StatefulWidget {
  const AttendanceCorrectionApprovalsPage({super.key});

  @override
  State<AttendanceCorrectionApprovalsPage> createState() =>
      _AttendanceCorrectionApprovalsPageState();
}

class _AttendanceCorrectionApprovalsPageState
    extends State<AttendanceCorrectionApprovalsPage> {
  final _repository = AttendanceCorrectionApprovalRepository.maybeCreate();

  List<AttendanceCorrectionApprovalRequest> _items = const [];
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
        _error = '過去勤怠の修正承認を利用できません。';
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final items = await repository.loadPending();
      if (!mounted) return;
      setState(() {
        _items = items;
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
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          '過去勤怠の修正承認',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        actions: const [SkoNotificationBell()],
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? _ErrorState(message: _error!, onRetry: _load)
                : _items.isEmpty
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.all(28),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.task_alt_outlined, size: 56),
                              SizedBox(height: 12),
                              Text(
                                '承認待ちの過去勤怠修正はありません',
                                textAlign: TextAlign.center,
                                style: TextStyle(fontWeight: FontWeight.w900),
                              ),
                            ],
                          ),
                        ),
                      )
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
                                leading: const CircleAvatar(
                                  child: Icon(Icons.edit_calendar_outlined),
                                ),
                                title: Text(
                                  item.requestedByName,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                subtitle: Text(
                                  [
                                    '${item.itemCount}件',
                                    if (item.signerName.isNotEmpty)
                                      'サイン: ${item.signerName}',
                                    if (item.submittedAt != null)
                                      _dateTime(item.submittedAt!),
                                  ].join(' / '),
                                ),
                                trailing:
                                    const Icon(Icons.chevron_right),
                                onTap: _busy
                                    ? null
                                    : () => _openRequest(item),
                              ),
                            );
                          },
                        ),
                      ),
      ),
    );
  }

  Future<void> _openRequest(
    AttendanceCorrectionApprovalRequest request,
  ) async {
    final repository = _repository;
    if (repository == null) return;

    List<AttendanceCorrectionApprovalItem> details;
    try {
      details = await repository.loadItems(request.id);
    } catch (error) {
      if (!mounted) return;
      _show('修正内容を読み込めませんでした: $error');
      return;
    }
    if (!mounted) return;

    final note = TextEditingController();
    final decision = await showDialog<bool?>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('${request.requestedByName} / ${request.itemCount}件'),
        content: SizedBox(
          width: 620,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (request.signerName.isNotEmpty)
                  Text(
                    'おまとめサイン: ${request.signerName}',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                const SizedBox(height: 10),
                for (final item in details) ...[
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _itemTitle(item),
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            item.changeSummary.trim().isEmpty
                                ? '変更内容を確認してください'
                                : item.changeSummary,
                          ),
                          const SizedBox(height: 8),
                          _SnapshotDiff(
                            original: item.originalSnapshot,
                            proposed: item.proposedSnapshot,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                ],
                const SizedBox(height: 10),
                TextField(
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
          OutlinedButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('却下'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('承認して反映'),
          ),
        ],
      ),
    );

    final noteText = note.text;
    note.dispose();

    if (decision == null) return;

    setState(() => _busy = true);
    try {
      final status = await repository.decide(
        requestId: request.id,
        approve: decision,
        note: noteText,
      );
      if (!mounted) return;
      _show(
        status == 'approved'
            ? '過去勤怠の修正を承認し、勤怠へ反映しました'
            : '過去勤怠の修正申請を却下しました',
      );
      await _load();
    } catch (error) {
      if (!mounted) return;
      _show('承認処理に失敗しました: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _itemTitle(AttendanceCorrectionApprovalItem item) {
    final date = item.originalSnapshot['date']?.toString() ?? '';
    final worker = item.originalSnapshot['workerName']?.toString() ?? '';
    return [date, worker].where((value) => value.isNotEmpty).join('  ');
  }

  void _show(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  static String _dateTime(DateTime value) {
    final local = value.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${local.year}/${two(local.month)}/${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}';
  }
}

class _SnapshotDiff extends StatelessWidget {
  const _SnapshotDiff({
    required this.original,
    required this.proposed,
  });

  final Map<String, dynamic> original;
  final Map<String, dynamic> proposed;

  static const _labels = <String, String>{
    'siteName': '現場',
    'manDays': '人工',
    'overtimeHours': '残業',
    'earlyHours': '早出',
    'nightHours': '夜勤',
    'allowanceYen': '手当',
    'notes': '備考',
  };

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (final entry in _labels.entries) {
      final before = original[entry.key]?.toString() ?? '';
      final after = proposed[entry.key]?.toString() ?? '';
      if (before == after) continue;

      rows.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 56,
                child: Text(
                  entry.value,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              Expanded(
                child: Text('$before → $after'),
              ),
            ],
          ),
        ),
      );
    }

    if (rows.isEmpty) {
      return const Text('変更差分なし');
    }
    return Column(children: rows);
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({
    required this.message,
    required this.onRetry,
  });

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
            const Icon(Icons.error_outline, size: 48),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('再読み込み'),
            ),
          ],
        ),
      ),
    );
  }
}
