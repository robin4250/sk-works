import '../../international/language_controller.dart';
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
  final _allowance1Unit = TextEditingController(text: '回');
  final _allowance2 = TextEditingController();
  final _allowance2Amount = TextEditingController();
  final _allowance2Unit = TextEditingController(text: '回');
  final _allowance3 = TextEditingController();
  final _allowance3Amount = TextEditingController();
  final _allowance3Unit = TextEditingController(text: '回');

  bool _loading = true;
  bool _saving = false;
  String? _error;
  int _loadGeneration = 0;

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
      _allowance1,
      _allowance1Amount,
      _allowance1Unit,
      _allowance2,
      _allowance2Amount,
      _allowance2Unit,
      _allowance3,
      _allowance3Amount,
      _allowance3Unit,
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
      final value = await repository.load();
      if (!mounted || generation != _loadGeneration) return;
      _tax.text = value.taxRate.toString();
      _welfare.text = value.welfareRate.toString();
      _overtime.text = value.overtimeHourRateYen.toString();
      _early.text = value.earlyHourRateYen.toString();
      _night.text = value.nightHourRateYen.toString();
      _holiday.text = value.holidayDayRateYen.toString();
      _allowance1.text = value.allowance1Name;
      _allowance1Amount.text = value.allowance1AmountYen.toString();
      _allowance1Unit.text = value.allowance1Unit;
      _allowance2.text = value.allowance2Name;
      _allowance2Amount.text = value.allowance2AmountYen.toString();
      _allowance2Unit.text = value.allowance2Unit;
      _allowance3.text = value.allowance3Name;
      _allowance3Amount.text = value.allowance3AmountYen.toString();
      _allowance3Unit.text = value.allowance3Unit;
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
          allowance1Unit: _allowance1Unit.text,
          allowance2Name: _allowance2.text,
          allowance2AmountYen: values[5]!,
          allowance2Unit: _allowance2Unit.text,
          allowance3Name: _allowance3.text,
          allowance3AmountYen: values[6]!,
          allowance3Unit: _allowance3Unit.text,
        ),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(SkoLanguageController.tr('会社単価・手当設定を保存しました'))),
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

  Widget _allowanceBlock(
    int number,
    TextEditingController name,
    TextEditingController amount,
    TextEditingController unit,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            TextField(
              controller: name,
              decoration: InputDecoration(labelText: SkoLanguageController.trParams('手当{number} 名称', {'number': number})),
            ),
            SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: amount,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(labelText: SkoLanguageController.trParams('手当{number} 金額（円）', {'number': number})),
                  ),
                ),
                SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: unit,
                    maxLength: 6,
                    decoration: InputDecoration(
                      labelText: SkoLanguageController.trParams('手当{number} 単位', {'number': number}),
                      hintText: SkoLanguageController.tr('回・日・時間・件など'),
                      helperText: SkoLanguageController.tr('週間表示・カレンダー表示・月集計に反映'),
                      counterText: '',
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    SkoLanguageController.watch(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          SkoLanguageController.tr('会社単価・手当設定'),
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        actions: const [SkoNotificationBell()],
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
                            SkoLanguageController.tr('会社共通の税率・福利厚生費率・手当をここで設定します。社員ごとの給与は「個別給与設定」、現場ごとの請求単価は「管理者用現場データ」で設定します。登録した値を各画面で使用するため、同じ内容の再入力は不要です。'),
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
                      Text(
                        SkoLanguageController.tr('任意手当（最大3つ）'),
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w900,
                            ),
                      ),
                      SizedBox(height: 10),
                      _allowanceBlock(
                        1,
                        _allowance1,
                        _allowance1Amount,
                        _allowance1Unit,
                      ),
                      SizedBox(height: 10),
                      _allowanceBlock(
                        2,
                        _allowance2,
                        _allowance2Amount,
                        _allowance2Unit,
                      ),
                      SizedBox(height: 10),
                      _allowanceBlock(
                        3,
                        _allowance3,
                        _allowance3Amount,
                        _allowance3Unit,
                      ),
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
