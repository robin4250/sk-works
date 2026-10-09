import 'payroll_condition_warning.dart';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../notifications/notification_bell.dart';
import '../shared/pdf_bytes_cache.dart';
import '../../international/language_controller.dart';
import 'payroll_pdf_service.dart';
import 'payroll_statement_repository.dart';
import 'payroll_confirmation_repository.dart';
import 'payroll_review_repository.dart';

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
  const PayrollStatementPreviewPage({super.key, required this.statement});

  final PayrollStatementRecord statement;

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
  String? _confirmationError;
  final _pdfBytes = PdfBytesCache();

  @override
  void initState() {
    super.initState();
    _loadConfirmation();
  }

  Future<void> _loadConfirmation() async {
    final repository = _confirmationRepository;
    if (repository == null) return;
    try {
      final status = await repository.loadStatus(widget.statement.periodStart);
      final reviewRepository = PayrollReviewRepository.maybeCreate();
      if (reviewRepository == null) throw StateError(SkoLanguageController.tr('給与明細を再取得できません。'));
      final workspace = await reviewRepository.loadWorkspace(
        widget.statement.periodStart,
      );
      PayrollStatementRecord? refreshed;
      for (final item in workspace.items) {
        if (item.statement.id == widget.statement.id) {
          refreshed = item.statement;
          break;
        }
      }
      if (refreshed == null) {
        if (mounted) {
          setState(() {
            _statementUnavailable = true;
            _pdfBytes.invalidate();
          });
        }
        throw StateError(SkoLanguageController.tr('この給与明細を閲覧できません。'));
      }
      if (mounted) {
        setState(() {
          _confirmation = status;
          _refreshedStatement = refreshed;
          _statementUnavailable = false;
          _confirmationError = null;
          _pdfBytes.invalidate();
        });
      }
    } catch (error) {
      if (error is PostgrestException &&
          (error.code == '42501' ||
              (error.code == 'P0001' &&
                  error.message == 'payroll review permission required'))) {
        // Re-read the self-scoped source before falling back after a role change.
        PayrollStatementRecord? ownStatement;
        String? reloadError;
        final selfRepository = PayrollStatementRepository.maybeCreate();
        if (selfRepository != null) {
          try {
            final ownStatements = await selfRepository.loadMyStatements();
            for (final item in ownStatements) {
              if (item.id == widget.statement.id) {
                ownStatement = item;
                break;
              }
            }
          } catch (error) {
            reloadError = SkoLanguageController.trParams('給与明細を再取得できませんでした: {error}', {'error': error});
          }
        }
        if (mounted) {
          setState(() {
            _confirmation = null;
            _confirmationError = reloadError;
            _refreshedStatement = ownStatement;
            _statementUnavailable = ownStatement == null;
            _pdfBytes.invalidate();
          });
        }
        return;
      }
      if (mounted) {
        setState(() => _confirmationError = SkoLanguageController.trParams('確認状態を読み込めませんでした: {error}', {'error': error}));
      }
    }
  }

  Future<void> _confirm(bool cancel) async {
    final repository = _confirmationRepository;
    final status = _confirmation;
    if (repository == null || status == null || _confirmationBusy) return;
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
    final original = _refreshedStatement ?? widget.statement;
    final status = _confirmation;
    if (status == null) return original;
    return PayrollStatementRecord(
      id: original.id,
      companyName: original.companyName.isEmpty
          ? widget.statement.companyName
          : original.companyName,
      workerName: original.workerName,
      periodStart: original.periodStart,
      periodEnd: original.periodEnd,
      grossPay: original.grossPay,
      deductions: original.deductions,
      netPay: original.netPay,
      // Only the statement-scoped workspace supplies stamps and their real times.
      detail: original.detail,
      issuedAt: original.issuedAt,
      reviewConfirmed: status.confirmed,
      reviewedAt: original.reviewedAt,
    );
  }

  final TransformationController _zoomController = TransformationController();

  @override
  void dispose() {
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
                    onPressed: _loadConfirmation,
                    icon: const Icon(Icons.refresh),
                  ),
                ],
              ),
            ),
          if (_confirmation != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Wrap(
                spacing: 12,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    SkoLanguageController.trParams('確認 {confirmed}/{required}名', {'confirmed': _confirmation!.confirmedCount, 'required': _confirmation!.requiredCount}),
                  ),
                  for (final reviewer in _confirmation!.reviewers)
                    Text(
                      SkoLanguageController.trParams('{name}：{status}', {'name': reviewer.name, 'status': SkoLanguageController.tr(reviewer.confirmed ? '確認済み' : '未確認')}),
                    ),
                  if (_confirmation!.confirmationOpenDate != null)
                    Text(
                      SkoLanguageController.trParams('確認開始：{date}', {'date': '${_confirmation!.confirmationOpenDate!.month}/${_confirmation!.confirmationOpenDate!.day}'}),
                    ),
                  if (_confirmation!.canConfirm)
                    FilledButton(
                      onPressed: _confirmationBusy
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
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Text(
              SkoLanguageController.isEnglish
                  ? 'Pinch to zoom. Drag to move while zoomed.'
                  : '2本指で拡大・縮小／拡大後はドラッグで移動',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          Expanded(
            child: _confirmationBusy
                ? const Center(child: CircularProgressIndicator())
                : _statementUnavailable
                ? Center(child: Text(SkoLanguageController.tr('この給与明細を閲覧できません。')))
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
