import 'package:flutter/material.dart';

import 'worker_attendance_sheet_repository.dart';

class AttendanceSharingPage extends StatefulWidget {
  const AttendanceSharingPage({super.key, required this.repository});

  final WorkerAttendanceSheetRepository repository;

  @override
  State<AttendanceSharingPage> createState() => _AttendanceSharingPageState();
}

class _AttendanceSharingPageState extends State<AttendanceSharingPage> {
  late Future<List<Map<String, dynamic>>> _rules;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _rules = widget.repository.manageAttendanceSharing();
  }

  Future<void> _change(Map<String, dynamic> rule) async {
    final disable = rule['first_work_date'] != null;
    final now = DateTime.now();
    final start = disable
        ? null
        : await showDatePicker(
            context: context,
            helpText: '共有する出勤の開始日',
            initialDate: DateTime(now.year, now.month, now.day),
            firstDate: DateTime(2000),
            lastDate: DateTime(now.year + 1, 12, 31),
          );
    if (!mounted || (!disable && start == null)) return;
    final agreed = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(disable ? '勤怠共有を停止' : '勤怠共有を許可'),
        content: Text(
          disable
              ? '「${rule['site_name']}」の勤怠共有を停止します。'
              : '「${rule['site_name']}」の勤怠を「${rule['parent_name']}」と共有します。相手が同じ現場の共有を許可した場合、上位の取引会社にも作業者名・日付・勤務実績が表示されます。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog),
            child: const Text('戻る'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: Text(disable ? '停止' : '許可'),
          ),
        ],
      ),
    );
    if (!mounted || agreed != true) return;
    setState(() => _saving = true);
    try {
      final rows = await widget.repository.manageAttendanceSharing(
        itemId: rule['item_id'] as String,
        start: start,
        disable: disable,
      );
      if (mounted) setState(() => _rules = Future.value(rows));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('勤怠共有を変更できませんでした。')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('勤怠共有')),
    body: FutureBuilder(
      future: _rules,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Center(
            child: Text('勤怠共有の設定を開けませんでした。管理者権限と接続状況を確認してください。'),
          );
        }
        final rows = snapshot.data;
        if (rows == null) {
          return const Center(child: CircularProgressIndicator());
        }
        if (rows.isEmpty) {
          return const Center(child: Text('承認済みの上位会社との現場共有がありません。'));
        }
        return ListView(
          children: [
            for (final row in rows)
              ListTile(
                title: Text(row['site_name'] as String),
                subtitle: Text(
                  '${row['parent_name']}  ${row['first_work_date'] ?? '共有なし'}',
                ),
                trailing: TextButton(
                  onPressed: _saving ? null : () => _change(row),
                  child: Text(row['first_work_date'] == null ? '許可' : '停止'),
                ),
              ),
          ],
        );
      },
    ),
  );
}
