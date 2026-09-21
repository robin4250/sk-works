import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../notifications/notification_bell.dart';
import '../../branding/product_brand.dart';
import '../../data/supabase_backend.dart';
import 'company_module_settings_page.dart';
import 'company_rate_settings_page.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _companyName = TextEditingController(text: ProductBrand.displayName);
  final _taxRate = TextEditingController(text: '10');
  final _defaultUnitPrice = TextEditingController(text: '25000');
  bool _loading = true;
  bool _saving = false;
  bool _canManageCompany = false;
  String? _companyId;
  String? _loadError;
  String _detailMode = 'siteBreakdownOnInvoice';

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
      if (_usesCloud) {
        await _loadFromCloud();
      } else {
        await _loadFromLocal();
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
    final companies = await SupabaseBackend.client
        .from('companies')
        .select(
          'id, name, tax_rate, default_unit_price, default_invoice_detail_mode',
        )
        .eq('id', companyId)
        .limit(1);
    if (companies.isEmpty) {
      throw StateError('会社情報が見つかりません。');
    }

    final company = companies.first;
    _companyId = companyId;
    _companyName.text = company['name'] as String? ?? ProductBrand.displayName;
    _taxRate.text = (company['tax_rate'] ?? 10).toString();
    _defaultUnitPrice.text = (company['default_unit_price'] ?? 25000).toString();
    _detailMode = _fromDatabaseDetailMode(
      company['default_invoice_detail_mode'] as String?,
    );
  }

  Future<void> _loadFromLocal() async {
    final prefs = await SharedPreferences.getInstance();
    _companyName.text = prefs.getString('settings_company_name') ?? ProductBrand.displayName;
    _taxRate.text = prefs.getDouble('settings_tax_rate')?.toString() ?? '10';
    _defaultUnitPrice.text =
        prefs.getInt('settings_default_unit_price')?.toString() ?? '25000';
    _detailMode = prefs.getString('settings_invoice_detail_mode') ??
        'siteBreakdownOnInvoice';
  }

  Future<void> _save() async {
    if (_usesCloud && !_canManageCompany) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('会社設定は管理者のみ変更できます')),
      );
      return;
    }

    final taxRate = double.tryParse(_taxRate.text.trim());
    final unitPrice = int.tryParse(_defaultUnitPrice.text.trim());
    if (_companyName.text.trim().isEmpty || taxRate == null || unitPrice == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('入力内容を確認してください')),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      if (_usesCloud) {
        final companyId = _companyId;
        if (companyId == null) {
          throw StateError('会社IDが取得できません。');
        }
        await SupabaseBackend.client.from('companies').update({
          'name': _companyName.text.trim(),
          'tax_rate': taxRate,
          'default_unit_price': unitPrice,
          'default_invoice_detail_mode': _toDatabaseDetailMode(_detailMode),
        }).eq('id', companyId);
      } else {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('settings_company_name', _companyName.text.trim());
        await prefs.setDouble('settings_tax_rate', taxRate);
        await prefs.setInt('settings_default_unit_price', unitPrice);
        await prefs.setString('settings_invoice_detail_mode', _detailMode);
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_usesCloud ? 'クラウドに設定を保存しました' : '設定を保存しました'),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('設定の保存に失敗しました: $error')),
      );
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  String _fromDatabaseDetailMode(String? value) {
    return switch (value) {
      'consolidated_only' => 'consolidatedOnly',
      'site_breakdown_attachment' => 'siteDetailAttachment',
      _ => 'siteBreakdownOnInvoice',
    };
  }

  String _toDatabaseDetailMode(String value) {
    return switch (value) {
      'consolidatedOnly' => 'consolidated_only',
      'siteDetailAttachment' => 'site_breakdown_attachment',
      _ => 'site_breakdown_on_invoice',
    };
  }

  @override
  void dispose() {
    _companyName.dispose();
    _taxRate.dispose();
    _defaultUnitPrice.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('設定'),
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
                      if (_usesCloud) ...[
                        Card(
                          child: ListTile(
                            leading: const Icon(Icons.cloud_done_outlined),
                            title: const Text('Supabaseクラウド接続中'),
                            subtitle: const Text('この設定は会社のクラウドデータに保存されます'),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Card(
                          child: ListTile(
                            leading: const Icon(Icons.widgets_outlined),
                            title: const Text('利用機能の設定'),
                            subtitle: const Text('会社で使う機能をON / OFF'),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => const CompanyModuleSettingsPage(),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        if (_canManageCompany) ...[
                          Card(
                            child: ListTile(
                              leading: const Icon(Icons.currency_yen_outlined),
                              title: const Text('会社単価・手当設定'),
                              subtitle: const Text('福利厚生費率・残業・早出・夜勤・休日・任意手当×3'),
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
                      ],
                      Text(
                        '会社情報',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _companyName,
                        enabled: !_usesCloud || _canManageCompany,
                        decoration: const InputDecoration(labelText: '会社名'),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        '請求設定',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _taxRate,
                        enabled: !_usesCloud || _canManageCompany,
                        keyboardType:
                            const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(labelText: '消費税率（%）'),
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: _defaultUnitPrice,
                        enabled: !_usesCloud || _canManageCompany,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: '標準人工単価（円）'),
                      ),
                      const SizedBox(height: 14),
                      DropdownButtonFormField<String>(
                        initialValue: _detailMode,
                        decoration: const InputDecoration(labelText: '標準の請求明細方式'),
                        items: const [
                          DropdownMenuItem(
                            value: 'consolidatedOnly',
                            child: Text('合算のみ'),
                          ),
                          DropdownMenuItem(
                            value: 'siteBreakdownOnInvoice',
                            child: Text('請求書に現場別内訳'),
                          ),
                          DropdownMenuItem(
                            value: 'siteDetailAttachment',
                            child: Text('現場別明細を別紙添付'),
                          ),
                        ],
                        onChanged: _usesCloud && !_canManageCompany
                            ? null
                            : (value) => setState(() {
                                  _detailMode = value ?? _detailMode;
                                }),
                      ),
                      const SizedBox(height: 24),
                      FilledButton.icon(
                        onPressed: _saving || (_usesCloud && !_canManageCompany)
                            ? null
                            : _save,
                        icon: _saving
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.save_outlined),
                        label: Text(_saving ? '保存中...' : '設定を保存'),
                      ),
                    ],
                  ),
      ),
    );
  }
}
