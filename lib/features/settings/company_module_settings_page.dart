import 'package:flutter/material.dart';

import 'company_module_settings_repository.dart';
import 'product_modules.dart';

class CompanyModuleSettingsPage extends StatefulWidget {
  const CompanyModuleSettingsPage({super.key});

  @override
  State<CompanyModuleSettingsPage> createState() =>
      _CompanyModuleSettingsPageState();
}

class _CompanyModuleSettingsPageState extends State<CompanyModuleSettingsPage> {
  final _repository = CompanyModuleSettingsRepository.maybeCreate();

  bool _loading = true;
  bool _canManage = false;
  String? _error;
  Map<String, bool> _states = const {};
  Map<String, bool> _subAdminStates = const {};

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
        _error = 'Supabase接続またはログイン状態を確認してください。';
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final values = await Future.wait([
        repository.loadOptionalModuleStates(),
        repository.loadSubAdminHomeStates(),
        repository.canManage(),
      ]);
      if (!mounted) return;
      setState(() {
        _states = Map<String, bool>.from(values[0] as Map);
        _subAdminStates = Map<String, bool>.from(values[1] as Map);
        _canManage = values[2] as bool;
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

  Future<void> _setEnabled(String key, bool enabled) async {
    final repository = _repository;
    if (repository == null || !_canManage) return;

    final previous = _states[key] ?? true;
    setState(() => _states = {..._states, key: enabled});

    try {
      await repository.setEnabled(key, enabled);
    } catch (error) {
      if (!mounted) return;
      setState(() => _states = {..._states, key: previous});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('モジュール設定を保存できませんでした: $error')),
      );
    }
  }

  Future<void> _setSubAdminEnabled(String key, bool enabled) async {
    final repository = _repository;
    if (repository == null || !_canManage) return;

    final previous = _subAdminStates[key] ?? false;
    setState(() => _subAdminStates = {..._subAdminStates, key: enabled});

    try {
      await repository.setSubAdminHomeEnabled(key, enabled);
    } catch (error) {
      if (!mounted) return;
      setState(() => _subAdminStates = {..._subAdminStates, key: previous});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('サブ管理者表示設定を保存できませんでした: $error')),
      );
    }
  }

  String _subAdminLabel(String key) => switch (key) {
        'people' => '社員データ',
        'company_deliveries' => '協力会社',
        'vehicle_routes' => '車両ルート',
        'employee_register' => '従業員登録',
        'approvals' => '承認待ち',
        'employee_onboarding_approvals' => '本登録承認',
        'documents' => '必要書類',
        'employee_qualifications' => '従業員資格',
        'signatures' => 'サイン一覧',
        _ => key,
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('利用機能の設定'),
        actions: [
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
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        _canManage
                            ? '使わない機能をOFFにしても、過去のデータは削除されません。必要になったら再びONにできます。'
                            : '利用機能の状態を確認できます。変更は会社のオーナーまたは管理者のみ行えます。',
                      ),
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          _error!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  Text(
                    '常に利用する基本機能',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const SizedBox(height: 8),
                  for (final module
                      in [ProductModules.people, ProductModules.settings])
                    Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: const Icon(Icons.lock_outline),
                        title: Text(module.label),
                        subtitle: Text(module.description),
                        trailing: const Text('ON'),
                      ),
                    ),
                  const SizedBox(height: 18),
                  Text(
                    'サブ管理者に表示する機能',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    '一般ユーザー用・閲覧者用は自動で表示されます。下記はチェックONの項目だけサブ管理者へ表示します。',
                  ),
                  const SizedBox(height: 8),
                  for (final key
                      in CompanyModuleSettingsRepository.subAdminHomeKeys)
                    Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: CheckboxListTile(
                        title: Text(_subAdminLabel(key)),
                        value: _subAdminStates[key] ?? false,
                        onChanged: _canManage
                            ? (value) => _setSubAdminEnabled(key, value == true)
                            : null,
                      ),
                    ),
                  const SizedBox(height: 18),
                  Text(
                    '任意機能',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const SizedBox(height: 8),
                  for (final module in ProductModules.optional)
                    Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: SwitchListTile(
                        title: Text(module.label),
                        subtitle: Text(module.description),
                        value: _states[module.key] ?? true,
                        onChanged: _canManage
                            ? (enabled) => _setEnabled(module.key, enabled)
                            : null,
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}
