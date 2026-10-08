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
      ]);
      if (!mounted) return;
      setState(() {
        _states = Map<String, bool>.from(values[0] as Map);
        _subAdminStates = Map<String, bool>.from(values[1] as Map);
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
        title: Text(SkoLanguageController.tr('利用機能のON／OFF（保管中）')),
        actions: [
          IconButton(
            tooltip: 'この画面について',
            icon: const Icon(Icons.help_outline),
            onPressed: () => showDialog<void>(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('利用機能のON／OFF（保管中）'),
                content: const Text('既に作成した画面をMaster側に保管しています。用途は今後検討します。現在は所属会社の既存設定を読み取り専用で確認し、会社所属がない場合や取得権限がない場合は表示できません。アプリ全体の機能や公開範囲は変更しません。担当者ごとの業務権限設定とは別です。保存済みの設定・登録データ・履歴は変更しません。'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('確認'),
                  ),
                ],
              ),
            ),
          ),
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
                        SkoLanguageController.tr('Master側に保管中です。用途は今後検討します。既存の会社設定は読み取り専用で、個人別の業務権限ではありません。設定・登録データは変更しません。'),
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
                    SkoLanguageController.tr('既存のサブ管理者共通表示設定（保管中）'),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    SkoLanguageController.tr('保存済みの共通表示設定です。Aさん・Bさんなど個人別の業務権限を設定するものではありません。'),
                  ),
                  SizedBox(height: 8),
                  for (final key
                      in CompanyModuleSettingsRepository.subAdminHomeKeys)
                    Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: CheckboxListTile(
                        title: Text(_subAdminLabel(key)),
                        value: _subAdminStates[key] ?? false,
                        onChanged: null,
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
                        onChanged: null,
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}
