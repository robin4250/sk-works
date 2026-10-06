import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String read(String path) => File(path).readAsStringSync();

void main() {
  test('invoice loader falls back to snapshot customer and skips only malformed rows', () {
    final repository =
        read('lib/features/invoices/invoice_cloud_repository.dart');

    expect(repository, contains("snapshotMap['customer_name']"));
    expect(repository, contains("'取引先未設定'"));
    expect(repository, contains('try {'));
    expect(repository, contains('Keep other valid invoices visible'));
  });

  test('invoice page opens latest available month if current month is empty', () {
    final page = read('lib/features/invoices/invoice_cloud_page.dart');

    expect(page, contains('final hasCurrentPeriod = _invoices.any'));
    expect(page, contains('if (!hasCurrentPeriod && _invoices.isNotEmpty)'));
    expect(page, contains('months.sort'));
    expect(page, contains('_period = DateTime(months.first.year, months.first.month)'));
  });
}
