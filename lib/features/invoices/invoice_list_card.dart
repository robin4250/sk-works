import 'package:flutter/material.dart';

import '../../domain/invoice_engine.dart';
import '../../international/language_controller.dart';

/// Displays saved amounts only when signed sources and quantity status are ready.
class InvoiceListCard extends StatelessWidget {
  const InvoiceListCard({
    super.key,
    required this.invoice,
    required this.periodLabel,
    required this.onTap,
  });

  final InvoiceCalculationResult invoice;
  final String periodLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final english = SkoLanguageController.isEnglish;
    final pending = invoice.amountPending;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              const CircleAvatar(child: Icon(Icons.receipt_long_outlined)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      invoice.customerId,
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(periodLabel),
                    const SizedBox(height: 5),
                    Text(
                      pending
                          ? (invoice.routeSourcePending
                              ? (english ? 'Checkout report or billing settings pending' : '退勤日報・請求設定の確認待ち')
                              : (english ? 'Quantity approval pending' : '請求数量の承認待ち'))
                          : (english
                                ? '${invoice.siteCalculations.length} sites'
                                : '${invoice.siteCalculations.length}現場'),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                pending
                    ? (english ? 'Pending' : '未確定')
                    : invoiceAmountLabel(invoice.grandTotalYen),
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}

String invoiceAmountLabel(int value) {
  final negative = value < 0;
  final digits = value.abs().toString();
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
    buffer.write(digits[i]);
  }
  return '${negative ? '-' : ''}¥$buffer';
}
