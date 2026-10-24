import '../../international/language_controller.dart';
import 'package:flutter/material.dart';

import '../notifications/notification_bell.dart';
import 'company_rate_settings_repository.dart';

class CompanyRateSettingsPage extends StatefulWidget {
  const CompanyRateSettingsPage({super.key, this.companyId});

  final String? companyId;

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

  bool _loading = true;
  bool _saving = false;
  String? _error;
  int _loadGeneration = 0;
  CompanyRateSettings? _loaded;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _loadGeneration++;
    for (final controller in [
      _tax,
      _welfare,
      _overtime,
      _early,
      _night,
      _holiday,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    if (!mounted) return;
    final generation = ++_loadGeneration;
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
      final company = widget.companyId;
      if (company == null || company.isEmpty) {
        throw StateError('会社情報を確認できません。会社設定から開き直してください。');
      }
      final value = await repository.loadDefaults(company);
      if (!mounted || generation != _loadGeneration) return;
      _tax.text = value.taxRate.toString();
      _welfare.text = value.welfareRate.toString();
      _overtime.text = value.overtimeHourRateYen.toString();
      _early.text = value.earlyHourRateYen.toString();
      _night.text = value.nightHourRateYen.toString();
      _holiday.text = value.holidayDayRateYen.toString();
      _loaded = value;
      setState(() => _loading = false);
    } catch (error) {
      if (!mounted || generation != _loadGeneration) return;
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
      final loaded = _loaded;
      if (loaded == null) { throw StateError('設定を読み直してください。'); }
      _loaded = await repository.saveDefaults(
        expected: loaded,
        taxRate: tax,
        welfareRate: welfare,
        overtimeHourRateYen: values[0]!,
        earlyHourRateYen: values[1]!,
        nightHourRateYen: values[2]!,
        holidayDayRateYen: values[3]!,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(SkoLanguageController.tr('消費税・福利厚生費・旧単価を保存しました'))),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = SkoLanguageController.trParams('保存できませんでした: {error}', {'error': error}));
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
        decoration: InputDecoration(labelText: SkoLanguageController.tr(label)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    SkoLanguageController.watch(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          SkoLanguageController.tr('消費税・福利厚生費・旧単価'),
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        actions: [
          IconButton(tooltip: '使い方', icon: const Icon(Icons.help_outline),
            onPressed: () => showDialog<void>(context: context, builder: (context) => AlertDialog(
              title: const Text('消費税・福利厚生費・旧単価の使い方'),
              content: const Text('消費税率・福利厚生費率と登録済みの旧単価を設定します。共通手当は給料一覧の「社内共通手当」にまとめています。この保存では手当の名称・金額・単位を変更しません。'),
              actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('閉じる'))],
            ))),
          const SkoNotificationBell(),
        ],
      ),
      body: SafeArea(
        child: _loading
            ? Center(child: CircularProgressIndicator())
            : _error != null && _tax.text.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(SkoLanguageController.tr(_error!), textAlign: TextAlign.center),
                          SizedBox(height: 12),
                          FilledButton(
                            onPressed: _load,
                            child: Text(SkoLanguageController.tr('再読み込み')),
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      Card(
                        child: Padding(
                          padding: EdgeInsets.all(16),
                          child: Text(
                            SkoLanguageController.tr('消費税率・福利厚生費率と登録済みの旧単価を設定します。共通手当は給料一覧の「社内共通手当」から設定します。'),
                          ),
                        ),
                      ),
                      SizedBox(height: 16),
                      Text(
                        SkoLanguageController.tr('税率・福利厚生費率'),
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w900,
                            ),
                      ),
                      SizedBox(height: 10),
                      _moneyField(_tax, SkoLanguageController.tr('消費税率（%）'), decimal: true),
                      _moneyField(_welfare, SkoLanguageController.tr('福利厚生費率（%）'), decimal: true),
                      SizedBox(height: 12),
                      ExpansionTile(
                        title: Text(SkoLanguageController.tr('旧単価（登録済み設定）')),
                        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                        children: [
                          Text(
                            SkoLanguageController.tr('以前に登録した単価です。変更する必要がある場合だけ開いて編集してください。社員ごとの給与は「個別給与設定」で設定します。'),
                          ),
                          SizedBox(height: 10),
                          _moneyField(_overtime, SkoLanguageController.tr('残業単価（1時間・円）')),
                          _moneyField(_early, SkoLanguageController.tr('早出単価（1時間・円）')),
                          _moneyField(_night, SkoLanguageController.tr('夜勤単価（1時間・円）')),
                          _moneyField(_holiday, SkoLanguageController.tr('休日出勤単価（1日・円）')),
                        ],
                      ),
                      SizedBox(height: 12),
                      if (_error != null) ...[
                        SizedBox(height: 12),
                        Text(
                          SkoLanguageController.tr(_error!),
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ],
                      SizedBox(height: 20),
                      FilledButton.icon(
                        onPressed: _saving ? null : _save,
                        icon: _saving
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : Icon(Icons.save_outlined),
                        label: Text(_saving ? SkoLanguageController.tr('保存中...') : SkoLanguageController.tr('設定を保存')),
                      ),
                    ],
                  ),
      ),
    );
  }
}

