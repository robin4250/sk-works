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
  bool _loading = true;
  String? _error;

  static const _permissionLabels = <String, String>{
    'can_approve_daily_report_edits': '日報修正の承認',
    'can_manage_attendance': '出勤・人区管理',
    'can_manage_people': '人員管理',
    'can_view_invoices': '請求書を見る',
    'can_manage_invoices': '請求書設定・管理',
    'can_view_admin_site_data': '管理者用現場データを見る',
    'can_manage_admin_site_data': '管理者用現場データを編集',
    'can_manage_payroll': '給与管理',
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
      final items = await repository.loadAll();
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
                    itemCount: _items.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final item = _items[index];
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
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => _edit(index),
                        ),
                      );
                    },
                  ),
      ),
    );
  }

  Future<void> _edit(int index) async {
    final current = _items[index];
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
                      initialValue: role == 'owner' ? 'admin' : role,
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
                            '管理者はすべての管理機能を利用できます。',
                          ),
                        ),
                      )
                    else
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
        'owner' => '管理者',
        'admin' => '管理者',
        'manager' => 'サブ管理者',
        _ => '一般ユーザー',
      };
}
