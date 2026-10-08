import '../../international/language_controller.dart';
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
        SnackBar(content: Text(SkoLanguageController.trParams('モジュール設定を保存できませんでした: {error}', {'error': error}))),
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
        SnackBar(content: Text(SkoLanguageController.trParams('サブ管理者表示設定を保存できませんでした: {error}', {'error': error}))),
      );
    }
  }

  String _subAdminLabel(String key) => switch (key) {
        'people' => SkoLanguageController.tr('社員データ'),
        'company_deliveries' => SkoLanguageController.tr('協力会社'),
        'vehicle_routes' => SkoLanguageController.tr('車両ルート'),
        'employee_register' => SkoLanguageController.tr('従業員登録'),
        'approvals' => SkoLanguageController.tr('承認待ち'),
        'documents' => SkoLanguageController.tr('必要書類'),
        'employee_qualifications' => SkoLanguageController.tr('従業員資格'),
        'signatures' => SkoLanguageController.tr('サイン一覧'),
        _ => key,
      };

  @override
  Widget build(BuildContext context) {
    SkoLanguageController.watch(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(SkoLanguageController.tr('利用機能のON／OFF')),
        actions: [
          IconButton(
            tooltip: SkoLanguageController.tr('再読み込み'),
            onPressed: _loading ? null : _load,
            icon: Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: _loading
            ? Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        _canManage
                            ? SkoLanguageController.tr('会社全員に共通の設定です。使う機能はON、使わない機能はOFFにしてください。OFFでも登録データは残り、ONに戻すと再び利用できます。')
                            : SkoLanguageController.tr('会社共通の利用機能を確認できます。ON／OFFの変更は管理者が行います。'),
                      ),
                    ),
                  ),
                  if (_error != null) ...[
                    SizedBox(height: 12),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          SkoLanguageController.tr(_error!),
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                    ),
                  ],
                  SizedBox(height: 16),
                  Text(
                    SkoLanguageController.tr('常に利用する基本機能'),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  SizedBox(height: 8),
                  for (final module
                      in [ProductModules.people, ProductModules.settings])
                    Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: Icon(Icons.lock_outline),
                        title: Text(SkoLanguageController.tr(module.label)),
                        subtitle: Text(SkoLanguageController.tr(module.description)),
                        trailing: Text(SkoLanguageController.tr('ON')),
                      ),
                    ),
                  SizedBox(height: 18),
                  Text(
                    SkoLanguageController.tr('サブ管理者に表示する機能'),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    SkoLanguageController.tr('一般ユーザー用・閲覧者用は自動で表示されます。下記はチェックONの項目だけサブ管理者へ表示します。'),
                  ),
                  SizedBox(height: 8),
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
                  SizedBox(height: 18),
                  Text(
                    SkoLanguageController.tr('会社で使う機能（ON／OFF）'),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  SizedBox(height: 8),
                  for (final module in ProductModules.optional)
                    Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: SwitchListTile(
                        title: Text(SkoLanguageController.tr(module.label)),
                        subtitle: Text(SkoLanguageController.tr(module.description)),
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
