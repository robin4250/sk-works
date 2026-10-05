import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';

import '../notifications/notification_bell.dart';
import '../../international/language_controller.dart';
import 'payroll_pdf_service.dart';
import 'payroll_statement_repository.dart';

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
        _error = SkoLanguageController.isEnglish ? 'Payslips are unavailable.' : '給与明細を利用できません。';
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
                                SkoLanguageController.isEnglish ? 'No payslips have been issued yet.' : '給与明細はまだ発行されていません',
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
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 10),
                          itemBuilder: (context, index) {
                            final item = _items[index];
                            return Card(
                              child: InkWell(
                                borderRadius: BorderRadius.circular(20),
                                onTap: () => Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        PayrollStatementPreviewPage(
                                      statement: item,
                                    ),
                                  ),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.all(18),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        item.monthLabel,
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleLarge
                                            ?.copyWith(
                                              fontWeight: FontWeight.w900,
                                            ),
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
                                        item.reviewConfirmed ? (SkoLanguageController.isEnglish ? 'Confirmed' : '確認済み') : (SkoLanguageController.isEnglish ? 'Unconfirmed' : '未確定'),
                                        style: TextStyle(
                                          color: item.reviewConfirmed
                                              ? Colors.green
                                              : Theme.of(context)
                                                  .colorScheme
                                                  .error,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      const SizedBox(height: 12),
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              SkoLanguageController.isEnglish ? 'Net Pay' : '差引支給額',
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
                                                ?.copyWith(
                                                  fontWeight: FontWeight.w900,
                                                ),
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
  const PayrollStatementPreviewPage({
    super.key,
    required this.statement,
  });

  final PayrollStatementRecord statement;

  @override
  State<PayrollStatementPreviewPage> createState() =>
      _PayrollStatementPreviewPageState();
}

class _PayrollStatementPreviewPageState
    extends State<PayrollStatementPreviewPage> {
  final TransformationController _zoomController = TransformationController();

  @override
  void dispose() {
    _zoomController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final statement = widget.statement;
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
            child: InteractiveViewer(
              transformationController: _zoomController,
              minScale: 1,
              maxScale: 5,
              panEnabled: true,
              scaleEnabled: true,
              boundaryMargin: const EdgeInsets.all(120),
              clipBehavior: Clip.none,
              child: PdfPreview(
                initialPageFormat: PdfPageFormat.a4.landscape,
                canChangePageFormat: false,
                canChangeOrientation: false,
                allowPrinting: true,
                allowSharing: true,
                pdfFileName:
                    '${statement.monthLabel}_${statement.workerName}_給与明細.pdf',
                build: (_) => PayrollPdfService.buildPdf(statement),
              ),
            ),
          ),
        ],
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
