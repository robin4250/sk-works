import 'package:flutter/material.dart';

import '../../domain/invoice_engine.dart';
import 'invoice_cloud_repository.dart';
import 'invoice_page.dart';

class InvoiceCloudPage extends StatefulWidget {
  const InvoiceCloudPage({super.key});

  @override
  State<InvoiceCloudPage> createState() => _InvoiceCloudPageState();
}

class _InvoiceCloudPageState extends State<InvoiceCloudPage> {
  final _repository = InvoiceCloudRepository.maybeCreate();
  final _invoices = <InvoiceCalculationResult>[];
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
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Supabase接続が利用できません。';
      });
      return;
    }
    try {
      final rows = await repository.loadAll();
      if (!mounted) return;
      setState(() {
        _invoices
          ..clear()
          ..addAll(rows);
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
        title: const Text('請求管理'),
        actions: [
          IconButton(
            tooltip: '再読み込み',
            onPressed: _loading
                ? null
                : () {
                    setState(() => _loading = true);
                    _load();
                  },
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _loading ? null : _addInvoice,
        icon: const Icon(Icons.add),
        label: const Text('請求作成'),
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? _ErrorState(message: _error!, onRetry: _load)
                : _invoices.isEmpty
                    ? const Center(child: Text('請求データはまだありません'))
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                        itemCount: _invoices.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final invoice = _invoices[index];
                          return Card(
                            child: InkWell(
                              borderRadius: BorderRadius.circular(12),
                              onTap: () => _showInvoice(invoice),
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        const CircleAvatar(
                                          child: Icon(Icons.receipt_long_outlined),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                invoice.customerId,
                                                style: const TextStyle(fontWeight: FontWeight.w700),
                                              ),
                                              Text(invoice.billingPeriod),
                                            ],
                                          ),
                                        ),
                                        const Icon(Icons.chevron_right),
                                      ],
                                    ),
                                    const SizedBox(height: 14),
                                    Text(
                                      _yen(invoice.grandTotalYen),
                                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                                            fontWeight: FontWeight.w900,
                                          ),
                                    ),
                                    Text(
                                      '${invoice.siteCalculations.length}現場 / 小計 ${_yen(invoice.subtotalYen)} / 消費税 ${_yen(invoice.taxYen)}',
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
      ),
    );
  }

  Future<void> _addInvoice() async {
    final result = await Navigator.of(context).push<InvoiceCalculationResult>(
      MaterialPageRoute(builder: (_) => const InvoiceFormPage()),
    );
    final repository = _repository;
    if (result == null || repository == null) return;
    try {
      await repository.insert(result);
      if (!mounted) return;
      setState(() => _invoices.insert(0, result));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('請求をクラウドに保存しました')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('保存できませんでした: $error')),
      );
    }
  }

  void _showInvoice(InvoiceCalculationResult invoice) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: FractionallySizedBox(
          heightFactor: 0.88,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            children: [
              Text(
                invoice.customerId,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
              Text('対象期間: ${invoice.billingPeriod}'),
              Text('明細方式: ${_detailModeLabel(invoice.detailMode)}'),
              const SizedBox(height: 18),
              for (final site in invoice.siteCalculations) ...[
                Text(site.siteName, style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                for (final line in site.lines)
                  Row(
                    children: [
                      Expanded(child: Text(line.label)),
                      Text('${line.quantity} × ${_yen(line.unitPriceYen)}'),
                      const SizedBox(width: 12),
                      Text(_yen(line.amountYen)),
                    ],
                  ),
                if (site.manualAdjustmentYen != 0)
                  Row(
                    children: [
                      const Expanded(child: Text('手動調整')),
                      Text(_yen(site.manualAdjustmentYen)),
                    ],
                  ),
                if (site.welfareAmountYen != 0)
                  Row(
                    children: [
                      const Expanded(child: Text('法定福利費相当')),
                      Text(_yen(site.welfareAmountYen)),
                    ],
                  ),
                Align(
                  alignment: Alignment.centerRight,
                  child: Text('現場小計 ${_yen(site.subtotalYen)}'),
                ),
                const Divider(height: 24),
              ],
              Row(
                children: [
                  const Expanded(child: Text('小計')),
                  Text(_yen(invoice.subtotalYen)),
                ],
              ),
              Row(
                children: [
                  const Expanded(child: Text('消費税')),
                  Text(_yen(invoice.taxYen)),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Text('請求合計', style: Theme.of(context).textTheme.titleLarge),
                  const Spacer(),
                  Text(
                    _yen(invoice.grandTotalYen),
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _detailModeLabel(InvoiceDetailMode mode) => switch (mode) {
        InvoiceDetailMode.consolidatedOnly => '合算のみ',
        InvoiceDetailMode.siteBreakdownOnInvoice => '請求書に現場別内訳',
        InvoiceDetailMode.siteDetailAttachment => '現場別明細を別紙添付',
      };
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

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
            const Icon(Icons.cloud_off_outlined, size: 42),
            const SizedBox(height: 12),
            const Text('クラウド請求を読み込めませんでした'),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('再試行'),
            ),
          ],
        ),
      ),
    );
  }
}

String _yen(int value) {
  final negative = value < 0;
  final digits = value.abs().toString();
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
    buffer.write(digits[i]);
  }
  return '${negative ? '-' : ''}¥$buffer';
}
