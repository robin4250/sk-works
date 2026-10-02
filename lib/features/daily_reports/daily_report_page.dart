// ignore_for_file: prefer_interpolation_to_compose_strings

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../notifications/notification_bell.dart';
import '../operations/odometer_text_recognition_engine.dart';
import 'daily_report_pdf_service.dart';
import 'daily_report_repository.dart';
import 'signature_capture_page.dart';

class DailyReportPage extends StatefulWidget {
  const DailyReportPage({
    super.key,
    this.initialDate,
    this.initialSiteId,
  });

  final DateTime? initialDate;
  final String? initialSiteId;

  @override
  State<DailyReportPage> createState() => _DailyReportPageState();
}

class _DailyReportPageState extends State<DailyReportPage> {
  final _repository = DailyReportRepository.maybeCreate();
  final _workDescription = TextEditingController();
  final _picker = ImagePicker();
  final _odometerRecognition = const OdometerTextRecognitionEngine();

  late DateTime _date;
  List<DailyReportSiteGroup> _groups = const [];
  String? _siteId;
  String? _siteName;
  List<DailyReportWorkerDraft> _workers = [];
  DailyReportRecord? _report;
  List<DailyReportEvidenceRecord> _evidence = const [];
  bool _loading = true;
  bool _saving = false;
  String? _error;

  final Map<String, TextEditingController> _overtime = {};
  final Map<String, TextEditingController> _early = {};
  final Map<String, TextEditingController> _night = {};
  final Map<String, TextEditingController> _allowance = {};
  final Map<String, TextEditingController> _allowanceLabel = {};
  final Map<String, TextEditingController> _odometer = {};

  bool get _signed => _report?.signed == true;
  bool get _editable => !_signed;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialDate ?? DateTime.now();
    _date = DateTime(initial.year, initial.month, initial.day);
    _siteId = widget.initialSiteId;
    _loadDay();
  }

  @override
  void dispose() {
    _workDescription.dispose();
    _disposeWorkerControllers();
    super.dispose();
  }

  void _disposeWorkerControllers() {
    for (final controller in [
      ..._overtime.values,
      ..._early.values,
      ..._night.values,
      ..._allowance.values,
      ..._allowanceLabel.values,
      ..._odometer.values,
    ]) {
      controller.dispose();
    }
    _overtime.clear();
    _early.clear();
    _night.clear();
    _allowance.clear();
    _allowanceLabel.clear();
    _odometer.clear();
  }

  Future<void> _loadDay() async {
    final repository = _repository;
    if (repository == null) {
      setState(() {
        _loading = false;
        _error = '日報機能を利用できません。';
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final groups = await repository.loadClockedInGroups(_date);
      if (!mounted) return;

      String? nextSite = _siteId;
      if (nextSite == null || !groups.any((g) => g.siteId == nextSite)) {
        nextSite = groups.isNotEmpty ? groups.first.siteId : null;
      }

      setState(() {
        _groups = groups;
        _siteId = nextSite;
        _siteName = nextSite == null
            ? null
            : groups
                .where((g) => g.siteId == nextSite)
                .map((g) => g.siteName)
                .firstOrNull;
      });

      await _loadSelectedSite();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _loadSelectedSite() async {
    final repository = _repository;
    final siteId = _siteId;
    if (repository == null || siteId == null) {
      if (!mounted) return;
      setState(() {
        _report = null;
        _workers = [];
        _evidence = const [];
        _loading = false;
      });
      _resetWorkerControllers();
      return;
    }

    try {
      final existing =
          await repository.loadReport(date: _date, siteId: siteId);
      final evidence = await repository.loadAttendanceEvidence(
        reportId: existing?.id,
        date: _date,
        siteId: siteId,
      );
      if (!mounted) return;

      final group = _groups.where((g) => g.siteId == siteId).firstOrNull;
      final workers = existing?.workers.isNotEmpty == true
          ? existing!.workers
          : List<DailyReportWorkerDraft>.from(group?.workers ?? const []);

      setState(() {
        _report = existing;
        _siteName = existing?.siteName ?? group?.siteName ?? '';
        _workers = workers;
        _evidence = evidence;
        _workDescription.text = existing?.workDescription ?? '';
        _loading = false;
      });
      _resetWorkerControllers();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  void _resetWorkerControllers() {
    _disposeWorkerControllers();
    for (final worker in _workers) {
      _overtime[worker.workerId] =
          TextEditingController(text: _number(worker.overtimeHours));
      _early[worker.workerId] =
          TextEditingController(text: _number(worker.earlyHours));
      _night[worker.workerId] =
          TextEditingController(text: _number(worker.nightHours));
      _allowance[worker.workerId] =
          TextEditingController(text: worker.allowanceAmount.toString());
      _allowanceLabel[worker.workerId] =
          TextEditingController(text: worker.allowanceLabel);
      _odometer[worker.workerId] = TextEditingController(
        text: worker.odometerKm == null ? '' : _number(worker.odometerKm!),
      );
    }
  }

  Future<void> _pickDate() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (selected == null) return;
    setState(() {
      _date = selected;
      _siteId = null;
    });
    await _loadDay();
  }

  Future<void> _selectSite(String? siteId) async {
    if (siteId == null || siteId == _siteId) return;
    setState(() {
      _siteId = siteId;
      _siteName = _groups
          .where((g) => g.siteId == siteId)
          .map((g) => g.siteName)
          .firstOrNull;
      _loading = true;
    });
    await _loadSelectedSite();
  }

  void _applyControllers() {
    for (final worker in _workers) {
      worker.overtimeHours =
          double.tryParse(_overtime[worker.workerId]?.text ?? '') ?? 0;
      worker.earlyHours =
          double.tryParse(_early[worker.workerId]?.text ?? '') ?? 0;
      worker.nightHours =
          double.tryParse(_night[worker.workerId]?.text ?? '') ?? 0;
      worker.allowanceAmount =
          int.tryParse(_allowance[worker.workerId]?.text ?? '') ?? 0;
      worker.allowanceLabel =
          _allowanceLabel[worker.workerId]?.text.trim() ?? '';
      if (worker.vehicleId != null) {
        worker.odometerKm = double.tryParse(
          _odometer[worker.workerId]?.text.trim() ?? '',
        );
      }
    }
  }

  Future<void> _captureOdometer(
    DailyReportWorkerDraft worker,
  ) async {
    final photo = await _picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 92,
      maxWidth: 2400,
    );
    if (photo == null) return;

    OdometerRecognitionResult result;
    try {
      result = await _odometerRecognition.recognizeImagePath(photo.path);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('メーターを読み取れませんでした: $error')),
      );
      return;
    }

    if (!mounted) return;
    final controller = TextEditingController(
      text: result.bestCandidate == null
          ? ''
          : _number(result.bestCandidate!),
    );

    final action = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('メーター読取結果'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              '数値が合っていれば登録してください。違う場合は手入力で修正するか、再撮影できます。',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: '走行距離',
                suffixText: 'km',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, 'retry'),
            child: const Text('再撮影'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, 'use'),
            child: const Text('この数値を登録'),
          ),
        ],
      ),
    );

    if (action == 'retry') {
      controller.dispose();
      await _captureOdometer(worker);
      return;
    }

    if (action == 'use') {
      final value = double.tryParse(controller.text.trim());
      if (value == null || value < 0) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('走行距離を数字で入力してください')),
          );
        }
      } else {
        _odometer[worker.workerId]?.text = _number(value);
        worker.odometerKm = value;
        if (mounted) setState(() {});
      }
    }
    controller.dispose();
  }

  Future<String?> _saveDraft() async {
    final repository = _repository;
    final siteId = _siteId;
    if (repository == null || siteId == null) return null;

    _applyControllers();

    final missingOdometer = _workers.where(
      (worker) => worker.vehicleId != null && worker.odometerKm == null,
    );
    if (missingOdometer.isNotEmpty) {
      final names = missingOdometer.map((worker) => worker.workerName).join('、');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            names + ' の退勤時走行距離を入力してください',
          ),
        ),
      );
      return null;
    }

    setState(() => _saving = true);
    try {
      final id = await repository.saveDraft(
        reportId: _report?.id,
        siteId: siteId,
        date: _date,
        workDescription: _workDescription.text,
        workers: _workers,
      );
      if (!mounted) return id;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('日報を登録しました')),
      );
      await _loadSelectedSite();
      return id;
    } catch (error) {
      if (!mounted) return null;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('登録できませんでした: $error')),
      );
      return null;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _sign() async {
    final reportId = _report?.id ?? await _saveDraft();
    if (reportId == null || !mounted) return;

    final result = await Navigator.of(context).push<SignatureResult>(
      MaterialPageRoute(builder: (_) => const SignatureCapturePage()),
    );
    if (result == null || !mounted) return;

    final repository = _repository;
    if (repository == null) return;

    setState(() => _saving = true);
    try {
      await repository.sign(
        reportId: reportId,
        signerName: result.signerName,
        signatureJson: result.toJson(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('責任者サインで日報を確定しました')),
      );
      await _loadSelectedSite();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('確定できませんでした: $error')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _requestEdit() async {
    final report = _report;
    final repository = _repository;
    if (report == null || repository == null) return;

    final reason = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('確定済み日報を修正'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              '確定済みの日報は直接変更できません。サブ管理者2名へ承認依頼を送ります。',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: reason,
              maxLines: 3,
              decoration: const InputDecoration(labelText: '修正理由（任意）'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('承認依頼を送る'),
          ),
        ],
      ),
    );

    if (confirmed != true) {
      reason.dispose();
      return;
    }

    try {
      await repository.requestEdit(
        reportId: report.id,
        reason: reason.text,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            '承認依頼を送りました。2名の承認後、お知らせから編集できます。',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('承認依頼を送れませんでした: $error')),
      );
    } finally {
      reason.dispose();
    }
  }

  Future<void> _showSignature() async {
    final report = _report;
    if (report?.signatureJson == null) return;
    final strokes = SignatureResult.fromJson(report!.signatureJson);

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('サイン済み：${report.signerName ?? ''}'),
        content: SizedBox(
          width: 460,
          child: SignaturePreview(strokes: strokes, height: 220),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('閉じる'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          '日報',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        actions: const [SkoNotificationBell()],
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? _ErrorState(message: _error!, onRetry: _loadDay)
                : _groups.isEmpty
                    ? _EmptyDay(date: _date, onPickDate: _pickDate)
                    : ListView(
                        padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
                        children: [
                          _HeaderField(
                            icon: Icons.calendar_today_outlined,
                            label: '日付',
                            value:
                                '${_date.year}/${_two(_date.month)}/${_two(_date.day)}',
                            onTap: _pickDate,
                          ),
                          const SizedBox(height: 10),
                          DropdownButtonFormField<String>(
                            initialValue: _siteId,
                            decoration: const InputDecoration(
                              labelText: '現場',
                              prefixIcon: Icon(Icons.business_outlined),
                            ),
                            items: [
                              for (final group in _groups)
                                DropdownMenuItem(
                                  value: group.siteId,
                                  child: Text(group.siteName),
                                ),
                            ],
                            onChanged: _selectSite,
                          ),
                          const SizedBox(height: 16),
                          _MemberSummary(workers: _workers),
                          if (_evidence.isNotEmpty) ...[
                            const SizedBox(height: 10),
                            Card(
                              child: ListTile(
                                leading: const CircleAvatar(
                                  child: Icon(Icons.photo_camera_outlined),
                                ),
                                title: const Text(
                                  '出勤確認写真',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                subtitle: Text(
                                  _evidence.length.toString() +
                                      '枚 / この日報に紐付いています',
                                ),
                                trailing: const Icon(Icons.chevron_right),
                                onTap: () => Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => DailyReportEvidencePage(
                                      date: _date,
                                      siteName: _siteName ?? '',
                                      items: _evidence,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                          const SizedBox(height: 16),
                          TextField(
                            controller: _workDescription,
                            enabled: _editable,
                            minLines: 6,
                            maxLines: 12,
                            decoration: const InputDecoration(
                              labelText: '作業内容',
                              alignLabelWithHint: true,
                              hintText: '本日の作業内容を入力',
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'メンバー別 残業・早出・手当',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.w900),
                          ),
                          const SizedBox(height: 8),
                          for (final worker in _workers) ...[
                            _WorkerDetailCard(
                              worker: worker,
                              editable: _editable,
                              overtime: _overtime[worker.workerId]!,
                              early: _early[worker.workerId]!,
                              night: _night[worker.workerId]!,
                              allowance: _allowance[worker.workerId]!,
                              allowanceLabel:
                                  _allowanceLabel[worker.workerId]!,
                              odometer: _odometer[worker.workerId]!,
                              onCaptureOdometer: () =>
                                  _captureOdometer(worker),
                            ),
                            const SizedBox(height: 8),
                          ],
                          const SizedBox(height: 8),
                          if (_signed)
                            Card(
                              child: ListTile(
                                leading: const CircleAvatar(
                                  child: Icon(Icons.check),
                                ),
                                title: const Text(
                                  'サイン済み・確定',
                                  style: TextStyle(fontWeight: FontWeight.w900),
                                ),
                                subtitle: Text(
                                  _report?.signerName ?? '責任者サイン済み',
                                ),
                                trailing: const Icon(Icons.chevron_right),
                                onTap: _showSignature,
                              ),
                            )
                          else
                            Card(
                              child: ListTile(
                                leading: const CircleAvatar(
                                  child: Icon(Icons.draw_outlined),
                                ),
                                title: const Text(
                                  '責任者サイン',
                                  style: TextStyle(fontWeight: FontWeight.w900),
                                ),
                                subtitle: const Text(
                                  'サインをもらうと、この日報と出勤データが確定します',
                                ),
                                trailing: const Icon(Icons.chevron_right),
                                onTap: _saving ? null : _sign,
                              ),
                            ),
                          const SizedBox(height: 16),
                          if (!_signed)
                            FilledButton.icon(
                              onPressed: _saving ? null : _saveDraft,
                              icon: const Icon(Icons.save_outlined),
                              label: const Text('登録'),
                            ),
                          if (_signed)
                            FilledButton.tonalIcon(
                              onPressed: _saving ? null : _requestEdit,
                              icon: const Icon(Icons.edit_outlined),
                              label: const Text('編集・修正を申請'),
                            ),
                          const SizedBox(height: 10),
                          OutlinedButton.icon(
                            onPressed: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => DailyReportPrintPreviewPage(
                                  date: _date,
                                  siteName: _siteName ?? '',
                                  workers: _workers,
                                  workDescription: _workDescription.text,
                                  report: _report,
                                ),
                              ),
                            ),
                            icon: const Icon(Icons.print_outlined),
                            label: const Text('A4印刷プレビュー'),
                          ),
                        ],
                      ),
      ),
    );
  }

  static String _number(double value) {
    if (value == value.roundToDouble()) return value.toInt().toString();
    return value
        .toStringAsFixed(2)
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');
  }

  static String _two(int value) => value.toString().padLeft(2, '0');
}

class _WorkerDetailCard extends StatelessWidget {
  const _WorkerDetailCard({
    required this.worker,
    required this.editable,
    required this.overtime,
    required this.early,
    required this.night,
    required this.allowance,
    required this.allowanceLabel,
    required this.odometer,
    required this.onCaptureOdometer,
  });

  final DailyReportWorkerDraft worker;
  final bool editable;
  final TextEditingController overtime;
  final TextEditingController early;
  final TextEditingController night;
  final TextEditingController allowance;
  final TextEditingController allowanceLabel;
  final TextEditingController odometer;
  final VoidCallback onCaptureOdometer;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ExpansionTile(
        leading: const CircleAvatar(child: Icon(Icons.person_outline)),
        title: Text(
          worker.workerName,
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        subtitle: Text(
          [
            '個別の残業・早出・手当を設定',
            if (worker.vehicleName?.trim().isNotEmpty == true)
              '車両：' + worker.vehicleName!,
            if (worker.routeName?.trim().isNotEmpty == true)
              'ルート：' + worker.routeName!,
          ].join(' / '),
        ),
        childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
        children: [
          if (worker.vehicleName?.trim().isNotEmpty == true ||
              worker.routeName?.trim().isNotEmpty == true) ...[
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                [
                  if (worker.vehicleName?.trim().isNotEmpty == true)
                    '車両：' + worker.vehicleName!,
                  if (worker.routeName?.trim().isNotEmpty == true)
                    'ルート：' + worker.routeName!,
                ].join('　'),
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
            const SizedBox(height: 10),
          ],
          if (worker.vehicleId != null) ...[
            TextField(
              controller: odometer,
              enabled: editable,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: '退勤時の走行距離',
                suffixText: 'km',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: editable ? onCaptureOdometer : null,
                icon: const Icon(Icons.camera_alt_outlined),
                label: const Text('メーターを撮影して読取'),
              ),
            ),
            const SizedBox(height: 10),
          ],
          Row(
            children: [
              Expanded(
                child: _NumberField(
                  controller: overtime,
                  label: '残業(h)',
                  enabled: editable,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _NumberField(
                  controller: early,
                  label: '早出(h)',
                  enabled: editable,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _NumberField(
                  controller: night,
                  label: '夜間(h)',
                  enabled: editable,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            controller: allowanceLabel,
            enabled: editable,
            decoration: const InputDecoration(
              labelText: '手当名',
              hintText: '例：鉄骨、PC',
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: allowance,
            enabled: editable,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: '手当金額（円）'),
          ),
        ],
      ),
    );
  }
}

class _NumberField extends StatelessWidget {
  const _NumberField({
    required this.controller,
    required this.label,
    required this.enabled,
  });

  final TextEditingController controller;
  final String label;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      enabled: enabled,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(labelText: label),
    );
  }
}

class _MemberSummary extends StatelessWidget {
  const _MemberSummary({required this.workers});

  final List<DailyReportWorkerDraft> workers;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '朝の出勤メンバー  ${workers.length}名',
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final worker in workers)
                  Chip(
                    avatar: const Icon(Icons.person, size: 16),
                    label: Text(worker.workerName),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _HeaderField extends StatelessWidget {
  const _HeaderField({
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Icon(icon),
        title: Text(label),
        subtitle: Text(
          value,
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}

class _EmptyDay extends StatelessWidget {
  const _EmptyDay({
    required this.date,
    required this.onPickDate,
  });

  final DateTime date;
  final VoidCallback onPickDate;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.event_busy_outlined, size: 54),
            const SizedBox(height: 12),
            const Text(
              'この日の出勤メンバーがまだありません',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            const Text(
              '朝の出勤登録が行われると、現場とメンバーが日報へ自動表示されます。',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onPickDate,
              icon: const Icon(Icons.calendar_today),
              label: const Text('日付を変更'),
            ),
          ],
        ),
      ),
    );
  }
}

class DailyReportEvidencePage extends StatelessWidget {
  const DailyReportEvidencePage({
    super.key,
    required this.date,
    required this.siteName,
    required this.items,
  });

  final DateTime date;
  final String siteName;
  final List<DailyReportEvidenceRecord> items;

  @override
  Widget build(BuildContext context) {
    final repository = DailyReportRepository.maybeCreate();
    return Scaffold(
      appBar: AppBar(
        title: const Text('出勤確認写真一覧'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Card(
            child: ListTile(
              leading: const Icon(Icons.calendar_today_outlined),
              title: Text(
                date.year.toString() +
                    '/' +
                    date.month.toString().padLeft(2, '0') +
                    '/' +
                    date.day.toString().padLeft(2, '0'),
              ),
              subtitle: Text(siteName),
            ),
          ),
          const SizedBox(height: 8),
          for (final item in items)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      item.workerName +
                          ' / ' +
                          (item.eventType == 'clock_out' ? '退勤' : '出勤'),
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      item.confirmedAt.hour.toString().padLeft(2, '0') +
                          ':' +
                          item.confirmedAt.minute.toString().padLeft(2, '0'),
                    ),
                    const SizedBox(height: 8),
                    if (repository != null)
                      FutureBuilder<String>(
                        future:
                            repository.attendanceEvidenceUrl(item.storagePath),
                        builder: (context, snapshot) {
                          final url = snapshot.data;
                          if (url == null) {
                            return const SizedBox(
                              height: 180,
                              child: Center(
                                child: CircularProgressIndicator(),
                              ),
                            );
                          }
                          return InteractiveViewer(
                            minScale: 1,
                            maxScale: 5,
                            child: Image.network(
                              url,
                              fit: BoxFit.contain,
                              errorBuilder: (_, __, ___) =>
                                  const SizedBox(
                                height: 180,
                                child: Center(
                                  child: Icon(Icons.broken_image_outlined),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class DailyReportPrintPreviewPage extends StatelessWidget {
  const DailyReportPrintPreviewPage({
    super.key,
    required this.date,
    required this.siteName,
    required this.workers,
    required this.workDescription,
    required this.report,
  });

  final DateTime date;
  final String siteName;
  final List<DailyReportWorkerDraft> workers;
  final String workDescription;
  final DailyReportRecord? report;

  @override
  Widget build(BuildContext context) {
    final strokes = SignatureResult.fromJson(report?.signatureJson);

    return Scaffold(
      appBar: AppBar(
        title: const Text('日報 A4プレビュー'),
        actions: const [SkoNotificationBell()],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            AspectRatio(
              aspectRatio: 1 / 1.414,
              child: Card(
                child: InteractiveViewer(
                  minScale: 0.8,
                  maxScale: 4,
                  child: Padding(
                    padding: const EdgeInsets.all(22),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          '作 業 日 報',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 14),
                        Text('日付  ${date.year}/${date.month}/${date.day}'),
                        Text('現場  $siteName'),
                        const Divider(height: 20),
                        Text(
                          '出勤メンバー（${workers.length}名）',
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 6),
                        for (final worker in workers)
                          Text(
                            '${worker.workerName}  '
                            '残${worker.overtimeHours} 早${worker.earlyHours} '
                            '${worker.allowanceLabel}',
                            style: const TextStyle(fontSize: 11),
                          ),
                        const Divider(height: 20),
                        const Text(
                          '作業内容',
                          style: TextStyle(fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 4),
                        Text(workDescription),
                        const Spacer(),
                        if (report?.signed == true) ...[
                          Text(
                            '責任者：${report?.signerName ?? ''}',
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 5),
                          SignaturePreview(strokes: strokes, height: 90),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: () => DailyReportPdfService.printReport(
                date: date,
                siteName: siteName,
                workers: workers,
                workDescription: workDescription,
                report: report,
              ),
              icon: const Icon(Icons.print),
              label: const Text('印刷'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({
    required this.message,
    required this.onRetry,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_outlined, size: 46),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('再読み込み'),
            ),
          ],
        ),
      ),
    );
  }
}
