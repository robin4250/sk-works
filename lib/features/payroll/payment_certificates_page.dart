import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';

import '../notifications/notification_bell.dart';
import '../../international/language_controller.dart';
import '../../domain/rate_formula_settings.dart';
import 'payment_certificate_pdf_service.dart';
import 'payment_certificate_repository.dart';

class PaymentCertificatesPage extends StatefulWidget {
  const PaymentCertificatesPage({super.key});

  @override
  State<PaymentCertificatesPage> createState() =>
      _PaymentCertificatesPageState();
}

class _PaymentCertificatesPageState extends State<PaymentCertificatesPage> {
  final _repository = PaymentCertificateRepository.maybeCreate();
  List<PaymentCertificateRecord> _items = const [];
  bool _loading = true;
  String? _error;

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
        _error = SkoLanguageController.isEnglish ? 'Payment certificates are unavailable.' : '支払証明書を利用できません。';
      });
      return;
    }

    try {
      final items = await repository.loadCertificates();
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          SkoLanguageController.isEnglish ? 'Payment Certificates' : '支払証明書',
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        actions: [
          IconButton(
            tooltip: SkoLanguageController.isEnglish
                ? 'Payment Certificate Settings'
                : '支払証明書設定',
            onPressed: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const PartnerPaymentSettingsPage(),
                ),
              );
              if (mounted) await _load();
            },
            icon: const Icon(Icons.tune_outlined),
          ),
          const SkoNotificationBell(),
        ],
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(_error!, textAlign: TextAlign.center),
                    ),
                  )
                : _items.isEmpty
                    ? Center(
                        child: Text(
                          SkoLanguageController.isEnglish ? 'A draft is created automatically when subcontractor attendance is recorded.' : '下請け作業員の出勤が入ると自動で下書きを作成します',
                          textAlign: TextAlign.center,
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: ListView.separated(
                          padding: const EdgeInsets.all(12),
                          itemCount: _items.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final item = _items[index];
                            return Card(
                              child: ListTile(
                                onTap: () => Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => PaymentCertificatePreviewPage(
                                      record: item,
                                    ),
                                  ),
                                ),
                                title: Text(
                                  item.partnerCompanyName,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                subtitle: Text(
                                  '${item.monthLabel} ・ '
                                  '${item.status == 'draft' ? (SkoLanguageController.isEnglish ? 'Draft' : '下書き') : (SkoLanguageController.isEnglish ? 'Finalized' : '確定')} ・ '
                                  'revision ${item.revision}',
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      _yen(item.netAmount),
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                    IconButton(
                                      tooltip: SkoLanguageController.isEnglish ? 'Print' : '印刷',
                                      onPressed: () =>
                                          PaymentCertificatePdfService
                                              .printCertificate(item),
                                      icon: const Icon(Icons.print_outlined),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
      ),
    );
  }

  String _yen(int value) {
    final digits = value.abs().toString();
    final groups = <String>[];
    for (var end = digits.length; end > 0; end -= 3) {
      final start = (end - 3).clamp(0, digits.length);
      groups.insert(0, digits.substring(start, end));
    }
    return '${value < 0 ? '-' : ''}¥${groups.join(',')}';
  }
}

class PaymentCertificatePreviewPage extends StatelessWidget {
  const PaymentCertificatePreviewPage({
    super.key,
    required this.record,
  });

  final PaymentCertificateRecord record;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          SkoLanguageController.isEnglish
              ? 'Payment Certificate'
              : '支払証明書',
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        actions: const [SkoNotificationBell()],
      ),
      body: PdfPreview(
        initialPageFormat: PdfPageFormat.a4,
        canChangePageFormat: false,
        canChangeOrientation: false,
        allowPrinting: true,
        allowSharing: true,
        pdfFileName:
            '${record.monthLabel}_${record.partnerCompanyName}_支払証明書.pdf',
        build: (_) => PaymentCertificatePdfService.buildPdf(record),
      ),
    );
  }
}

class PartnerPaymentSettingsPage extends StatefulWidget {
  const PartnerPaymentSettingsPage({super.key});

  @override
  State<PartnerPaymentSettingsPage> createState() =>
      _PartnerPaymentSettingsPageState();
}

class _PartnerPaymentSettingsPageState
    extends State<PartnerPaymentSettingsPage> {
  final _repository = PaymentCertificateRepository.maybeCreate();

  final _daily = TextEditingController();
  final _legacyNightHourly = TextEditingController();
  final _overtime = TextEditingController();
  final _early = TextEditingController();
  final _nightDay = TextEditingController();
  final _nightOvertime = TextEditingController();
  final _holidayDay = TextEditingController();
  final _holidayOvertime = TextEditingController();
  final _holidayNightDay = TextEditingController();
  final _holidayNightOvertime = TextEditingController();
  final _welfare = TextEditingController();
  final _tax = TextEditingController();

  final _hoursPerDay = TextEditingController();
  final _overtimeMultiplier = TextEditingController();
  final _earlyMultiplier = TextEditingController();
  final _nightMultiplier = TextEditingController();
  final _nightOvertimeMultiplier = TextEditingController();
  final _holidayMultiplier = TextEditingController();
  final _holidayOvertimeMultiplier = TextEditingController();
  final _holidayNightMultiplier = TextEditingController();
  final _holidayNightOvertimeMultiplier = TextEditingController();

  final _allowances = <_PaymentAllowanceDraft>[];

  List<PartnerPaymentSetting> _items = const [];
  String? _partnerId;
  bool _hourlyBase = false;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  List<TextEditingController> get _allControllers => [
        _daily,
        _legacyNightHourly,
        _overtime,
        _early,
        _nightDay,
        _nightOvertime,
        _holidayDay,
        _holidayOvertime,
        _holidayNightDay,
        _holidayNightOvertime,
        _welfare,
        _tax,
        _hoursPerDay,
        _overtimeMultiplier,
        _earlyMultiplier,
        _nightMultiplier,
        _nightOvertimeMultiplier,
        _holidayMultiplier,
        _holidayOvertimeMultiplier,
        _holidayNightMultiplier,
        _holidayNightOvertimeMultiplier,
      ];

  @override
  void initState() {
    super.initState();
    for (final controller in _allControllers) {
      controller.addListener(_refreshFormulaPreview);
    }
    _load();
  }

  @override
  void dispose() {
    for (final controller in _allControllers) {
      controller
        ..removeListener(_refreshFormulaPreview)
        ..dispose();
    }
    for (final item in _allowances) {
      item.dispose();
    }
    super.dispose();
  }

  void _refreshFormulaPreview() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    final repository = _repository;
    if (repository == null) {
      setState(() {
        _loading = false;
        _error = SkoLanguageController.isEnglish
            ? 'Payment certificate settings are unavailable.'
            : '支払証明書設定を利用できません。';
      });
      return;
    }

    try {
      final items = await repository.loadSettings();
      if (!mounted) return;
      final previousId = _partnerId;
      setState(() {
        _items = items;
        _loading = false;
        _error = null;
        _partnerId = items.any((item) => item.partnerCompanyId == previousId)
            ? previousId
            : items.isEmpty
                ? null
                : items.first.partnerCompanyId;
      });
      _syncControllers();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  PartnerPaymentSetting? _selectedSetting() {
    final id = _partnerId;
    if (id == null) return null;
    for (final item in _items) {
      if (item.partnerCompanyId == id) return item;
    }
    return null;
  }

  void _syncControllers() {
    final item = _selectedSetting();
    if (item == null) return;
    _daily.text = item.dailyRateYen.toString();
    _legacyNightHourly.text = item.nightHourRateYen.toString();
    _overtime.text = item.overtimeHourRateYen.toString();
    _early.text = item.earlyHourRateYen.toString();
    _nightDay.text = item.nightDayRateYen.toString();
    _nightOvertime.text = item.nightOvertimeHourRateYen.toString();
    _holidayDay.text = item.holidayDayRateYen.toString();
    _holidayOvertime.text = item.holidayOvertimeHourRateYen.toString();
    _holidayNightDay.text = item.holidayNightDayRateYen.toString();
    _holidayNightOvertime.text =
        item.holidayNightOvertimeHourRateYen.toString();
    _welfare.text = _number(item.welfareRate);
    _tax.text = _number(item.taxRate);

    final formula = item.formulas;
    _hourlyBase = formula.hourlyBase;
    _hoursPerDay.text = _number(formula.hoursPerDay);
    _overtimeMultiplier.text = _number(formula.overtimeMultiplier);
    _earlyMultiplier.text = _number(formula.earlyMultiplier);
    _nightMultiplier.text = _number(formula.nightMultiplier);
    _nightOvertimeMultiplier.text =
        _number(formula.nightOvertimeMultiplier);
    _holidayMultiplier.text = _number(formula.holidayMultiplier);
    _holidayOvertimeMultiplier.text =
        _number(formula.holidayOvertimeMultiplier);
    _holidayNightMultiplier.text = _number(formula.holidayNightMultiplier);
    _holidayNightOvertimeMultiplier.text =
        _number(formula.holidayNightOvertimeMultiplier);

    for (final allowance in _allowances) {
      allowance.dispose();
    }
    _allowances
      ..clear()
      ..addAll(
        item.allowances.map(
          (value) => _PaymentAllowanceDraft(
            name: value.name,
            amountYen: value.amountYen,
          ),
        ),
      );
    setState(() {});
  }

  int _int(TextEditingController controller) =>
      int.tryParse(controller.text.trim()) ?? 0;

  double _double(TextEditingController controller, double fallback) =>
      double.tryParse(controller.text.trim()) ?? fallback;

  RateFormulaSettings get _formula => RateFormulaSettings(
        hourlyBase: _hourlyBase,
        hoursPerDay: _double(_hoursPerDay, 8),
        overtimeMultiplier: _double(_overtimeMultiplier, 1.25),
        earlyMultiplier: _double(_earlyMultiplier, 1.25),
        nightMultiplier: _double(_nightMultiplier, 1.5),
        nightOvertimeMultiplier:
            _double(_nightOvertimeMultiplier, 1.5),
        holidayMultiplier: _double(_holidayMultiplier, 1.35),
        holidayOvertimeMultiplier:
            _double(_holidayOvertimeMultiplier, 1.35),
        holidayNightMultiplier: _double(_holidayNightMultiplier, 1.6),
        holidayNightOvertimeMultiplier:
            _double(_holidayNightOvertimeMultiplier, 1.6),
      );

  PartnerPaymentSetting? _draftSetting({bool showError = true}) {
    final current = _selectedSetting();
    if (current == null) return null;

    final amountControllers = [
      _daily,
      _overtime,
      _early,
      _nightDay,
      _nightOvertime,
      _holidayDay,
      _holidayOvertime,
      _holidayNightDay,
      _holidayNightOvertime,
    ];
    if (amountControllers.any(
      (controller) =>
          int.tryParse(controller.text.trim()) == null ||
          _int(controller) < 0,
    )) {
      if (showError) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('金額は0以上の数字で入力してください')),
        );
      }
      return null;
    }

    final formula = _formula;
    if (formula.hoursPerDay <= 0 ||
        [
          formula.overtimeMultiplier,
          formula.earlyMultiplier,
          formula.nightMultiplier,
          formula.nightOvertimeMultiplier,
          formula.holidayMultiplier,
          formula.holidayOvertimeMultiplier,
          formula.holidayNightMultiplier,
          formula.holidayNightOvertimeMultiplier,
        ].any((value) => value < 0)) {
      if (showError) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('計算式の数値は0以上、1日の時間は0より大きい数で入力してください')),
        );
      }
      return null;
    }

    final welfare = double.tryParse(_welfare.text.trim());
    final tax = double.tryParse(_tax.text.trim());
    if (welfare == null ||
        tax == null ||
        welfare < 0 ||
        welfare > 100 ||
        tax < 0 ||
        tax > 100) {
      if (showError) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('福利厚生費率・消費税率は0～100で入力してください')),
        );
      }
      return null;
    }

    final allowances = <PaymentAllowanceSetting>[];
    for (var index = 0; index < _allowances.length; index++) {
      final item = _allowances[index];
      final name = item.name.text.trim();
      final amount = int.tryParse(item.amount.text.trim());
      if (name.isEmpty && (amount == null || amount == 0)) continue;
      if (name.isEmpty || amount == null || amount < 0) {
        if (showError) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('手当${index + 1}の名称と0以上の金額を入力してください')),
          );
        }
        return null;
      }
      allowances.add(PaymentAllowanceSetting(name: name, amountYen: amount));
    }

    return PartnerPaymentSetting(
      partnerCompanyId: current.partnerCompanyId,
      partnerCompanyName: current.partnerCompanyName,
      dailyRateYen: _int(_daily),
      overtimeHourRateYen: _int(_overtime),
      earlyHourRateYen: _int(_early),
      nightHourRateYen: _int(_legacyNightHourly),
      nightDayRateYen: _int(_nightDay),
      nightOvertimeHourRateYen: _int(_nightOvertime),
      holidayDayRateYen: _int(_holidayDay),
      holidayOvertimeHourRateYen: _int(_holidayOvertime),
      holidayNightDayRateYen: _int(_holidayNightDay),
      holidayNightOvertimeHourRateYen: _int(_holidayNightOvertime),
      formulas: formula,
      allowances: allowances,
      welfareRate: welfare,
      taxRate: tax,
    );
  }

  Future<void> _save() async {
    final repository = _repository;
    final draft = _draftSetting();
    if (repository == null || draft == null) return;

    setState(() => _saving = true);
    try {
      await repository.saveSetting(draft);
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('支払証明書設定を保存しました')),
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

  Future<void> _preview() async {
    final repository = _repository;
    final draft = _draftSetting();
    if (repository == null || draft == null) return;
    try {
      final record = await repository.previewForSetting(draft);
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => PaymentCertificatePreviewPage(record: record),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('プレビューできませんでした: $error')),
      );
    }
  }

  void _addAllowance() {
    setState(() => _allowances.add(_PaymentAllowanceDraft()));
  }

  void _removeAllowance(int index) {
    final removed = _allowances.removeAt(index);
    removed.dispose();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final daily = _int(_daily);
    final formula = _formula;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          '支払証明書設定',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        actions: const [SkoNotificationBell()],
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(child: Text(_error!, textAlign: TextAlign.center))
                : _items.isEmpty
                    ? const Center(child: Text('協力会社が登録されていません'))
                    : ListView(
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
                        children: [
                          DropdownButtonFormField<String>(
                            initialValue: _partnerId,
                            decoration: InputDecoration(
                              labelText: SkoLanguageController.isEnglish
                                  ? 'Subcontractor Company'
                                  : '協力会社',
                              border: const OutlineInputBorder(),
                            ),
                            items: [
                              for (final item in _items)
                                DropdownMenuItem(
                                  value: item.partnerCompanyId,
                                  child: Text(item.partnerCompanyName),
                                ),
                            ],
                            onChanged: (value) {
                              setState(() => _partnerId = value);
                              _syncControllers();
                            },
                          ),
                          const SizedBox(height: 14),
                          Text(
                            SkoLanguageController.isEnglish
                                ? 'Even without settings, a zero-value draft is generated. It recalculates automatically after settings are saved.'
                                : '未設定でも支払証明書は0円の下書きとして生成されます。設定後は自動で再計算されます。',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          const SizedBox(height: 14),
                          _sectionTitle('基準単価'),
                          SegmentedButton<bool>(
                            segments: const [
                              ButtonSegment(value: false, label: Text('日給')),
                              ButtonSegment(value: true, label: Text('時給')),
                            ],
                            selected: {_hourlyBase},
                            onSelectionChanged: (value) =>
                                setState(() => _hourlyBase = value.first),
                          ),
                          const SizedBox(height: 10),
                          _field(
                            _daily,
                            SkoLanguageController.isEnglish
                                ? (_hourlyBase ? 'Hourly Rate' : 'Daily Rate')
                                : (_hourlyBase ? '基準時給' : '1日単価'),
                          ),
                          Text(
                            _hourlyBase
                                ? '時給を入れると同じ倍率で自動計算します。時給の場合は÷8をせず、倍率を直接掛けます。'
                                : '1日単価を入れると下記単価を自動計算します。各金額欄へ直接入力した場合は、その金額を優先します。',
                          ),
                          const SizedBox(height: 14),
                                                    Text(
                            SkoLanguageController.isEnglish
                                ? 'Overtime Hourly Rate / Early-start Hourly Rate / Night Hourly Rate are calculated automatically unless directly entered.'
                                : '残業・早出・夜勤などは計算式から自動算出し、直接入力した金額がある場合は直接入力を優先します。',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          const SizedBox(height: 10),
_sectionTitle('計算式'),
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                children: [
                                  _factorField(_hoursPerDay, '1日の時間'),
                                  _factorField(_overtimeMultiplier, '残業倍率'),
                                  _factorField(_earlyMultiplier, '早出倍率'),
                                  _factorField(_nightMultiplier, '夜勤倍率'),
                                  _factorField(
                                    _nightOvertimeMultiplier,
                                    '夜勤残業倍率',
                                  ),
                                  _factorField(_holidayMultiplier, '休日出勤倍率'),
                                  _factorField(
                                    _holidayOvertimeMultiplier,
                                    '休日残業倍率',
                                  ),
                                  _factorField(
                                    _holidayNightMultiplier,
                                    '休日夜勤倍率',
                                  ),
                                  _factorField(
                                    _holidayNightOvertimeMultiplier,
                                    '休日夜勤残業倍率',
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),
                          _sectionTitle('自動計算単価 / 直接入力'),
                          _rateField(
                            _overtime,
                            '残業 1時間単価',
                            formula.overtime(daily),
                            formula.overtimeFormula(daily),
                          ),
                          _rateField(
                            _early,
                            '早出 1時間単価',
                            formula.early(daily),
                            formula.earlyFormula(daily),
                          ),
                          _rateField(
                            _nightDay,
                            '夜勤 1日単価',
                            formula.night(daily),
                            formula.nightFormula(daily),
                          ),
                          _rateField(
                            _nightOvertime,
                            '夜勤残業 1時間単価',
                            formula.nightOvertime(daily),
                            formula.nightOvertimeFormula(daily),
                          ),
                          _rateField(
                            _holidayDay,
                            '休日出勤 1日単価',
                            formula.holiday(daily),
                            formula.holidayFormula(daily),
                          ),
                          _rateField(
                            _holidayOvertime,
                            '休日残業 1時間単価',
                            formula.holidayOvertime(daily),
                            formula.holidayOvertimeFormula(daily),
                          ),
                          _rateField(
                            _holidayNightDay,
                            '休日夜勤 1日単価',
                            formula.holidayNight(daily),
                            formula.holidayNightFormula(daily),
                          ),
                          _rateField(
                            _holidayNightOvertime,
                            '休日夜勤残業 1時間単価',
                            formula.holidayNightOvertime(daily),
                            formula.holidayNightOvertimeFormula(daily),
                          ),
                          const SizedBox(height: 14),
                          _sectionTitle('手当'),
                          for (var i = 0; i < _allowances.length; i++)
                            _allowanceCard(i),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: OutlinedButton.icon(
                              onPressed: _addAllowance,
                              icon: const Icon(Icons.add),
                              label: const Text('手当を追加'),
                            ),
                          ),
                          const SizedBox(height: 14),
                          _sectionTitle('福利厚生費・消費税'),
                          _percentField(_welfare, '福利厚生費率'),
                          _percentField(_tax, '消費税率'),
                          const SizedBox(height: 14),
                          const Text(
                            '金額欄が0の場合は計算式の自動計算値を使用します。計算式の数字も変更して保存できます。',
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: _saving ? null : _preview,
                                  icon: const Icon(Icons.preview_outlined),
                                  label: const Text('プレビュー'),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: FilledButton.icon(
                                  onPressed: _saving ? null : _save,
                                  icon: const Icon(Icons.save_outlined),
                                  label: Text(_saving ? '保存中…' : '設定を保存'),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
      ),
    );
  }

  Widget _sectionTitle(String label) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          label,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
        ),
      );

  Widget _field(TextEditingController controller, String label) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextFormField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: label,
            suffixText: '円',
            border: const OutlineInputBorder(),
          ),
        ),
      );

  Widget _factorField(TextEditingController controller, String label) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: TextFormField(
          controller: controller,
          keyboardType:
              const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: label,
            border: const OutlineInputBorder(),
          ),
        ),
      );

  Widget _percentField(TextEditingController controller, String label) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextFormField(
          controller: controller,
          keyboardType:
              const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: label,
            suffixText: '%',
            border: const OutlineInputBorder(),
          ),
        ),
      );

  Widget _rateField(
    TextEditingController controller,
    String label,
    int calculated,
    String formulaText,
  ) =>
      Card(
        margin: const EdgeInsets.only(bottom: 10),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _field(controller, label),
              Text(
                '自動計算 ¥$calculated　式: $formulaText',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 2),
              Text(
                '0なら自動計算 / 1円以上を直接入力するとその金額を使用',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      );

  Widget _allowanceCard(int index) {
    final item = _allowances[index];
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          children: [
            TextFormField(
              controller: item.name,
              decoration: InputDecoration(
                labelText: '手当${index + 1} 名称',
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            _field(item.amount, '手当${index + 1} 単価'),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => _removeAllowance(index),
                icon: const Icon(Icons.delete_outline),
                label: const Text('削除'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _number(double value) =>
      value == value.roundToDouble() ? value.toInt().toString() : value.toString();
}

class _PaymentAllowanceDraft {
  _PaymentAllowanceDraft({String name = '', int amountYen = 0})
      : name = TextEditingController(text: name),
        amount = TextEditingController(text: amountYen.toString());

  final TextEditingController name;
  final TextEditingController amount;

  void dispose() {
    name.dispose();
    amount.dispose();
  }
}
