import 'package:flutter/material.dart';

import 'people_cloud_repository.dart';
import 'worker_personnel_approver_settings_page.dart';

class WorkerPersonnelChangeApprovalsPage extends StatefulWidget {
  const WorkerPersonnelChangeApprovalsPage({super.key, this.initialRequestId});

  final String? initialRequestId;

  @override
  State<WorkerPersonnelChangeApprovalsPage> createState() =>
      _WorkerPersonnelChangeApprovalsPageState();
}

class _WorkerPersonnelChangeApprovalsPageState
    extends State<WorkerPersonnelChangeApprovalsPage> {
  final _repository = PeopleCloudRepository.maybeCreate();
  List<Map<String, dynamic>> _rows = const [];
  bool _loading = true;
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
        _error = '社員個人情報の変更承認を利用できません。';
      });
      return;
    }
    try {
      final rows = await repository.loadPendingPersonnelChanges();
      if (!mounted) return;
      final targetId = widget.initialRequestId?.trim() ?? '';
      final ordered = rows.toList(growable: true);
      if (targetId.isNotEmpty) {
        ordered.sort((a, b) {
          final aTarget = a['id']?.toString() == targetId;
          final bTarget = b['id']?.toString() == targetId;
          if (aTarget == bTarget) return 0;
          return aTarget ? -1 : 1;
        });
      }
      setState(() {
        _rows = List<Map<String, dynamic>>.unmodifiable(ordered);
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

  Future<void> _decide(Map<String, dynamic> row, bool approve) async {
    final repository = _repository;
    final id = row['id']?.toString() ?? '';
    if (repository == null || id.isEmpty) return;

    final count = (row['approval_count'] as num?)?.toInt() ?? 0;
    final required = (row['required_approvals'] as num?)?.toInt() ?? 1;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(approve ? 'この変更を承認しますか？' : 'この変更を拒否しますか？'),
        content: Text(
          approve
              ? '現在 $count/$required 名承認済みです。登録済み承認者が必要人数に達すると正式反映されます。'
              : '拒否するとこの変更申請は終了します。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('戻る'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(approve ? '承認する' : '拒否する'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      final result = await repository.decidePersonnelChange(
        requestId: id,
        approve: approve,
      );
      if (!mounted) return;
      final status = result['status']?.toString() ?? '';
      final approvalCount =
          (result['approval_count'] as num?)?.toInt() ?? count;
      final resultRequired =
          (result['required_approvals'] as num?)?.toInt() ?? required;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            status == 'approved'
                ? '$resultRequired名の承認が完了し、社員個人情報へ反映しました。'
                : status == 'rejected'
                ? '変更申請を拒否しました。'
                : '承認しました。現在 $approvalCount/$resultRequired 名です。',
          ),
        ),
      );
      await _load();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '処理できませんでした: ${PeopleCloudRepository.personnelSaveError(error)}',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          '社員個人情報の変更承認',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        actions: [
          IconButton(
            tooltip: '承認者設定',
            onPressed: () async {
              await Navigator.of(context).push<bool>(
                MaterialPageRoute(
                  builder: (_) => const WorkerPersonnelApproverSettingsPage(),
                ),
              );
              if (!mounted) return;
              await _load();
            },
            icon: const Icon(Icons.manage_accounts_outlined),
          ),
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
            ? Center(child: Text(_error!, textAlign: TextAlign.center))
            : _rows.isEmpty
            ? const Center(
                child: Text(
                  '変更承認待ちはありません',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              )
            : ListView.separated(
                padding: const EdgeInsets.all(12),
                itemCount: _rows.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final row = _rows[index];
                  final proposed = row['proposed'] is Map
                      ? Map<String, dynamic>.from(row['proposed'] as Map)
                      : const <String, dynamic>{};
                  final approvalCount =
                      (row['approval_count'] as num?)?.toInt() ?? 0;
                  final required =
                      (row['required_approvals'] as num?)?.toInt() ?? 1;

                  return Card(
                    child: ExpansionTile(
                      title: Text(
                        row['worker_name']?.toString() ?? '社員',
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                      subtitle: Text('承認 $approvalCount/$required 名'),
                      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      children: [
                        _line('名前', proposed['name']),
                        _line('血液型', proposed['blood_type']),
                        _line('社員番号', proposed['employee_number']),
                        _line('所属', proposed['department']),
                        _line('職種', proposed['role']),
                        _line('入社日', proposed['hire_date']),
                        _line('電話番号', proposed['phone']),
                        _line('住所', proposed['address']),
                        const Divider(),
                        _line('緊急連絡先氏名', proposed['emergency_name']),
                        _line('続柄', proposed['emergency_relation']),
                        _line('緊急電話番号', proposed['emergency_phone']),
                        _line('緊急住所', proposed['emergency_address']),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () => _decide(row, false),
                                child: const Text('拒否'),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: FilledButton(
                                onPressed: () => _decide(row, true),
                                child: const Text('承認'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              ),
      ),
    );
  }

  Widget _line(String label, Object? value) {
    final text = value?.toString().trim() ?? '';
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
          Expanded(child: Text(text.isEmpty ? '未登録' : text)),
        ],
      ),
    );
  }
}
