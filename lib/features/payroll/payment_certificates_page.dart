import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';

import '../notifications/notification_bell.dart';
import '../../international/language_controller.dart';
import '../../widgets/rate_calculation_card.dart';
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
  final _welfare = TextEditingController();
  final _tax = TextEditingController();

  List<PartnerPaymentSetting> _items = const [];
  final _allowances = <_NamedAmountDraft>[];
  String? _partnerId;
  RateCalculationDraft? _rateDraft;
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
    _welfare.dispose();
    _tax.dispose();
    for (final item in _allowances) {
      item.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final repository = _repository;
    if (repository == null) {
      setState(() {
        _loading = false;
        _error = '支払証明書設定を利用できません。';
      });
      return;
    }
    try {
      final items = await repository.loadSettings();
      if (!mounted) return;
      final previous = _partnerId;
      setState(() {
        _items = items;
        _partnerId = items.any((item) => item.partnerCompanyId == previous)
            ? previous
            : items.isEmpty
                ? null
                : items.first.partnerCompanyId;
        _loading = false;
        _error = null;
      });
      _syncFromSelected();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  PartnerPaymentSetting? _selectedSetting() {
    for (final item in _items) {
      if (item.partnerCompanyId == _partnerId) return item;
    }
    return null;
  }

  void _syncFromSelected() {
    final item = _selectedSetting();
    if (item == null) return;
    for (final old in _allowances) {
      old.dispose();
    }
    _allowances
      ..clear()
      ..addAll(
        item.allowances.map(
          (value) => _NamedAmountDraft(
            name: value.name,
            amountYen: value.amountYen,
          ),
        ),
      );
    _welfare.text = item.welfareRate.toString();
    _tax.text = item.taxRate.toString();
    _rateDraft = null;
    if (mounted) setState(() {});
  }

  PartnerPaymentSetting? _draftSetting() {
    final current = _selectedSetting();
    final rate = _rateDraft;
    if (current == null || rate == null) return null;

    final welfare = double.tryParse(_welfare.text.trim());
    final tax = double.tryParse(_tax.text.trim());
    if (welfare == null || welfare < 0 || tax == null || tax < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('福利厚生費率・消費税率は0以上の数字で入力してください')),
      );
      return null;
    }

    final allowances = <PaymentAllowanceSetting>[];
    for (var i = 0; i < _allowances.length; i++) {
      final name = _allowances[i].name.text.trim();
      final amount = int.tryParse(_allowances[i].amount.text.trim());
      if (name.isEmpty && (amount == null || amount == 0)) continue;
      if (name.isEmpty || amount == null || amount < 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('手当' + (i + 1).toString() + 'を確認してください')),
        );
        return null;
      }
      allowances.add(
        PaymentAllowanceSetting(name: name, amountYen: amount),
      );
    }

    return PartnerPaymentSetting(
      partnerCompanyId: current.partnerCompanyId,
      partnerCompanyName: current.partnerCompanyName,
      dailyRateYen: rate.calculated.daily,
      overtimeHourRateYen: rate.overrides['overtime'] ?? 0,
      earlyHourRateYen: rate.overrides['early'] ?? 0,
      nightHourRateYen: rate.calculated.hourly,
      nightDayRateYen: rate.overrides['night'] ?? 0,
      nightOvertimeHourRateYen: rate.overrides['night_overtime'] ?? 0,
      holidayDayRateYen: rate.overrides['holiday'] ?? 0,
      holidayOvertimeHourRateYen: rate.overrides['holiday_overtime'] ?? 0,
      holidayNightDayRateYen: rate.overrides['holiday_night'] ?? 0,
      holidayNightOvertimeHourRateYen:
          rate.overrides['holiday_night_overtime'] ?? 0,
      rateFormula: rate.formulaJson(),
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
        SnackBar(content: Text('保存できませんでした: ' + error.toString())),
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
        SnackBar(content: Text('プレビューできませんでした: ' + error.toString())),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final selected = _selectedSetting();
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
                : selected == null
                    ? const Center(child: Text('協力会社が登録されていません'))
                    : ListView(
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
                        children: [
                          DropdownButtonFormField<String>(
                            initialValue: _partnerId,
                            decoration: const InputDecoration(
                              labelText: '協力会社',
                              border: OutlineInputBorder(),
                            ),
                            items: [
                              for (final item in _items)
                                DropdownMenuItem(
                                  value: item.partnerCompanyId,
                                  child: Text(item.partnerCompanyName),
                                ),
                            ],
                            onChanged: (value) {
                              _partnerId = value;
                              _syncFromSelected();
                            },
                          ),
                          const SizedBox(height: 14),
                          RateCalculationCard(
                            key: ValueKey('payment-rate-' + selected.partnerCompanyId),
                            title: '単価 自動計算',
                            initialBaseRateYen: selected.dailyRateYen,
                            initialFormula: selected.rateFormula,
                            initialOverrides: selected.rateOverrides,
                            enabled: !_saving,
                            onChanged: (value) => _rateDraft = value,
                          ),
                          const Text(
                            '各単価は0のとき計算式から自動算出します。直接入力した単価はそちらを優先します。',
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            '手当',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                          ),
                          const SizedBox(height: 8),
                          for (var i = 0; i < _allowances.length; i++)
                            _allowanceField(i),
                          OutlinedButton.icon(
                            onPressed: _saving
                                ? null
                                : () => setState(
                                      () => _allowances.add(_NamedAmountDraft()),
                                    ),
                            icon: const Icon(Icons.add),
                            label: const Text('手当を追加'),
                          ),
                          const SizedBox(height: 16),
                          _decimalField(_welfare, '福利厚生費率', '%'),
                          _decimalField(_tax, '消費税率', '%'),
                          const SizedBox(height: 10),
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

  Widget _allowanceField(int index) {
    final item = _allowances[index];
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          children: [
            TextField(
              controller: item.name,
              decoration: InputDecoration(
                labelText: '手当' + (index + 1).toString() + ' 名称',
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: item.amount,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: '手当' + (index + 1).toString() + ' 単価',
                suffixText: '円',
                border: const OutlineInputBorder(),
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: _saving
                    ? null
                    : () {
                        final removed = _allowances.removeAt(index);
                        removed.dispose();
                        setState(() {});
                      },
                icon: const Icon(Icons.delete_outline),
                label: const Text('削除'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _decimalField(
    TextEditingController controller,
    String label,
    String suffix,
  ) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: label,
            suffixText: suffix,
            border: const OutlineInputBorder(),
          ),
        ),
      );
}

class _NamedAmountDraft {
  _NamedAmountDraft({String name = '', int amountYen = 0})
      : name = TextEditingController(text: name),
        amount = TextEditingController(text: amountYen.toString());

  final TextEditingController name;
  final TextEditingController amount;

  void dispose() {
    name.dispose();
    amount.dispose();
  }
}
