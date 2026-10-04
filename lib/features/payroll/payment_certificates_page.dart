import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';

import '../notifications/notification_bell.dart';
import '../../international/language_controller.dart';
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
        actions: const [SkoNotificationBell()],
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
  final _overtime = TextEditingController();
  final _early = TextEditingController();
  final _night = TextEditingController();

  List<PartnerPaymentSetting> _items = const [];
  String? _partnerId;
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
    _daily.dispose();
    _overtime.dispose();
    _early.dispose();
    _night.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final repository = _repository;
    if (repository == null) {
      setState(() {
        _loading = false;
        _error = SkoLanguageController.isEnglish ? 'Payment certificate settings are unavailable.' : '支払証明書設定を利用できません。';
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
    _overtime.text = item.overtimeHourRateYen.toString();
    _early.text = item.earlyHourRateYen.toString();
    _night.text = item.nightHourRateYen.toString();
  }

  Future<void> _save() async {
    final repository = _repository;
    final current = _selectedSetting();
    if (repository == null || current == null) return;

    int parse(TextEditingController controller) =>
        int.tryParse(controller.text.trim()) ?? -1;

    final daily = parse(_daily);
    final overtime = parse(_overtime);
    final early = parse(_early);
    final night = parse(_night);

    if ([daily, overtime, early, night].any((value) => value < 0)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(SkoLanguageController.isEnglish ? 'Enter amounts as numbers greater than or equal to 0.' : '金額は0以上の数字で入力してください')),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      await repository.saveSetting(
        PartnerPaymentSetting(
          partnerCompanyId: current.partnerCompanyId,
          partnerCompanyName: current.partnerCompanyName,
          dailyRateYen: daily,
          overtimeHourRateYen: overtime,
          earlyHourRateYen: early,
          nightHourRateYen: night,
        ),
      );
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(SkoLanguageController.isEnglish ? 'Payment certificate settings saved.' : '支払証明書設定を保存しました')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${SkoLanguageController.isEnglish ? 'Could not save' : '保存できませんでした'}: $error')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          SkoLanguageController.isEnglish ? 'Payment Certificate Settings' : '支払証明書設定',
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
                    ? Center(child: Text(SkoLanguageController.isEnglish ? 'No subcontractor companies are registered.' : '協力会社が登録されていません'))
                    : ListView(
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
                        children: [
                          DropdownButtonFormField<String>(
                            initialValue: _partnerId,
                            decoration: InputDecoration(
                              labelText: SkoLanguageController.isEnglish ? 'Subcontractor Company' : '協力会社',
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
                          const SizedBox(height: 16),
                          _field(_daily, SkoLanguageController.isEnglish ? 'Daily Rate' : '人工単価'),
                          _field(_overtime, SkoLanguageController.isEnglish ? 'Overtime Hourly Rate' : '残業1時間単価'),
                          _field(_early, SkoLanguageController.isEnglish ? 'Early-start Hourly Rate' : '早出1時間単価'),
                          _field(_night, SkoLanguageController.isEnglish ? 'Night Hourly Rate' : '夜勤1時間単価'),
                          const SizedBox(height: 8),
                          Text(
                            SkoLanguageController.isEnglish ? 'Even without settings, a zero-value draft is generated. It recalculates automatically after settings are saved.' : '未設定でも支払証明書は0円の下書きとして生成されます。設定後は自動で再計算されます。',
                          ),
                          const SizedBox(height: 16),
                          FilledButton.icon(
                            onPressed: _saving ? null : _save,
                            icon: const Icon(Icons.save_outlined),
                            label: Text(_saving ? (SkoLanguageController.isEnglish ? 'Saving…' : '保存中…') : (SkoLanguageController.isEnglish ? 'Save Settings' : '設定を保存')),
                          ),
                        ],
                      ),
      ),
    );
  }

  Widget _field(TextEditingController controller, String label) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextFormField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: label,
            suffixText: SkoLanguageController.isEnglish ? 'JPY' : '円',
            border: const OutlineInputBorder(),
          ),
        ),
      );
}
