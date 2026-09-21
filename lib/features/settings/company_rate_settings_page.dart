import 'package:flutter/material.dart';

import '../notifications/notification_bell.dart';
import 'company_rate_settings_repository.dart';

class CompanyRateSettingsPage extends StatefulWidget {
  const CompanyRateSettingsPage({super.key});

  @override
  State<CompanyRateSettingsPage> createState() =>
      _CompanyRateSettingsPageState();
}

class _CompanyRateSettingsPageState extends State<CompanyRateSettingsPage> {
  final _repository = CompanyRateSettingsRepository.maybeCreate();

  final _tax = TextEditingController();
  final _welfare = TextEditingController();
  final _overtime = TextEditingController();
  final _early = TextEditingController();
  final _night = TextEditingController();
  final _holiday = TextEditingController();
  final _allowance1 = TextEditingController();
  final _allowance1Amount = TextEditingController();
  final _allowance2 = TextEditingController();
  final _allowance2Amount = TextEditingController();
  final _allowance3 = TextEditingController();
  final _allowance3Amount = TextEditingController();

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
      _tax,
      _welfare,
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
    if (repository == null) {
      setState(() {
        _loading = false;
        _error = '会社単価設定を利用できません。';
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final value = await repository.load();
      _tax.text = value.taxRate.toString();
      _welfare.text = value.welfareRate.toString();
      _overtime.text = value.overtimeHourRateYen.toString();
      _early.text = value.earlyHourRateYen.toString();
      _night.text = value.nightHourRateYen.toString();
      _holiday.text = value.holidayDayRateYen.toString();
      _allowance1.text = value.allowance1Name;
      _allowance1Amount.text = value.allowance1AmountYen.toString();
      _allowance2.text = value.allowance2Name;
      _allowance2Amount.text = value.allowance2AmountYen.toString();
      _allowance3.text = value.allowance3Name;
      _allowance3Amount.text = value.allowance3AmountYen.toString();
      if (!mounted) return;
      setState(() => _loading = false);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  int? _yen(TextEditingController controller) =>
      int.tryParse(controller.text.trim());

  Future<void> _save() async {
    final repository = _repository;
    if (repository == null) return;

    final tax = double.tryParse(_tax.text.trim());
    final welfare = double.tryParse(_welfare.text.trim());
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
        tax < 0 ||
        tax > 100 ||
        welfare < 0 ||
        welfare > 100 ||
        values.any((value) => value == null || value < 0)) {
      setState(() => _error = '税率・福利厚生費率・各単価を0以上の数字で入力してください。');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      await repository.save(
        CompanyRateSettings(
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
        ),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('会社単価・手当設定を保存しました')),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = '保存できませんでした: $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _moneyField(
    TextEditingController controller,
    String label, {
    bool decimal = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        keyboardType: TextInputType.numberWithOptions(decimal: decimal),
        decoration: InputDecoration(labelText: label),
      ),
    );
  }

  Widget _allowanceBlock(
    int number,
    TextEditingController name,
    TextEditingController amount,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            TextField(
              controller: name,
              decoration: InputDecoration(labelText: '手当$number 名称'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: amount,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(labelText: '手当$number 金額（円）'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          '会社単価・手当設定',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        actions: const [SkoNotificationBell()],
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null && _tax.text.isEmpty
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
                            child: const Text('再読み込み'),
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      const Card(
                        child: Padding(
                          padding: EdgeInsets.all(16),
                          child: Text(
                            '初期設定で登録した請求・勤務単価を後から変更できます。'
                            'この画面は管理者だけが利用できます。',
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        '税率・福利厚生費率',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w900,
                            ),
                      ),
                      const SizedBox(height: 10),
                      _moneyField(_tax, '消費税率（%）', decimal: true),
                      _moneyField(_welfare, '福利厚生費率（%）', decimal: true),
                      const SizedBox(height: 12),
                      Text(
                        '勤務単価',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w900,
                            ),
                      ),
                      const SizedBox(height: 10),
                      _moneyField(_overtime, '残業単価（1時間・円）'),
                      _moneyField(_early, '早出単価（1時間・円）'),
                      _moneyField(_night, '夜勤単価（1時間・円）'),
                      _moneyField(_holiday, '休日出勤単価（1日・円）'),
                      const SizedBox(height: 12),
                      Text(
                        '任意手当（最大3つ）',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w900,
                            ),
                      ),
                      const SizedBox(height: 10),
                      _allowanceBlock(1, _allowance1, _allowance1Amount),
                      const SizedBox(height: 10),
                      _allowanceBlock(2, _allowance2, _allowance2Amount),
                      const SizedBox(height: 10),
                      _allowanceBlock(3, _allowance3, _allowance3Amount),
                      if (_error != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          _error!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ],
                      const SizedBox(height: 20),
                      FilledButton.icon(
                        onPressed: _saving ? null : _save,
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
