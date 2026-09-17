import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _companyName = TextEditingController(text: 'SK WORKS');
  final _taxRate = TextEditingController(text: '10');
  final _defaultUnitPrice = TextEditingController(text: '25000');
  bool _loading = true;
  String _detailMode = 'siteBreakdownOnInvoice';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _companyName.text = prefs.getString('settings_company_name') ?? 'SK WORKS';
      _taxRate.text = prefs.getDouble('settings_tax_rate')?.toString() ?? '10';
      _defaultUnitPrice.text =
          prefs.getInt('settings_default_unit_price')?.toString() ?? '25000';
      _detailMode = prefs.getString('settings_invoice_detail_mode') ??
          'siteBreakdownOnInvoice';
    } catch (_) {
      // Defaults are already populated.
    }
    if (!mounted) return;
    setState(() => _loading = false);
  }

  Future<void> _save() async {
    final taxRate = double.tryParse(_taxRate.text.trim());
    final unitPrice = int.tryParse(_defaultUnitPrice.text.trim());
    if (_companyName.text.trim().isEmpty || taxRate == null || unitPrice == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('入力内容を確認してください')),
      );
      return;
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('settings_company_name', _companyName.text.trim());
      await prefs.setDouble('settings_tax_rate', taxRate);
      await prefs.setInt('settings_default_unit_price', unitPrice);
      await prefs.setString('settings_invoice_detail_mode', _detailMode);
    } catch (_) {
      // Prototype persistence is best-effort until cloud settings are connected.
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('設定を保存しました')),
    );
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
      appBar: AppBar(title: const Text('設定')),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text(
                    '会社情報',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _companyName,
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
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: '消費税率（%）'),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _defaultUnitPrice,
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
                    onChanged: (value) => setState(() {
                      _detailMode = value ?? _detailMode;
                    }),
                  ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: _save,
                    icon: const Icon(Icons.save_outlined),
                    label: const Text('設定を保存'),
                  ),
                ],
              ),
      ),
    );
  }
}
