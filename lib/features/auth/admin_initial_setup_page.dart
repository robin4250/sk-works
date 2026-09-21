import 'package:flutter/material.dart';

import '../people/worker_document_repository.dart';
import 'admin_initial_setup_repository.dart';

class AdminInitialSetupWizardPage extends StatefulWidget {
  const AdminInitialSetupWizardPage({
    super.key,
    required this.onCompleted,
    required this.onSignOut,
  });

  final VoidCallback onCompleted;
  final Future<void> Function() onSignOut;

  @override
  State<AdminInitialSetupWizardPage> createState() =>
      _AdminInitialSetupWizardPageState();
}

class _AdminInitialSetupWizardPageState
    extends State<AdminInitialSetupWizardPage> {
  final _repository = AdminInitialSetupRepository.maybeCreate();
  final _documentRepository = WorkerDocumentRepository.maybeCreate();

  final _siteName = TextEditingController();
  final _customerName = TextEditingController();
  final _siteAddress = TextEditingController();
  final _nearestStation = TextEditingController();
  final _siteUnitPrice = TextEditingController();

  final _taxRate = TextEditingController(text: '10');
  final _welfareRate = TextEditingController(text: '0');
  final _overtime = TextEditingController(text: '0');
  final _early = TextEditingController(text: '0');
  final _night = TextEditingController(text: '0');
  final _holiday = TextEditingController(text: '0');
  final _allowance1 = TextEditingController();
  final _allowance1Amount = TextEditingController(text: '0');
  final _allowance2 = TextEditingController();
  final _allowance2Amount = TextEditingController(text: '0');
  final _allowance3 = TextEditingController();
  final _allowance3Amount = TextEditingController(text: '0');

  bool _loading = true;
  bool _busy = false;
  String? _error;
  AdminInitialSetupState? _state;
  List<Map<String, dynamic>> _requirements = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final controller in [
      _siteName,
      _customerName,
      _siteAddress,
      _nearestStation,
      _siteUnitPrice,
      _taxRate,
      _welfareRate,
      _overtime,
      _early,
      _night,
      _holiday,
      _allowance1,
      _allowance1Amount,
      _allowance2,
      _allowance2Amount,
      _allowance3,
      _allowance3Amount,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final repository = _repository;
    if (repository == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final state = await repository.loadState();
      List<Map<String, dynamic>> requirements = const [];
      if (!state.documentRequirementsReviewed &&
          _documentRepository != null) {
        final all = await _documentRepository!.loadAll();
        requirements = all['requirements'] ?? const [];
      }
      if (!mounted) return;
      setState(() {
        _state = state;
        _requirements = requirements;
        _loading = false;
      });
      if (state.completed) widget.onCompleted();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  int get _step {
    final state = _state;
    if (state == null) return 0;
    if (!state.documentRequirementsReviewed) return 0;
    if (!state.firstSiteCompleted) return 1;
    if (!state.rateSettingsCompleted) return 2;
    return 3;
  }

  Future<void> _addDefaults() async {
    final repo = _documentRepository;
    if (repo == null) return;
    setState(() => _busy = true);
    try {
      await repo.addDefaultRequirements();
      await _load();
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = '必要書類を追加できませんでした: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addCustomRequirement() async {
    final repo = _documentRepository;
    if (repo == null) return;
    final name = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('会社独自の必要書類を追加'),
        content: TextField(
          controller: name,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: '書類名',
            hintText: '例：作業員登録申請書',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, name.text.trim()),
            child: const Text('追加'),
          ),
        ],
      ),
    );
    name.dispose();
    if (result == null || result.isEmpty) return;

    setState(() => _busy = true);
    try {
      await repo.addRequirement(
        name: result,
        scope: 'internal',
        isRequired: true,
        expiryRequired: false,
      );
      await _load();
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = '必要書類を追加できませんでした: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _finishDocuments() async {
    final repository = _repository;
    if (repository == null) return;
    setState(() => _busy = true);
    try {
      await repository.markDocumentRequirementsReviewed();
      await _load();
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = '必要書類設定を完了できませんでした: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveSite() async {
    final repository = _repository;
    if (repository == null) return;

    final unitPrice = int.tryParse(_siteUnitPrice.text.trim());
    if (_siteName.text.trim().isEmpty ||
        _customerName.text.trim().isEmpty ||
        _siteAddress.text.trim().isEmpty ||
        _nearestStation.text.trim().isEmpty ||
        unitPrice == null ||
        unitPrice < 0) {
      setState(() => _error = '現場名・請求先会社・住所・最寄駅・現場単価を確認してください。');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await repository.saveInitialSite(
        siteName: _siteName.text,
        customerName: _customerName.text,
        address: _siteAddress.text,
        nearestStation: _nearestStation.text,
        billingUnitPriceYen: unitPrice,
      );
      await _load();
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = '現場を登録できませんでした: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  int? _yen(TextEditingController controller) =>
      int.tryParse(controller.text.trim());

  Future<void> _saveRates() async {
    final repository = _repository;
    if (repository == null) return;

    final tax = double.tryParse(_taxRate.text.trim());
    final welfare = double.tryParse(_welfareRate.text.trim());
    final values = [
      _yen(_overtime),
      _yen(_early),
      _yen(_night),
      _yen(_holiday),
      _yen(_allowance1Amount),
      _yen(_allowance2Amount),
      _yen(_allowance3Amount),
    ];
    if (tax == null ||
        welfare == null ||
        values.any((value) => value == null || value! < 0)) {
      setState(() => _error = '税率・福利厚生費率・各単価を数字で入力してください。');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await repository.saveInitialRates(
        taxRate: tax,
        welfareRate: welfare,
        overtimeHourRateYen: values[0]!,
        earlyHourRateYen: values[1]!,
        nightHourRateYen: values[2]!,
        holidayDayRateYen: values[3]!,
        allowance1Name: _allowance1.text,
        allowance1AmountYen: values[4]!,
        allowance2Name: _allowance2.text,
        allowance2AmountYen: values[5]!,
        allowance3Name: _allowance3.text,
        allowance3AmountYen: values[6]!,
      );
      await _load();
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = '会社単価設定を保存できませんでした: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _header(String title, String body) {
    return Card(
      color: Theme.of(context).colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
            ),
            const SizedBox(height: 8),
            Text(body),
          ],
        ),
      ),
    );
  }

  Widget _documentsStep() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _header(
          '2 / 4　会社・従業員に必要な書類',
          '会社で必要とする申請書類・従業員登録書類をここで決めます。'
          '実際の書類写真やPDFは後から登録できます。'
          '必須にした書類は、本人が全て登録するまでホームに「大事なお知らせ」として表示されます。',
        ),
        const SizedBox(height: 12),
        if (_requirements.isEmpty)
          OutlinedButton.icon(
            onPressed: _busy ? null : _addDefaults,
            icon: const Icon(Icons.playlist_add),
            label: const Text('標準の必要書類を追加'),
          ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _busy ? null : _addCustomRequirement,
          icon: const Icon(Icons.add),
          label: const Text('会社独自の必要書類を追加'),
        ),
        const SizedBox(height: 12),
        if (_requirements.isNotEmpty)
          for (final requirement in _requirements)
            Card(
              child: ListTile(
                leading: const Icon(Icons.description_outlined),
                title: Text(requirement['name']?.toString() ?? '必要書類'),
                subtitle: Text(
                  requirement['is_required'] == true ? '必須' : '任意',
                ),
              ),
            ),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: _busy ? null : _finishDocuments,
          icon: const Icon(Icons.arrow_forward),
          label: const Text('この必要書類設定で次へ'),
        ),
      ],
    );
  }

  Widget _siteStep() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _header(
          '3 / 4　最初の現場を登録',
          '管理者は現場単価も登録します。請求先会社名・現場住所・最寄駅まで入力すると、'
          '出勤・日報・請求へつながる最初の現場ができます。',
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _siteName,
          decoration: const InputDecoration(labelText: '現場名 *'),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _customerName,
          decoration: const InputDecoration(labelText: '請求先会社名 *'),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _siteAddress,
          decoration: const InputDecoration(labelText: '現場住所 *'),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _nearestStation,
          decoration: const InputDecoration(labelText: '最寄り駅 *'),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _siteUnitPrice,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: '現場単価（円） *'),
        ),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: _busy ? null : _saveSite,
          icon: const Icon(Icons.arrow_forward),
          label: const Text('現場を登録して次へ'),
        ),
      ],
    );
  }

  Widget _moneyField(
    TextEditingController controller,
    String label, {
    bool decimal = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: controller,
        keyboardType: TextInputType.numberWithOptions(decimal: decimal),
        decoration: InputDecoration(labelText: label),
      ),
    );
  }

  Widget _ratesStep() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _header(
          '4 / 4　請求・勤務単価を設定',
          'ここまで登録するとSKOを通常利用できます。税率・福利厚生費率と、'
          '残業・早出・夜勤・休日出勤の単価、任意手当を3種類まで設定します。',
        ),
        const SizedBox(height: 12),
        _moneyField(_taxRate, '消費税率（%）', decimal: true),
        _moneyField(_welfareRate, '福利厚生費率（%）', decimal: true),
        _moneyField(_overtime, '残業単価（1時間・円）'),
        _moneyField(_early, '早出単価（1時間・円）'),
        _moneyField(_night, '夜勤単価（1時間・円）'),
        _moneyField(_holiday, '休日出勤単価（1日・円）'),
        const SizedBox(height: 8),
        const Text(
          '任意手当（最大3つ）',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _allowance1,
          decoration: const InputDecoration(labelText: '手当1 名称'),
        ),
        _moneyField(_allowance1Amount, '手当1 金額（円）'),
        TextField(
          controller: _allowance2,
          decoration: const InputDecoration(labelText: '手当2 名称'),
        ),
        _moneyField(_allowance2Amount, '手当2 金額（円）'),
        TextField(
          controller: _allowance3,
          decoration: const InputDecoration(labelText: '手当3 名称'),
        ),
        _moneyField(_allowance3Amount, '手当3 金額（円）'),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: _busy ? null : _saveRates,
          icon: const Icon(Icons.check_circle_outline),
          label: const Text('設定を保存してSKOを開始'),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'SKO 初期設定',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        actions: [
          TextButton(
            onPressed: _busy ? null : widget.onSignOut,
            child: const Text('ログアウト'),
          ),
        ],
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
                          const SizedBox(height: 12),
                          FilledButton(
                            onPressed: _load,
                            child: const Text('再試行'),
                          ),
                        ],
                      ),
                    ),
                  )
                : switch (_step) {
                    0 => _documentsStep(),
                    1 => _siteStep(),
                    2 => _ratesStep(),
                    _ => const Center(child: CircularProgressIndicator()),
                  },
      ),
    );
  }
}
