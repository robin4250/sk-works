import 'package:flutter/material.dart';

String payrollRateMonthText(DateTime month) =>
    '${month.year.toString().padLeft(4, '0')}-${month.month.toString().padLeft(2, '0')}';

Map<String, String> payrollRateStartingMonths(DateTime now) => {
  'insurance_month': payrollRateMonthText(now),
  'payroll_month': payrollRateMonthText(now),
  'payment_month': payrollRateMonthText(DateTime(now.year, now.month + 1)),
};

Future<String?> showPayrollRateMonthPicker(
  BuildContext context,
  String current,
) {
  final parsed = DateTime.tryParse('$current-01') ?? DateTime.now();
  var year = parsed.year;
  return showDialog<String>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: const Text('年月を選択'),
        content: SizedBox(
          width: 280,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      tooltip: '前年',
                      onPressed: year > 1 ? () => setState(() => year--) : null,
                      icon: const Icon(Icons.chevron_left),
                    ),
                    Flexible(child: Text('$year年')),
                    IconButton(
                      tooltip: '翌年',
                      onPressed: year < 9999
                          ? () => setState(() => year++)
                          : null,
                      icon: const Icon(Icons.chevron_right),
                    ),
                  ],
                ),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 4,
                  children: [
                    for (var month = 1; month <= 12; month++)
                      TextButton(
                        style: TextButton.styleFrom(
                          backgroundColor:
                              year == parsed.year && month == parsed.month
                              ? Theme.of(context).colorScheme.secondaryContainer
                              : null,
                        ),
                        onPressed: () => Navigator.pop(
                          context,
                          payrollRateMonthText(DateTime(year, month)),
                        ),
                        child: Text('$month月'),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('キャンセル'),
          ),
        ],
      ),
    ),
  );
}
