import 'package:flutter/material.dart';

import '../../domain/invoice_engine.dart';

class InvoicePage extends StatefulWidget {
  const InvoicePage({super.key});

  @override
  State<InvoicePage> createState() => _InvoicePageState();
}

class _InvoicePageState extends State<InvoicePage> {
  final _invoices = <InvoiceCalculationResult>[];

  @override
  void initState() {
    super.initState();
    _invoices.add(_sampleInvoice());
  }

  InvoiceCalculationResult _sampleInvoice() {
    return InvoiceEngine.calculate(
      customerId: '株式会社ABC',
      billingPeriod: '2026年9月',
      detailMode: InvoiceDetailMode.siteBreakdownOnInvoice,
      sites: const [
        SiteInvoiceCalculation(
          siteId: 'sumida-renovation',
          siteName: '墨田区〇〇改修工事',
          lines: [
            InvoiceLine(label: '作業人工', quantity: 20, unitPriceYen: 25000),
            InvoiceLine(label: '残業', quantity: 12, unitPriceYen: 4000),
          ],
          manualAdjustmentYen: 20000,
        ),
        SiteInvoiceCalculation(
          siteId: 'koto-newbuild',
          siteName: '江東区△△新築工事',
          lines: [
            InvoiceLine(label: '作業人工', quantity: 15, unitPriceYen: 25000),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('請求管理')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addInvoice,
        icon: const Icon(Icons.add),
        label: const Text('請求作成'),
      ),
      body: SafeArea(
        child: ListView.separated(
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
                          const CircleAvatar(child: Icon(Icons.receipt_long_outlined)),
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
    if (result == null) return;
    setState(() => _invoices.insert(0, result));
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

class InvoiceFormPage extends StatefulWidget {
  const InvoiceFormPage({super.key});

  @override
  State<InvoiceFormPage> createState() => _InvoiceFormPageState();
}

class _InvoiceFormPageState extends State<InvoiceFormPage> {
  final _formKey = GlobalKey<FormState>();
  final _customer = TextEditingController();
  final _period = TextEditingController();
  final _site = TextEditingController();
  final _label = TextEditingController(text: '作業人工');
  final _quantity = TextEditingController(text: '1');
  final _unitPrice = TextEditingController(text: '25000');
  final _adjustment = TextEditingController(text: '0');
  final _welfarePercent = TextEditingController(text: '0');
  InvoiceDetailMode _detailMode = InvoiceDetailMode.siteBreakdownOnInvoice;

  @override
  void dispose() {
    for (final controller in [
      _customer,
      _period,
      _site,
      _label,
      _quantity,
      _unitPrice,
      _adjustment,
      _welfarePercent,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('請求 - 新規作成')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _requiredText(_customer, '請求先'),
              const SizedBox(height: 14),
              _requiredText(_period, '対象期間'),
              const SizedBox(height: 14),
              DropdownButtonFormField<InvoiceDetailMode>(
                initialValue: _detailMode,
                decoration: const InputDecoration(labelText: '明細方式'),
                items: const [
                  DropdownMenuItem(
                    value: InvoiceDetailMode.consolidatedOnly,
                    child: Text('合算のみ'),
                  ),
                  DropdownMenuItem(
                    value: InvoiceDetailMode.siteBreakdownOnInvoice,
                    child: Text('請求書に現場別内訳'),
                  ),
                  DropdownMenuItem(
                    value: InvoiceDetailMode.siteDetailAttachment,
                    child: Text('現場別明細を別紙添付'),
                  ),
                ],
                onChanged: (value) => setState(() => _detailMode = value ?? _detailMode),
              ),
              const SizedBox(height: 20),
              Text('現場計算', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              _requiredText(_site, '現場名'),
              const SizedBox(height: 14),
              _requiredText(_label, '明細名'),
              const SizedBox(height: 14),
              _decimalField(_quantity, '数量 / 人工'),
              const SizedBox(height: 14),
              _integerField(_unitPrice, '単価（円）', allowNegative: false),
              const SizedBox(height: 14),
              _integerField(_adjustment, '手動調整（円）', allowNegative: true),
              const SizedBox(height: 14),
              _decimalField(_welfarePercent, '法定福利費相当（%）'),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: _submit,
                icon: const Icon(Icons.calculate_outlined),
                label: const Text('計算して作成'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  TextFormField _requiredText(TextEditingController controller, String label) {
    return TextFormField(
      controller: controller,
      decoration: InputDecoration(labelText: label),
      validator: (value) => value == null || value.trim().isEmpty ? '$labelを入力してください' : null,
    );
  }

  TextFormField _decimalField(TextEditingController controller, String label) {
    return TextFormField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(labelText: label),
      validator: (value) {
        final number = double.tryParse(value ?? '');
        if (number == null || number < 0) return '0以上の数値を入力してください';
        return null;
      },
    );
  }

  TextFormField _integerField(
    TextEditingController controller,
    String label, {
    required bool allowNegative,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: TextInputType.number,
      decoration: InputDecoration(labelText: label),
      validator: (value) {
        final number = int.tryParse(value ?? '');
        if (number == null) return '整数を入力してください';
        if (!allowNegative && number < 0) return '0以上の数値を入力してください';
        return null;
      },
    );
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final welfarePercent = double.parse(_welfarePercent.text);
    final result = InvoiceEngine.calculate(
      customerId: _customer.text.trim(),
      billingPeriod: _period.text.trim(),
      detailMode: _detailMode,
      sites: [
        SiteInvoiceCalculation(
          siteId: DateTime.now().microsecondsSinceEpoch.toString(),
          siteName: _site.text.trim(),
          lines: [
            InvoiceLine(
              label: _label.text.trim(),
              quantity: double.parse(_quantity.text),
              unitPriceYen: int.parse(_unitPrice.text),
            ),
          ],
          manualAdjustmentYen: int.parse(_adjustment.text),
          welfareRateBps: (welfarePercent * 100).round(),
        ),
      ],
    );
    Navigator.of(context).pop(result);
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
