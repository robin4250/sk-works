import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../notifications/notification_bell.dart';
import '../help/floating_help_controller.dart';
import '../../branding/sko_theme.dart';
import '../../data/supabase_backend.dart';
import '../../international/language_controller.dart';
import 'company_module_settings_page.dart';
import 'company_rate_settings_page.dart';
import 'company_payroll_rates_page.dart';
import 'company_allowance_identity_entry.dart';
import 'master_device_management_page.dart';
import 'master_device_repository.dart';
import 'master_feature_controls_page.dart';
import 'master_operations_dashboard_page.dart';
import 'master_protected_page.dart';
import 'master_recovery_contacts_page.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _loading = true;
  bool _canManageCompany = false;
  bool _isMasterAdmin = false;
  String? _companyId;
  bool _canReadPayrollRates = false;
  String? _loadError;
  String _languageCode = SkoLanguageController.languageCode;
  bool _floatingHelpEnabled = true;
  bool _appNotificationSoundEnabled = true;

  bool get _usesCloud => SupabaseBackend.isInitialized;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });

    try {
      await FloatingHelpController.load();
      _floatingHelpEnabled = FloatingHelpController.enabled.value;
      final personalPrefs = await SharedPreferences.getInstance();
      _appNotificationSoundEnabled =
          personalPrefs.getBool('sko_app_notification_sound_enabled') ?? true;
      if (_usesCloud) {
        await _loadFromCloud();
      }
    } catch (error) {
      _loadError = '設定の読み込みに失敗しました: $error';
    }

    if (!mounted) return;
    setState(() => _loading = false);
  }

  Future<void> _loadFromCloud() async {
    final user = SupabaseBackend.client.auth.currentUser;
    if (user == null) {
      throw StateError('ログイン情報がありません。');
    }

    final memberships = await SupabaseBackend.client
        .from('company_members')
        .select('company_id, role')
        .eq('user_id', user.id)
        .limit(1);
    if (memberships.isEmpty) {
      throw StateError('会社への所属情報がありません。');
    }

    final companyId = memberships.first['company_id'] as String;
    final role = memberships.first['role']?.toString() ?? 'viewer';
    _canManageCompany = role == 'owner' || role == 'admin';
    _canReadPayrollRates = _canManageCompany || role == 'viewer';

    final masterRepository = MasterDeviceRepository.maybeCreate();
    if (masterRepository != null) {
      try {
        _isMasterAdmin = await masterRepository.isMasterAdmin();
      } catch (_) {
        _isMasterAdmin = false;
      }
    }
    final companies = await SupabaseBackend.client
        .from('companies')
        .select('id')
        .eq('id', companyId)
        .limit(1);
    if (companies.isEmpty) {
      throw StateError('会社情報が見つかりません。');
    }

    _companyId = companyId;
    _languageCode = SkoLanguageController.languageCode;
  }

  Future<void> _setLanguage(String code) async {
    if (_languageCode == code) return;
    setState(() => _languageCode = code);
    try {
      await SkoLanguageController.setLanguage(
        code,
        saveCloud: _usesCloud && _canManageCompany,
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${SkoLanguageController.tr('設定の保存に失敗しました')}: $error',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(SkoLanguageController.tr('設定')),
        actions: const [SkoNotificationBell()],
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _loadError != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.cloud_off_outlined, size: 48),
                          const SizedBox(height: 12),
                          Text(_loadError!, textAlign: TextAlign.center),
                          const SizedBox(height: 16),
                          FilledButton(
                            onPressed: _load,
                            child: const Text('再読み込み'),
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      Text(
                        SkoLanguageController.tr('表示言語'),
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 10),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: SegmentedButton<String>(
                            segments: const [
                              ButtonSegment<String>(
                                value: 'ja',
                                label: Text('日本語'),
                              ),
                              ButtonSegment<String>(
                                value: 'en',
                                label: Text('English'),
                              ),
                            ],
                            selected: {_languageCode},
                            onSelectionChanged: (values) {
                              if (values.isNotEmpty) {
                                _setLanguage(values.first);
                              }
                            },
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        SkoLanguageController.tr('ヘルプ表示'),
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 10),
                      Card(
                        child: SwitchListTile(
                          value: _floatingHelpEnabled,
                          secondary: const Icon(Icons.help_outline),
                          title: Text(
                            SkoLanguageController.tr('フローティングヘルプ'),
                            style: const TextStyle(fontWeight: FontWeight.w900),
                          ),
                          subtitle: Text(
                            SkoLanguageController.tr(
                              'ONにすると画面右下の？ボタンからいつでも使い方を確認できます。ボタンは長押しで好きな位置へ移動できます。',
                            ),
                          ),
                          onChanged: (value) async {
                            setState(() => _floatingHelpEnabled = value);
                            await FloatingHelpController.setEnabled(value);
                          },
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        '通知設定',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 10),
                      Card(
                        child: SwitchListTile(
                          value: _appNotificationSoundEnabled,
                          secondary: Icon(
                            _appNotificationSoundEnabled
                                ? Icons.notifications_active_outlined
                                : Icons.notifications_off_outlined,
                          ),
                          title: const Text(
                            'アプリの通知音設定',
                            style: TextStyle(fontWeight: FontWeight.w900),
                          ),
                          subtitle: const Text(
                            'OFFにするとアプリ全体の通知音を鳴らしません。グループごとの通知音設定とは別です。',
                          ),
                          onChanged: (value) async {
                            setState(
                              () => _appNotificationSoundEnabled = value,
                            );
                            final prefs =
                                await SharedPreferences.getInstance();
                            await prefs.setBool(
                              'sko_app_notification_sound_enabled',
                              value,
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        SkoLanguageController.tr('表示カラー'),
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 10),
                      ValueListenableBuilder<SkoPalette>(
                        valueListenable: SkoThemeController.palette,
                        builder: (context, selectedPalette, _) {
                          return Card(
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    SkoLanguageController.tr('テーマカラー'),
                                    style: TextStyle(
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  const Text(
                                    '文字・アイコン・ボタン・背景などへ一括で反映します。',
                                  ),
                                  const SizedBox(height: 14),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: [
                                      for (final palette in SkoTheme.palettes)
                                        ChoiceChip(
                                          selected:
                                              selectedPalette.key == palette.key,
                                          avatar: CircleAvatar(
                                            radius: 8,
                                            backgroundColor: palette.brand,
                                          ),
                                          label: Text(palette.label),
                                          onSelected: (_) =>
                                              SkoThemeController.setPalette(
                                            palette.key,
                                          ),
                                        ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 24),
                      if (_usesCloud) ...[
                        Card(
                          child: ListTile(
                            leading: const Icon(Icons.cloud_done_outlined),
                            title: const Text('Supabaseクラウド接続中'),
                            subtitle: const Text('この設定は会社のクラウドデータに保存されます'),
                          ),
                        ),
                        const SizedBox(height: 16),
                        if (_canManageCompany) ...[
                          Card(
                            child: ListTile(
                              leading: const Icon(Icons.currency_yen_outlined),
                              title: const Text('消費税・会社手当設定'),
                              subtitle: const Text('消費税率・福利厚生費率・残業・早出・夜勤・休日・任意手当×3'),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () => Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => const CompanyRateSettingsPage(),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],
                        if (_canManageCompany && _companyId != null) ...[
                          CompanyAllowanceIdentityEntry(companyId: _companyId!, canManageCompany: _canManageCompany),
                          const SizedBox(height: 16),
                        ],
                        if (_canReadPayrollRates && _companyId != null) ...[
                          Card(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(23),
                              side: BorderSide(
                                color: Theme.of(context).colorScheme.primary,
                                width: 1.8,
                              ),
                            ),
                            child: Container(
                              margin: const EdgeInsets.all(3),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: Theme.of(context).colorScheme.primary,
                                  width: 1.8,
                                ),
                              ),
                              child: ListTile(
                                leading: const Icon(Icons.percent_outlined),
                                title: const Text('会社共通の税率・保険料率'),
                                subtitle: Text(_canManageCompany
                                    ? '社会保険・雇用保険・所得税資料'
                                    : '料率・適用月・情報元の閲覧'),
                                trailing: const Icon(Icons.chevron_right),
                                onTap: () => Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => CompanyPayrollRatesPage(
                                      companyId: _companyId!,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],
                        if (_isMasterAdmin) ...[
                          Card(
                            child: ListTile(
                              leading: const Icon(Icons.widgets_outlined),
                              title: const Text('利用機能のON／OFF（保管中）'),
                              subtitle: const Text('用途は検討中。既存設定の確認のみ'),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () => Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => const MasterProtectedPage(
                                    title: '利用機能のON／OFF（保管中）',
                                    child: CompanyModuleSettingsPage(),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Card(
                            child: ListTile(
                              leading: const Icon(Icons.dashboard_outlined),
                              title: const Text('Master ダッシュボード'),
                              subtitle: const Text('SKO全体の集計値を確認'),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () => Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => const MasterProtectedPage(
                                    title: 'Master ダッシュボード',
                                    child: MasterOperationsDashboardPage(),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Card(
                            child: ListTile(
                              leading: const Icon(Icons.tune_outlined),
                              title: const Text('Master 機能設定'),
                              subtitle: const Text('車両管理・ルート配車を安全にON / OFF'),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () => Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => const MasterProtectedPage(
                                    title: 'Master 機能設定',
                                    child: MasterFeatureControlsPage(),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Card(
                            child: ListTile(
                              leading: const Icon(Icons.admin_panel_settings_outlined),
                              title: const Text('マスターデバイス管理'),
                              subtitle: const Text('信頼済み端末の確認・ロック・登録解除'),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () => Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => const MasterProtectedPage(
                                    title: 'マスターデバイス管理',
                                    child: MasterDeviceManagementPage(),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Card(
                            child: ListTile(
                              leading: const Icon(Icons.emergency_outlined),
                              title: const Text('Master 緊急復旧設定'),
                              subtitle: const Text('2系統の復旧メールを安全に登録'),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () => Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => const MasterProtectedPage(
                                    title: 'Master 緊急復旧設定',
                                    child: MasterRecoveryContactsPage(),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],
                      ],
                    ],
                  ),
      ),
    );
  }
}
