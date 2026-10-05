import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../notifications/notification_bell.dart';
import 'invoice_approval_repository.dart';
import 'invoice_settings_repository.dart';

class InvoiceSettingsPage extends StatefulWidget {
  const InvoiceSettingsPage({super.key});

  @override
  State<InvoiceSettingsPage> createState() => _InvoiceSettingsPageState();
}

class _InvoiceSettingsPageState extends State<InvoiceSettingsPage> {
  final _repository = InvoiceSettingsRepository.maybeCreate();
  final _approvalRepository = InvoiceApprovalRepository.maybeCreate();

  final _templateTitle = TextEditingController();
  final _taxRate = TextEditingController();
  final _welfareRate = TextEditingController();
  final _footerNote = TextEditingController();
  final _invoiceSubject = TextEditingController();
  final _invoiceContactName = TextEditingController();
  final _paymentDueText = TextEditingController();
  final _bankName = TextEditingController();
  final _bankBranch = TextEditingController();
  final _accountNumber = TextEditingController();
  final _accountHolder = TextEditingController();

  String _accountType = '普通';
  String _companyName = '';
  String _companyPostalCode = '';
  String _companyAddress = '';
  String _companyPhone = '';
  String _companyFax = '';
  String _companyLogoBase64 = '';
  String _companySealBase64 = '';
  bool _loading = true;
  bool _saving = false;
  String? _error;
  List<InvoiceApproverCandidate> _approverCandidates = const [];
  final List<String> _selectedApproverIds = [];

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
      _invoiceSubject,
      _invoiceContactName,
      _paymentDueText,
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
      final candidates = await _approvalRepository?.loadCandidates() ??
          const <InvoiceApproverCandidate>[];
      if (!mounted) return;
      _companyName = value.companyName;
      _companyPostalCode = value.companyPostalCode;
      _companyAddress = value.companyAddress;
      _companyPhone = value.companyPhone;
      _companyFax = value.companyFax;
      _companyLogoBase64 = value.companyLogoBase64;
      _companySealBase64 = value.companySealBase64;
      _templateTitle.text = value.templateTitle;
      _invoiceSubject.text = value.invoiceSubject;
      _invoiceContactName.text = value.invoiceContactName;
      _paymentDueText.text = value.paymentDueText;
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
      _approverCandidates = candidates;
      final selected = candidates
          .where((item) => item.selectedPosition != null)
          .toList()
        ..sort(
          (a, b) => a.selectedPosition!.compareTo(b.selectedPosition!),
        );
      _selectedApproverIds
        ..clear()
        ..addAll(selected.map((item) => item.userId));
      setState(() => _loading = false);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  Uint8List? get _companyLogoBytes {
    if (_companyLogoBase64.trim().isEmpty) return null;
    try {
      return base64Decode(_companyLogoBase64);
    } catch (_) {
      return null;
    }
  }

  Future<void> _pickCompanyLogo() async {
    final file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1200,
      imageQuality: 92,
    );
    if (file == null) return;
    final bytes = await file.readAsBytes();
    if (bytes.lengthInBytes > 2 * 1024 * 1024) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ロゴ画像は2MB以下にしてください')),
      );
      return;
    }
    if (!mounted) return;
    setState(() => _companyLogoBase64 = base64Encode(bytes));
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

    if (_selectedApproverIds.isEmpty || _selectedApproverIds.length > 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('確認者は1～2名で設定してください')),
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
          companyPostalCode: _companyPostalCode,
          companyAddress: _companyAddress,
          companyPhone: _companyPhone,
          companyFax: _companyFax,
          invoiceSubject: _invoiceSubject.text,
          invoiceContactName: _invoiceContactName.text,
          paymentDueText: _paymentDueText.text,
          companyLogoBase64: _companyLogoBase64,
          companySealBase64: _companySealBase64,
        ),
      );
      await _approvalRepository?.saveApprovers(_selectedApproverIds);
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
                          title: const Text('請求元（会社データから自動反映）'),
                          subtitle: Text(
                            [
                              _companyName,
                              if (_companyPostalCode.isNotEmpty)
                                '〒$_companyPostalCode',
                              if (_companyAddress.isNotEmpty) _companyAddress,
                              if (_companyPhone.isNotEmpty)
                                'TEL $_companyPhone',
                              if (_companyFax.isNotEmpty)
                                'FAX $_companyFax',
                            ].join('\n'),
                          ),
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
                            controller: _invoiceSubject,
                            decoration: const InputDecoration(
                              labelText: '件名',
                              hintText: '例：とび工　安全設備・足場組立解体作業',
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _paymentDueText,
                            decoration: const InputDecoration(
                              labelText: '支払約定日',
                              hintText: '例：翌月10日 / 令和8年11月10日',
                            ),
                          ),
                          const SizedBox(height: 12),
                          Card(
                            margin: EdgeInsets.zero,
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  const Text(
                                    '会社ロゴ',
                                    style: TextStyle(fontWeight: FontWeight.w800),
                                  ),
                                  const SizedBox(height: 8),
                                  if (_companyLogoBytes != null)
                                    Container(
                                      height: 72,
                                      alignment: Alignment.centerLeft,
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        border: Border.all(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .outlineVariant,
                                        ),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Image.memory(
                                        _companyLogoBytes!,
                                        fit: BoxFit.contain,
                                      ),
                                    )
                                  else
                                    const Text('ロゴ未登録'),
                                  const SizedBox(height: 8),
                                  Wrap(
                                    spacing: 8,
                                    children: [
                                      OutlinedButton.icon(
                                        onPressed: _pickCompanyLogo,
                                        icon: const Icon(Icons.image_outlined),
                                        label: const Text('ロゴ画像を登録'),
                                      ),
                                      if (_companyLogoBytes != null)
                                        TextButton.icon(
                                          onPressed: () => setState(
                                            () => _companyLogoBase64 = '',
                                          ),
                                          icon: const Icon(Icons.delete_outline),
                                          label: const Text('登録解除'),
                                        ),
                                    ],
                                  ),
                                  const Text(
                                    '請求書では会社名の左隣に表示します。プレビュー・PDF・印刷・共有で同じ画像を使用します。',
                                    style: TextStyle(fontSize: 12),
                                  ),
                                ],
                              ),
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
                        title: '請求書の承認者',
                        children: [
                          const Text(
                            '登録済みユーザーから1～2名を選択します。請求書には確認者欄を2枠表示し、選択順が左からの順番になります。',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 8),
                          if (_approverCandidates.isEmpty)
                            const Text('選択できるユーザーがいません')
                          else
                            ..._approverCandidates.map((candidate) {
                              final index =
                                  _selectedApproverIds.indexOf(candidate.userId);
                              final selected = index >= 0;
                              return CheckboxListTile(
                                contentPadding: EdgeInsets.zero,
                                value: selected,
                                title: Text(candidate.displayName),
                                subtitle: Text(
                                  selected
                                      ? '確認者 ${index + 1} ・ ${candidate.role}'
                                      : candidate.role,
                                ),
                                secondary: selected
                                    ? CircleAvatar(
                                        child: Text('${index + 1}'),
                                      )
                                    : const Icon(Icons.person_outline),
                                onChanged: (checked) {
                                  setState(() {
                                    if (checked == true) {
                                      if (_selectedApproverIds.length >= 2) {
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                          const SnackBar(
                                            content: Text(
                                              '確認者は最大2名です',
                                            ),
                                          ),
                                        );
                                        return;
                                      }
                                      if (!selected) {
                                        _selectedApproverIds
                                            .add(candidate.userId);
                                      }
                                    } else {
                                      _selectedApproverIds
                                          .remove(candidate.userId);
                                    }
                                  });
                                },
                              );
                            }),
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
