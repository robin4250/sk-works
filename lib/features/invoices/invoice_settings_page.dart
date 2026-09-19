import 'package:flutter/material.dart';

import '../notifications/notification_bell.dart';
import 'invoice_settings_repository.dart';

class InvoiceSettingsPage extends StatefulWidget {
  const InvoiceSettingsPage({super.key});

  @override
  State<InvoiceSettingsPage> createState() => _InvoiceSettingsPageState();
}

class _InvoiceSettingsPageState extends State<InvoiceSettingsPage> {
  final _repository = InvoiceSettingsRepository.maybeCreate();

  final _templateTitle = TextEditingController();
  final _taxRate = TextEditingController();
  final _welfareRate = TextEditingController();
  final _footerNote = TextEditingController();
  final _bankName = TextEditingController();
  final _bankBranch = TextEditingController();
  final _accountNumber = TextEditingController();
  final _accountHolder = TextEditingController();

  String _accountType = '普通';
  String _companyName = '';
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final controller in [
      _templateTitle,
      _taxRate,
      _welfareRate,
      _footerNote,
      _bankName,
      _bankBranch,
      _accountNumber,
      _accountHolder,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final repository = _repository;
    if (repository == null) {
      setState(() {
        _loading = false;
        _error = '請求書設定を利用できません。';
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final value = await repository.load();
      if (!mounted) return;
      _companyName = value.companyName;
      _templateTitle.text = value.templateTitle;
      _taxRate.text = value.taxRate.toString();
      _welfareRate.text = value.welfareRate.toString();
      _footerNote.text = value.footerNote;
      _bankName.text = value.bankName;
      _bankBranch.text = value.bankBranch;
      _accountNumber.text = value.bankAccountNumber;
      _accountHolder.text = value.bankAccountHolder;
      _accountType = value.bankAccountType.isEmpty
          ? '普通'
          : value.bankAccountType;
      setState(() => _loading = false);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _save() async {
    final repository = _repository;
    if (repository == null) return;

    final taxRate = double.tryParse(_taxRate.text);
    final welfareRate = double.tryParse(_welfareRate.text);
    if (taxRate == null ||
        taxRate < 0 ||
        taxRate > 100 ||
        welfareRate == null ||
        welfareRate < 0 ||
        welfareRate > 100) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('税率・法定福利費率を確認してください')),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      await repository.save(
        InvoiceSettingsData(
          companyName: _companyName,
          taxRate: taxRate,
          welfareRate: welfareRate,
          templateTitle: _templateTitle.text,
          footerNote: _footerNote.text,
          bankName: _bankName.text,
          bankBranch: _bankBranch.text,
          bankAccountType: _accountType,
          bankAccountNumber: _accountNumber.text,
          bankAccountHolder: _accountHolder.text,
        ),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('請求書設定を保存しました')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('保存できませんでした: $error')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          '請求書設定',
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
                : ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      Card(
                        child: ListTile(
                          leading: const Icon(Icons.business_outlined),
                          title: const Text('請求元'),
                          subtitle: Text(_companyName),
                        ),
                      ),
                      const SizedBox(height: 14),
                      _Section(
                        title: 'テンプレート',
                        children: [
                          TextField(
                            controller: _templateTitle,
                            decoration: const InputDecoration(
                              labelText: '表題',
                              hintText: '請求書',
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _footerNote,
                            maxLines: 3,
                            decoration: const InputDecoration(
                              labelText: '備考・フッター',
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      _Section(
                        title: '計算設定',
                        children: [
                          TextField(
                            controller: _taxRate,
                            keyboardType:
                                const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: const InputDecoration(
                              labelText: '消費税率（%）',
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _welfareRate,
                            keyboardType:
                                const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: const InputDecoration(
                              labelText: '標準 法定福利費率（%）',
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      _Section(
                        title: '振込先',
                        children: [
                          TextField(
                            controller: _bankName,
                            decoration: const InputDecoration(
                              labelText: '銀行・郵便局名',
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _bankBranch,
                            decoration: const InputDecoration(
                              labelText: '支店名',
                            ),
                          ),
                          const SizedBox(height: 12),
                          DropdownButtonFormField<String>(
                            initialValue: _accountType,
                            decoration: const InputDecoration(
                              labelText: '預金種別',
                            ),
                            items: const [
                              DropdownMenuItem(
                                value: '普通',
                                child: Text('普通'),
                              ),
                              DropdownMenuItem(
                                value: '当座',
                                child: Text('当座'),
                              ),
                              DropdownMenuItem(
                                value: '貯蓄',
                                child: Text('貯蓄'),
                              ),
                              DropdownMenuItem(
                                value: 'その他',
                                child: Text('その他'),
                              ),
                            ],
                            onChanged: (value) => setState(
                              () => _accountType = value ?? '普通',
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _accountNumber,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: '口座番号',
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _accountHolder,
                            decoration: const InputDecoration(
                              labelText: '口座名義（カナ）',
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      FilledButton.icon(
                        onPressed: _saving ? null : _save,
                        icon: const Icon(Icons.save_outlined),
                        label: Text(_saving ? '保存中...' : '設定を保存'),
                      ),
                    ],
                  ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.children,
  });

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }
}
