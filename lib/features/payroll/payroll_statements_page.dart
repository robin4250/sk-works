import 'dart:async';
import 'own_draft_bank_admission.dart';
import 'own_draft_bank_repository.dart';
import 'payroll_pending_attendance_panel.dart';
import 'payroll_condition_warning.dart';
import 'payroll_finalization_panel.dart';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';

import '../notifications/notification_bell.dart';
import '../shared/pdf_bytes_cache.dart';
import '../../international/language_controller.dart';
import '../../data/supabase_backend.dart';
import 'payroll_pdf_service.dart';
import 'payroll_insurance_evidence_card.dart';
import 'payroll_statement_repository.dart';
import 'payroll_confirmation_repository.dart';
import 'payroll_statement_source_repository.dart';

class PayrollStatementsPage extends StatefulWidget {
  const PayrollStatementsPage({super.key});

  @override
  State<PayrollStatementsPage> createState() => _PayrollStatementsPageState();
}

class _PayrollStatementsPageState extends State<PayrollStatementsPage> {
  final _repository = PayrollStatementRepository.maybeCreate();

  List<PayrollStatementRecord> _items = const [];
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
        _error = SkoLanguageController.isEnglish
            ? 'Payslips are unavailable.'
            : '給与明細を利用できません。';
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final items = await repository.loadMyStatements();
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
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
          SkoLanguageController.isEnglish ? 'Payslips' : '給与明細',
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        actions: const [SkoNotificationBell()],
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
            ? _ErrorState(message: _error!, onRetry: _load)
            : _items.isEmpty
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.payments_outlined, size: 56),
                      const SizedBox(height: 12),
                      Text(
                        SkoLanguageController.isEnglish
                            ? 'No payslips have been issued yet.'
                            : '給与明細はまだ発行されていません',
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ],
                  ),
                ),
              )
            : RefreshIndicator(
                onRefresh: _load,
                child: ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: _items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final item = _items[index];
                    return Card(
                      child: InkWell(
                        borderRadius: BorderRadius.circular(20),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) =>
                                PayrollStatementPreviewPage(statement: item),
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(18),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.monthLabel,
                                style: Theme.of(context).textTheme.titleLarge
                                    ?.copyWith(fontWeight: FontWeight.w900),
                              ),
                              const SizedBox(height: 6),
                              if (item.companyName.isNotEmpty)
                                Text(
                                  item.companyName,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              if (item.workerName.isNotEmpty)
                                Text(item.workerName),
                              const SizedBox(height: 6),
                              Text(
                                item.reviewConfirmed
                                    ? (SkoLanguageController.isEnglish
                                          ? 'Confirmed'
                                          : '確認済み')
                                    : (SkoLanguageController.isEnglish
                                          ? 'Unconfirmed'
                                          : '未確認'),
                                style: TextStyle(
                                  color: item.reviewConfirmed
                                      ? Colors.green
                                      : Theme.of(context).colorScheme.error,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      SkoLanguageController.isEnglish
                                          ? 'Net Pay'
                                          : '差引支給額',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyMedium,
                                    ),
                                  ),
                                  Text(
                                    _yen(item.netPay),
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleLarge
                                        ?.copyWith(fontWeight: FontWeight.w900),
                                  ),
                                  const SizedBox(width: 6),
                                  const Icon(Icons.chevron_right),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
      ),
    );
  }

  static String _yen(int value) {
    final digits = value.abs().toString();
    final groups = <String>[];
    for (var end = digits.length; end > 0; end -= 3) {
      final start = (end - 3).clamp(0, digits.length);
      groups.insert(0, digits.substring(start, end));
    }
    return '${value < 0 ? '-' : ''}¥${groups.join(',')}';
  }
}

class PayrollStatementPreviewPage extends StatefulWidget {
  const PayrollStatementPreviewPage({super.key, required this.statement, this.allowFinalization = false, this.sourceRepository, this.ownBankGateway});

  final PayrollStatementRecord statement;
  final bool allowFinalization;
  final PayrollStatementSourceRepository? sourceRepository;
  final OwnDraftBankGateway? ownBankGateway;

  @override
  State<PayrollStatementPreviewPage> createState() =>
      _PayrollStatementPreviewPageState();
}

class _PayrollStatementPreviewPageState
    extends State<PayrollStatementPreviewPage> {
  final _confirmationRepository = PayrollConfirmationRepository.maybeCreate();
  PayrollConfirmationStatus? _confirmation;
  PayrollStatementRecord? _refreshedStatement;
  bool _statementUnavailable = false;
  bool _confirmationBusy = false;
  bool _sourceLoading = false;
  bool _finalizationBusy = false;
  bool _finalizationUncertain = false;
  String? _confirmationError;
  final _pdfBytes = PdfBytesCache();
  OwnDraftBankGateway? _bankGateway;
  OwnDraftBankAdmission? _bankAdmission;
  bool _bankLoading=false;
  String? _bankError;
  int _bankGeneration=0;

  @override
  void initState() {
    super.initState();
    if(widget.statement.ownDraftBankPurpose && widget.statement.isDraft){
      _bankGateway=widget.ownBankGateway??OwnDraftBankRepository.maybeCreate();
      _bankGateway?.addListener(_bankScopeChanged);
    }
    _loadConfirmation();
  }

  void _ensureOwnBankGateway(){
    if(_bankGateway!=null)return;
    _bankGateway=widget.ownBankGateway??OwnDraftBankRepository.maybeCreate();
    _bankGateway?.addListener(_bankScopeChanged);
  }
  void _bankScopeChanged(){
    if(!mounted||_bankGateway?.isCurrent==true)return;
    _bankGeneration++;_bankAdmission=null;_pdfBytes.invalidate();
    setState((){_bankLoading=false;_bankError='ログイン状態が変わりました。口座を再確認してください。';});
  }
  Future<void> _resolveOwnBank(PayrollStatementRecord source) async {
    if(!source.isDraft||!source.ownDraftBankPurpose)return;
    _ensureOwnBankGateway();
    final generation=++_bankGeneration;_bankAdmission=null;_pdfBytes.invalidate();
    setState((){_bankLoading=true;_bankError=null;});
    try{
      final gateway=_bankGateway;if(gateway==null)throw StateError('口座確認を利用できません。');
      final value=await gateway.read(source);
      final current=_refreshedStatement??widget.statement;
      if(!mounted||generation!=_bankGeneration||!gateway.isCurrent||current.id!=source.id||current.revision!=source.revision||!current.isDraft)return;
      setState((){_bankAdmission=value.withLease(() {
        if(!mounted||generation!=_bankGeneration)return false;
        final active=_refreshedStatement??widget.statement;
        return active.isDraft&&active.id==source.id&&active.revision==source.revision;
      });_bankError=value.state==OwnDraftBankState.unavailable?'個人口座を確認できません。未登録とは判断せず、給与金額は保持しています。':null;_pdfBytes.invalidate();});
    }catch(_){if(mounted&&generation==_bankGeneration)setState(()=>_bankError='個人口座を確認できません。未登録とは判断せず、給与金額は保持しています。');}
    finally{if(mounted&&generation==_bankGeneration)setState(()=>_bankLoading=false);}
  }

  Future<PayrollStatementRecord?> _loadConfirmation() async {
    final repository = widget.sourceRepository ?? PayrollStatementSourceRepository.maybeCreate();
    if (repository == null) {
      if (SupabaseBackend.isInitialized) {
        setState(() => _statementUnavailable = true);
      }
      return null;
    }
    _bankGeneration++;_bankAdmission=null;_pdfBytes.invalidate();
    setState(() { _sourceLoading = true; _confirmationError = null; });
    try {
      final source = await repository.load(widget.statement);
      if (!mounted) return null;
      setState(() {
        _confirmation = source.confirmation;
        _refreshedStatement = source.statement;
        _statementUnavailable = false;
        _pdfBytes.invalidate();
      });
      unawaited(_resolveOwnBank(source.statement));
      return source.statement;
    } catch (error) {
      if (mounted) {
        setState(() {
          _confirmation = null;
          _confirmationError = SkoLanguageController.trParams(
            '給与明細を再取得できませんでした: {error}', {'error': error});
          _pdfBytes.invalidate();
        });
      }
      return null;
    } finally {
      if (mounted) setState(() => _sourceLoading = false);
    }
  }

  Future<void> _confirm(bool cancel) async {
    final repository = _confirmationRepository;
    final status = _confirmation;
    if (repository == null || status == null || _confirmationBusy || _finalizationBusy) return;
    if (cancel ? !status.canCancel : !status.canConfirm) return;
    if (!cancel && !await confirmPayrollConditions(
      context, payrollConditionWarnings(_pdfStatement.detail),
    )) {
      return;
    }
    if (!mounted) return;
    setState(() => _confirmationBusy = true);
    try {
      if (cancel) {
        await repository.cancelMonth(widget.statement.periodStart);
      } else {
        await repository.confirmMonth(widget.statement.periodStart);
      }
      if (mounted) {
        setState(() => _statementUnavailable = true);
      }
      await _loadConfirmation();
    } catch (error) {
      if (mounted) {
        setState(() => _confirmationError = '$error');
      }
    } finally {
      if (mounted) {
        setState(() => _confirmationBusy = false);
      }
    }
  }

  PayrollStatementRecord get _pdfStatement {
    final loaded = _refreshedStatement ?? widget.statement;
    final original = loaded.ownDraftBankPurpose && loaded.isDraft ? asOwnDraftStatement(loaded,admission:_bankAdmission)
        : widget.statement.managementBankHidden ? asManagementBankHiddenStatement(loaded) : loaded;
    final status = _confirmation;
    return payrollStatementWithDraftReview(
      original, confirmed: status?.confirmed,
      draftCompanyName: widget.statement.companyName,
    );
  }

  void _showPreviewHelp() {
    showModalBottomSheet<void>(context: context, showDragHandle: true,
      builder: (context) => SafeArea(child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(SkoLanguageController.isEnglish ? 'Preview help' : 'プレビューの使い方',
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
          const SizedBox(height: 12),
          Text(SkoLanguageController.isEnglish
            ? 'Pinch to zoom. Drag to move while zoomed.'
            : '2本指で拡大・縮小／拡大後はドラッグで移動'),
          if (widget.allowFinalization) ...[
            const SizedBox(height: 12),
            const Text(PayrollFinalizationPanel.helpText),
          ],
          const SizedBox(height: 12),
          TextButton(onPressed: () => Navigator.pop(context), child: Text(SkoLanguageController.tr('閉じる'))),
        ]),
      )));
  }

  void _showConfirmationDetails() {
    final status = _confirmation;
    if (status == null) return;
    showModalBottomSheet<void>(context: context, showDragHandle: true,
      builder: (context) => SafeArea(child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(SkoLanguageController.trParams('確認 {confirmed}/{required}名',
            {'confirmed': status.confirmedCount, 'required': status.requiredCount}),
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
          for (final reviewer in status.reviewers) Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(SkoLanguageController.trParams('{name}：{status}',
              {'name': reviewer.name, 'status': SkoLanguageController.tr(reviewer.confirmed ? '確認済み' : '未確認')})),
          ),
          if (status.confirmationOpenDate != null) Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(SkoLanguageController.trParams('確認開始：{date}',
              {'date': '${status.confirmationOpenDate!.month}/${status.confirmationOpenDate!.day}'})),
          ),
          const SizedBox(height: 12),
          TextButton(onPressed: () => Navigator.pop(context), child: Text(SkoLanguageController.tr('閉じる'))),
        ]),
      )));
  }

  final TransformationController _zoomController = TransformationController();

  @override
  void dispose() {
    _bankGeneration++;_bankAdmission=null;_pdfBytes.invalidate();
    _bankGateway?.removeListener(_bankScopeChanged);
    if(widget.ownBankGateway==null)unawaited(_bankGateway?.close()??Future<void>.value());
    _zoomController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    SkoLanguageController.watch(context);
    final statement = _pdfStatement;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          SkoLanguageController.isEnglish ? 'Payslip' : '給与明細書',
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        actions: [
          IconButton(
            tooltip: SkoLanguageController.isEnglish ? 'Preview help' : 'プレビューの使い方',
            onPressed: _showPreviewHelp,
            icon: const Icon(Icons.help_outline),
          ),
          IconButton(
            tooltip: SkoLanguageController.isEnglish
                ? 'Reset zoom'
                : '拡大縮小をリセット',
            onPressed: () => _zoomController.value = Matrix4.identity(),
            icon: const Icon(Icons.fit_screen_outlined),
          ),
          const SkoNotificationBell(),
        ],
      ),
      body: Column(
        children: [
          if (widget.allowFinalization)
            PayrollFinalizationPanel(statement: _pdfStatement, showHelp: false,
              statementAvailable: !_sourceLoading && !_statementUnavailable && _confirmationError == null,
              reloadStatement: _loadConfirmation,
              onBusyChanged: (busy) { if (mounted) setState(() => _finalizationBusy = busy); },
              onVerificationRequired: (needsVerification) { if (mounted) setState(() => _finalizationUncertain = needsVerification); },
              onSaved: (saved) { if (mounted) { setState(() {
                _refreshedStatement = saved; _confirmation = null; _finalizationUncertain = false;
                _statementUnavailable = false; _pdfBytes.invalidate();
              }); } }),
          if (!_statementUnavailable)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: PayrollConditionWarning(
                warnings: payrollConditionWarnings(_pdfStatement.detail),
              ),
            ),
          if (_confirmationError != null)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _confirmationError!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: _finalizationBusy || _sourceLoading ? null : _loadConfirmation,
                    icon: const Icon(Icons.refresh),
                  ),
                ],
              ),
            ),
          if (widget.allowFinalization && statement.isDraft && !_sourceLoading &&
              !_confirmationBusy && !_finalizationBusy && !_statementUnavailable && _confirmationError == null)
            PayrollPendingAttendancePanel(
              key: ValueKey(statement),
              statementId: statement.id,
              onReturn: () async { await _loadConfirmation(); },
            ),
          if (_confirmation != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Wrap(
                spacing: 12,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  TextButton.icon(
                    onPressed: _showConfirmationDetails,
                    icon: const Icon(Icons.fact_check_outlined, size: 18),
                    label: Text(SkoLanguageController.trParams('確認 {confirmed}/{required}名',
                      {'confirmed': _confirmation!.confirmedCount, 'required': _confirmation!.requiredCount})),
                  ),
                  if (_confirmation!.canConfirm)
                    FilledButton(
                      onPressed: _confirmationBusy || _finalizationBusy
                          ? null
                          : () => _confirm(false),
                      child: Text(SkoLanguageController.tr('月の給与を確認')),
                    ),
                  if (_confirmation!.canCancel)
                    TextButton(
                      onPressed: _confirmationBusy
                          ? null
                          : () => _confirm(true),
                      child: Text(SkoLanguageController.tr('確認を取り消す')),
                    ),
                ],
              ),
            ),
          if (!_statementUnavailable && !_sourceLoading && !_confirmationBusy &&
              !_finalizationBusy && !_finalizationUncertain && _confirmationError == null)
            PayrollInsuranceEvidenceCard(detail: statement.detail,
              month: '${statement.periodStart.year.toString().padLeft(4, '0')}-${statement.periodStart.month.toString().padLeft(2, '0')}-01'),
          Expanded(
            key: const ValueKey('payroll-preview-region'),
            child: _sourceLoading || _confirmationBusy || _finalizationBusy
                ? const Center(child: CircularProgressIndicator())
                : _statementUnavailable || _finalizationUncertain || _confirmationError != null
                ? Center(child: Text(SkoLanguageController.tr('この給与明細を閲覧できません。')))
                : statement.isDraft && statement.ownDraftBankPurpose && statement.ownDraftBankAdmission?.permits(statement.id,statement.revision)!=true
                ? Center(child: Padding(padding:const EdgeInsets.all(16),child:Column(mainAxisSize:MainAxisSize.min,children:[
                    Text('支給額 ${statement.grossPay}円 / 控除額 ${statement.deductions}円 / 差引支給額 ${statement.netPay}円'),
                    Text(_bankLoading?'個人口座を確認しています。':(_bankError??'個人口座の確認が必要です。未登録とは判断していません。')),
                    const Text('口座を確認するまで、この下書きのプレビュー・印刷・PDF共有を停止しています。確定済み明細には影響しません。'),
                    OutlinedButton(onPressed:_bankLoading?null:()=>_resolveOwnBank(statement),child:const Text('口座を再確認')),
                  ])))
                : statement.detail['tax_calculation'] is Map &&
                    (statement.detail['tax_calculation'] as Map)['blocked'] == true
                ? Center(child: Text('税計算の条件を確認してください。\n${(statement.detail['tax_calculation'] as Map)['reason']}'))
                : InteractiveViewer(
                    transformationController: _zoomController,
                    minScale: 1,
                    maxScale: 5,
                    panEnabled: true,
                    scaleEnabled: true,
                    boundaryMargin: const EdgeInsets.all(120),
                    clipBehavior: Clip.none,
                    child: PdfPreview(
                      key: ValueKey(_refreshedStatement ?? _confirmation),
                      initialPageFormat: PdfPageFormat.a4,
                      canChangePageFormat: false,
                      canChangeOrientation: false,
                      allowPrinting: true,
                      allowSharing: true,
                      pdfFileName:
                          '${statement.monthLabel}_${statement.workerName}_給与明細.pdf',
                      build: (_) => _pdfBytes.get(
                        () => PayrollPdfService.buildPdf(statement),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    SkoLanguageController.watch(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: Text(SkoLanguageController.isEnglish ? 'Reload' : '再読み込み'),
            ),
          ],
        ),
      ),
    );
  }
}
