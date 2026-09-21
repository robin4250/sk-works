import 'package:flutter/material.dart';

import '../notifications/notification_bell.dart';
import 'member_permission_repository.dart';

class MemberPermissionPage extends StatefulWidget {
  const MemberPermissionPage({super.key});

  @override
  State<MemberPermissionPage> createState() => _MemberPermissionPageState();
}

class _MemberPermissionPageState extends State<MemberPermissionPage> {
  final _repository = MemberPermissionRepository.maybeCreate();

  List<MemberPermissionRecord> _items = const [];
  List<ApprovalAssigneeRecord> _approvalAssignees = const [];
  bool _loading = true;
  String? _error;

  static const _permissionLabels = <String, String>{
    'can_manage_attendance': '出勤・人区管理',
    'can_manage_people': '人員管理',
    'can_manage_partner_chat': '協力会社チャット',
  };

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
        _error = '権限設定を利用できません。';
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final values = await Future.wait([
        repository.loadAll(),
        repository.loadApprovalAssignees(),
      ]);
      if (!mounted) return;
      setState(() {
        _items = values[0] as List<MemberPermissionRecord>;
        _approvalAssignees = values[1] as List<ApprovalAssigneeRecord>;
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
    final selected = _approvalAssignees.where((item) => item.isAssignee).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'アプリ利用者の権限',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        actions: const [SkoNotificationBell()],
      ),
      body: SafeArea(
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
                          const SizedBox(height: 16),
                          FilledButton.icon(
                            onPressed: _load,
                            icon: const Icon(Icons.refresh),
                            label: const Text('再読み込み'),
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: _items.length + 1,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      if (index == 0) {
                        return Card(
                          color: Theme.of(context).colorScheme.primaryContainer,
                          child: ListTile(
                            leading: const CircleAvatar(
                              child: Icon(Icons.fact_check_outlined),
                            ),
                            title: const Text(
                              '承認担当者（1〜3名）',
                              style: TextStyle(fontWeight: FontWeight.w900),
                            ),
                            subtitle: Text(
                              selected.isEmpty
                                  ? '承認担当者を設定してください'
                                  : selected
                                      .map((item) => item.displayName)
                                      .join(' / '),
                            ),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: _editApprovalAssignees,
                          ),
                        );
                      }

                      final item = _items[index - 1];
                      return Card(
                        child: ListTile(
                          leading: const CircleAvatar(
                            child: Icon(Icons.manage_accounts_outlined),
                          ),
                          title: Text(
                            item.displayName,
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          subtitle: Text(_roleLabel(item.role)),
                          trailing: item.role == 'owner'
                              ? const Icon(Icons.lock_outline)
                              : const Icon(Icons.chevron_right),
                          onTap: item.role == 'owner'
                              ? null
                              : () => _edit(index - 1),
                        ),
                      );
                    },
                  ),
      ),
    );
  }

  Future<void> _editApprovalAssignees() async {
    final repository = _repository;
    if (repository == null) return;

    var rows = List<ApprovalAssigneeRecord>.from(_approvalAssignees);

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final selectedCount = rows.where((item) => item.isAssignee).length;

          return AlertDialog(
            title: const Text('承認担当者を設定'),
            content: SizedBox(
              width: 520,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      '管理者が、サブ管理者以上から1〜3名を設定します。'
                      '日報修正などの承認通知は設定された担当者へ届きます。'
                      '1名設定にも対応するため、個人事業主・一人親方でも利用できます。',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '現在 $selectedCount / 3名',
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 8),
                    for (var index = 0; index < rows.length; index++)
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(rows[index].displayName),
                        subtitle: Text(_roleLabel(rows[index].role)),
                        value: rows[index].isAssignee,
                        onChanged: (enabled) async {
                          final value = enabled ?? false;
                          final current = rows[index];

                          if (value && !current.isAssignee && selectedCount >= 3) {
                            await _showApprovalLimitDialog(
                              parentContext: dialogContext,
                              candidate: current,
                              rows: rows,
                              onChanged: (updated) {
                                rows = updated;
                                setDialogState(() {});
                              },
                            );
                            return;
                          }

                          if (!value && current.isAssignee && selectedCount <= 1) {
                            await showDialog<void>(
                              context: dialogContext,
                              builder: (context) => AlertDialog(
                                title: const Text('承認担当者は1名以上必要です'),
                                content: const Text(
                                  '先に別の管理者またはサブ管理者を承認担当者へ追加してから、この担当者を外してください。',
                                ),
                                actions: [
                                  FilledButton(
                                    onPressed: () => Navigator.pop(context),
                                    child: const Text('閉じる'),
                                  ),
                                ],
                              ),
                            );
                            return;
                          }

                          try {
                            await repository.setApprovalAssignee(
                              userId: current.userId,
                              enabled: value,
                            );
                            rows[index] = ApprovalAssigneeRecord(
                              userId: current.userId,
                              displayName: current.displayName,
                              role: current.role,
                              isAssignee: value,
                            );
                            setDialogState(() {});
                          } catch (error) {
                            if (!dialogContext.mounted) return;
                            ScaffoldMessenger.of(dialogContext).showSnackBar(
                              SnackBar(content: Text('承認担当者を変更できませんでした: $error')),
                            );
                          }
                        },
                      ),
                  ],
                ),
              ),
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('閉じる'),
              ),
            ],
          );
        },
      ),
    );

    await _load();
  }

  Future<void> _showApprovalLimitDialog({
    required BuildContext parentContext,
    required ApprovalAssigneeRecord candidate,
    required List<ApprovalAssigneeRecord> rows,
    required ValueChanged<List<ApprovalAssigneeRecord>> onChanged,
  }) async {
    final repository = _repository;
    if (repository == null) return;
    final selected = rows.where((item) => item.isAssignee).toList();

    await showDialog<void>(
      context: parentContext,
      builder: (limitContext) => AlertDialog(
        title: const Text('承認担当者は最大3名です'),
        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '${candidate.displayName}さんへ承認権限を付けるには、'
                '現在登録中の3名のうち誰か1名を外してください。',
              ),
              const SizedBox(height: 12),
              for (final current in selected)
                Card(
                  child: ListTile(
                    title: Text(current.displayName),
                    subtitle: Text(_roleLabel(current.role)),
                    trailing: TextButton(
                      onPressed: () async {
                        try {
                          await repository.setApprovalAssignee(
                            userId: current.userId,
                            enabled: false,
                          );
                          await repository.setApprovalAssignee(
                            userId: candidate.userId,
                            enabled: true,
                          );
                          final updated = [
                            for (final row in rows)
                              ApprovalAssigneeRecord(
                                userId: row.userId,
                                displayName: row.displayName,
                                role: row.role,
                                isAssignee: row.userId == current.userId
                                    ? false
                                    : row.userId == candidate.userId
                                        ? true
                                        : row.isAssignee,
                              ),
                          ];
                          onChanged(updated);
                          if (limitContext.mounted) {
                            Navigator.pop(limitContext);
                          }
                        } catch (error) {
                          if (!limitContext.mounted) return;
                          ScaffoldMessenger.of(limitContext).showSnackBar(
                            SnackBar(content: Text('入れ替えできませんでした: $error')),
                          );
                        }
                      },
                      child: const Text('この人を外す'),
                    ),
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(limitContext),
            child: const Text('閉じる'),
          ),
        ],
      ),
    );
  }

  Future<void> _edit(int index) async {
    final current = _items[index];
    if (current.role == 'owner') return;
    var role = current.role;
    final permissions = Map<String, bool>.from(current.permissions);

    final saved = await showDialog<MemberPermissionRecord>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final fullAdmin = role == 'admin';
          return AlertDialog(
            title: Text(current.displayName),
            content: SizedBox(
              width: 500,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<String>(
                      initialValue: role,
                      decoration: const InputDecoration(
                        labelText: '役割',
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'admin',
                          child: Text('管理者'),
                        ),
                        DropdownMenuItem(
                          value: 'manager',
                          child: Text('サブ管理者'),
                        ),
                        DropdownMenuItem(
                          value: 'viewer',
                          child: Text('一般ユーザー'),
                        ),
                      ],
                      onChanged: (value) {
                        if (value == null) return;
                        setDialogState(() => role = value);
                      },
                    ),
                    const SizedBox(height: 12),
                    if (fullAdmin)
                      const Card(
                        child: Padding(
                          padding: EdgeInsets.all(14),
                          child: Text(
                            '管理者はすべての管理機能を利用できます。'
                            '承認担当者かどうかは、画面上部の「承認担当者（1〜3名）」から別に設定します。',
                          ),
                        ),
                      )
                    else ...[
                      if (role == 'manager')
                        const Card(
                          child: Padding(
                            padding: EdgeInsets.all(14),
                            child: Text(
                              'サブ管理者は請求書・管理者用現場データ（現場単価）・給与管理を利用できません。'
                              '本人の給与明細は一般ユーザーと同じように第2認証で確認できます。',
                            ),
                          ),
                        ),
                      for (final entry in _permissionLabels.entries)
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(entry.value),
                          value: permissions[entry.key] ?? false,
                          onChanged: (value) => setDialogState(
                            () => permissions[entry.key] = value,
                          ),
                        ),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('キャンセル'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(
                  dialogContext,
                  current.copyWith(
                    role: role,
                    permissions: permissions,
                  ),
                ),
                child: const Text('保存'),
              ),
            ],
          );
        },
      ),
    );

    if (saved == null) return;

    try {
      await _repository?.save(saved);
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('権限設定を保存しました')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('保存できませんでした: $error')),
      );
    }
  }

  static String _roleLabel(String role) => switch (role) {
        'owner' => '管理者（初回登録）',
        'admin' => '管理者',
        'manager' => 'サブ管理者',
        _ => '一般ユーザー',
      };
}
