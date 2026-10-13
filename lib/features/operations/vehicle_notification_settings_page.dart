import 'package:flutter/material.dart';

import 'vehicle_notification_settings_repository.dart';

class VehicleNotificationSettingsPage extends StatefulWidget {
  const VehicleNotificationSettingsPage({
    super.key,
    required this.vehicleId,
    required this.vehicleName,
  });

  final String vehicleId;
  final String vehicleName;

  @override
  State<VehicleNotificationSettingsPage> createState() =>
      _VehicleNotificationSettingsPageState();
}

class _VehicleNotificationSettingsPageState
    extends State<VehicleNotificationSettingsPage> {
  final _repository = VehicleNotificationSettingsRepository.maybeCreate();
  VehicleNotificationSettings? _settings;
  Set<String> _selected = {};
  String? _error;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final repository = _repository;
      if (repository == null) throw StateError('ログインが必要です。');
      final settings = await repository.load(widget.vehicleId);
      if (!mounted) return;
      setState(() {
        _settings = settings;
        _selected = (settings.configured
                ? settings.userIds
                : settings.suggestedUserIds)
            .toSet();
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = '車両管理者の設定を利用できません。設定機能の準備状況を確認してください。');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    final repository = _repository;
    final settings = _settings;
    if (repository == null ||
        settings == null ||
        _saving ||
        !settings.canSave(_selected)) {
      return;
    }
    setState(() => _saving = true);
    try {
      await repository.save(widget.vehicleId, _selected.toList());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('車両管理者を保存しました。')),
      );
      await _load();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('保存結果を確認できません。再読込して設定を確認してください。')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = _settings;
    final candidates = settings?.candidates ?? const <Map<String, dynamic>>[];
    final available = candidates.map((row) => row['user_id']).toSet();
    final unresolved = _selected.where((id) => !available.contains(id)).toList();
    final editable = settings?.enabled == true && !_saving;
    return Scaffold(
      appBar: AppBar(title: const Text('車両管理者')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_error!),
                      TextButton(onPressed: _load, child: const Text('再読込')),
                    ],
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Text(widget.vehicleName),
                    const SizedBox(height: 12),
                    const Text('通知を受け取る車両管理者を1〜3名選択します。会社の管理権限は変更しません。'),
                    if (settings?.configured == false &&
                        settings!.suggestedUserIds.isNotEmpty)
                      const Text('未登録です。初期候補は操作中の管理者1名です。保存するまで登録されません。'),
                    if (settings?.configured == false &&
                        settings!.suggestedUserIds.isEmpty)
                      const Text('未登録です。管理者を1〜3名選択してください。保存するまで登録されません。'),
                    if (settings?.enabled != true)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Text('車両通知は現在利用停止中です。管理者の変更・保存はできません。'),
                      ),
                    for (final row in candidates)
                      CheckboxListTile(
                        title: Text(row['name']?.toString() ?? '氏名未登録'),
                        subtitle: Text(_roleLabel(row['role']?.toString())),
                        value: _selected.contains(row['user_id']),
                        onChanged: !editable
                            ? null
                            : (value) {
                                final id = row['user_id'].toString();
                                if (value == true && _selected.length >= 3) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('車両管理者は3名までです。')),
                                  );
                                  return;
                                }
                                setState(() {
                                  if (value == true) {
                                    _selected.add(id);
                                  } else {
                                    _selected.remove(id);
                                  }
                                });
                              },
                      ),
                    for (final id in unresolved)
                      ListTile(
                        title: const Text('保存済みの受信者を選択候補として確認できません'),
                        subtitle: const Text('登録済みの設定は自動削除していません。変更する場合は選択を外してください。'),
                        trailing: TextButton(
                          onPressed: editable
                              ? () => setState(() => _selected.remove(id))
                              : null,
                          child: const Text('外す'),
                        ),
                      ),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: !_saving && settings!.canSave(_selected)
                          ? _save
                          : null,
                      child: Text(_saving ? '保存中…' : '管理者を保存'),
                    ),
                    const SizedBox(height: 16),
                    const ExpansionTile(
                      leading: Icon(Icons.help_outline),
                      title: Text('車両管理者の設定について'),
                      children: [
                        Padding(
                          padding: EdgeInsets.all(12),
                          child: Text('管理者・サブ管理者・閲覧者など、自社の選択候補から通知先を指定します。一般の会社管理権限は付与しません。外部メール送信の設定ではありません。通知停止中は登録できません。'),
                        ),
                      ],
                    ),
                  ],
                ),
    );
  }

  static String _roleLabel(String? role) => switch (role) {
        'owner' || 'admin' => '管理者',
        'manager' => 'サブ管理者',
        'viewer' => '閲覧者',
        _ => 'メンバー',
      };
}
