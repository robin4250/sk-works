import 'site_payment_agreement_page.dart';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';

import '../notifications/notification_bell.dart';
import '../shared/pdf_bytes_cache.dart';
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
      final items = await repository.loadCertificates(includeRegisteredPreviews: true);
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
    SkoLanguageController.watch(context);
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
                          SkoLanguageController.isEnglish ? 'Register a subcontractor company to preview its payment certificate.' : '下請け会社を登録すると、出勤実績がなくても支払証明書をプレビューできます。',
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
                                  item.isPreview
                                      ? '${item.monthLabel} ・ ${SkoLanguageController.isEnglish ? 'Preview · No attendance' : 'プレビュー・出勤実績なし'}'
                                      : '${item.monthLabel} ・ '
                                  '${item.status == 'draft' ? (SkoLanguageController.isEnglish ? 'Draft' : '下書き') : (SkoLanguageController.isEnglish ? 'Finalized' : '確定')} ・ '
                                  'revision ${item.revision}',
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      item.isPreview ? '' : _yen(item.netAmount),
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

class PaymentCertificatePreviewPage extends StatefulWidget {
  const PaymentCertificatePreviewPage({
    super.key,
    required this.record,
  });

  final PaymentCertificateRecord record;

  @override
  State<PaymentCertificatePreviewPage> createState() =>
      _PaymentCertificatePreviewPageState();
}

class _PaymentCertificatePreviewPageState
    extends State<PaymentCertificatePreviewPage> {
  final _pdfBytes = PdfBytesCache();

  @override
  void didUpdateWidget(covariant PaymentCertificatePreviewPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.record, widget.record)) {
      _pdfBytes.invalidate();
    }
  }

  @override
  Widget build(BuildContext context) {
    SkoLanguageController.watch(context);
    final record = widget.record;
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
        build: (_) => _pdfBytes.get(
          () => PaymentCertificatePdfService.buildPdf(record),
        ),
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
    _daily.text = (item.formulas.hourlyBase && item.hourlyBaseRateYen > 0
            ? item.hourlyBaseRateYen
            : item.dailyRateYen)
        .toString();
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
            _double(_nightOvertimeMultiplier, 1.25),
        holidayMultiplier: _double(_holidayMultiplier, 1.35),
        holidayOvertimeMultiplier:
            _double(_holidayOvertimeMultiplier, 1.25),
        holidayNightMultiplier: _double(_holidayNightMultiplier, 1.6),
        holidayNightOvertimeMultiplier:
            _double(_holidayNightOvertimeMultiplier, 1.25),
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
          SnackBar(content: Text(SkoLanguageController.tr('金額は0以上の数字で入力してください'))),
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
          SnackBar(content: Text(SkoLanguageController.tr('計算式の数値は0以上、1日の時間は0より大きい数で入力してください'))),
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
          SnackBar(content: Text(SkoLanguageController.tr('福利厚生費率・消費税率は0～100で入力してください'))),
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
            SnackBar(content: Text(SkoLanguageController.trParams('手当{number}の名称と0以上の金額を入力してください', {'number': index + 1}))),
          );
        }
        return null;
      }
      allowances.add(PaymentAllowanceSetting(name: name, amountYen: amount));
    }

    final baseInput = _int(_daily);
    return PartnerPaymentSetting(
      partnerCompanyId: current.partnerCompanyId,
      partnerCompanyName: current.partnerCompanyName,
      dailyRateYen: formula.dailyBase(baseInput),
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
      hourlyBaseRateYen: formula.hourlyBase ? baseInput : 0,
      allowances: allowances,
      welfareRate: welfare,
      taxRate: tax,
    );
  }

  Future<void> _save() async {
    if (_saving) return;
    final repository = _repository;
    final draft = _draftSetting();
    if (repository == null || draft == null) return;

    setState(() => _saving = true);
    try {
      await repository.saveSetting(draft);
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(SkoLanguageController.tr('支払証明書設定を保存しました'))),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(SkoLanguageController.trParams('保存できませんでした: {error}', {'error': error}))),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _preview() async {
    if (_saving) return;
    final repository = _repository;
    final draft = _draftSetting();
    if (repository == null || draft == null) return;
    setState(() => _saving = true);
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
        SnackBar(content: Text(SkoLanguageController.trParams('プレビューできませんでした: {error}', {'error': error}))),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
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
    SkoLanguageController.watch(context);
    final daily = _int(_daily);
    final formula = _formula;

    return Scaffold(
      appBar: AppBar(
        title: Text(SkoLanguageController.tr('支払証明書設定'),
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        actions: const [SkoNotificationBell()],
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(child: Text(_error!, textAlign: TextAlign.center))
                : _items.isEmpty
                    ? Center(child: Text(SkoLanguageController.tr('協力会社が登録されていません')))
                    : AbsorbPointer(
                        absorbing: _saving,
                        child: ListView(
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
                            onChanged: _saving ? null : (value) {
                              setState(() => _partnerId = value);
                              _syncControllers();
                            },
                          ),
                          const SizedBox(height: 14),
                          Text(SkoLanguageController.tr('支払証明書の単価・税率・福利厚生費率は、選択した下請け会社のこの設定を使用します。社員の給与単価とは別に管理します。')),
                          const SizedBox(height: 10),
                          OutlinedButton.icon(onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SitePaymentAgreementPage())), icon: const Icon(Icons.handshake_outlined), label: const Text('現場別の支払金額調整')),
                          _sectionTitle('基準単価'),
                          SegmentedButton<bool>(
                            segments: [
                              ButtonSegment(value: false, label: Text(SkoLanguageController.tr('日給'))),
                              ButtonSegment(value: true, label: Text(SkoLanguageController.tr('時給'))),
                            ],
                            selected: {_hourlyBase},
                            onSelectionChanged: _saving ? null : (value) =>
                                setState(() => _hourlyBase = value.first),
                          ),
                          const SizedBox(height: 10),
                          _field(
                            _daily,
                            _hourlyBase ? '基準時給' : '1日単価',
                          ),
                          Text(
                            SkoLanguageController.tr(_hourlyBase
                                ? '時給を入れると同じ倍率体系で自動計算します。残業・早出は時給×倍率、夜勤・休日系の日額は時給×1日時間×倍率です。'
                                : '1日単価を入れると下記単価を自動計算します。各金額欄へ直接入力した場合は、その金額を優先します。'),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            SkoLanguageController.isEnglish
                                ? 'Even without settings, a zero-value draft is generated and recalculated after saving.'
                                : '未設定でも支払証明書は0円の下書きとして生成されます。設定後は自動で再計算されます。',
                          ),
                          const SizedBox(height: 14),
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
                              onPressed: _saving ? null : _addAllowance,
                              icon: const Icon(Icons.add),
                              label: Text(SkoLanguageController.tr('手当を追加')),
                            ),
                          ),
                          const SizedBox(height: 14),
                          _sectionTitle('福利厚生費・消費税'),
                          _percentField(_welfare, '福利厚生費率'),
                          _percentField(_tax, '消費税率'),
                          const SizedBox(height: 14),
                          Text(SkoLanguageController.tr('金額欄が0の場合は計算式の自動計算値を使用します。計算式の数字も変更して保存できます。'),
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: _saving ? null : _preview,
                                  icon: const Icon(Icons.preview_outlined),
                                  label: Text(SkoLanguageController.tr('プレビュー')),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: FilledButton.icon(
                                  onPressed: _saving ? null : _save,
                                  icon: const Icon(Icons.save_outlined),
                                  label: Text(SkoLanguageController.tr(_saving ? '処理中…' : '設定を保存')),
                                ),
                              ),
                            ],
                          ),
                        ],
                        ),
                      ),
      ),
    );
  }

  Widget _sectionTitle(String label) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          SkoLanguageController.tr(label),
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
        ),
      );

  Widget _field(TextEditingController controller, String label) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextFormField(
          enabled: !_saving,
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: SkoLanguageController.tr(label),
            suffixText: SkoLanguageController.tr('円'),
            border: const OutlineInputBorder(),
          ),
        ),
      );

  Widget _factorField(TextEditingController controller, String label) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: TextFormField(
          enabled: !_saving,
          controller: controller,
          keyboardType:
              const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: SkoLanguageController.tr(label),
            border: const OutlineInputBorder(),
          ),
        ),
      );

  Widget _percentField(TextEditingController controller, String label) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextFormField(
          enabled: !_saving,
          controller: controller,
          keyboardType:
              const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: SkoLanguageController.tr(label),
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
              Text(SkoLanguageController.trParams('自動計算 ¥{amount}　式: {formula}', {'amount': calculated, 'formula': formulaText}),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 2),
              Text(SkoLanguageController.tr('0なら自動計算 / 1円以上を直接入力するとその金額を使用'),
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
              enabled: !_saving,
              controller: item.name,
              decoration: InputDecoration(
                labelText: SkoLanguageController.trParams('手当{number} 名称', {'number': index + 1}),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            _field(item.amount, SkoLanguageController.trParams('手当{number} 単価', {'number': index + 1})),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: _saving ? null : () => _removeAllowance(index),
                icon: const Icon(Icons.delete_outline),
                label: Text(SkoLanguageController.tr('削除')),
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
