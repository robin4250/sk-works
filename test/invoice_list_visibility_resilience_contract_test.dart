import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String read(String path) => File(path).readAsStringSync();

void main() {
  test('invoice loader falls back to snapshot customer and skips only malformed rows', () {
    final repository =
        read('lib/features/invoices/invoice_cloud_repository.dart');

    expect(repository, contains("snapshotMap['customer_name']"));
    expect(repository, contains("'取引先未設定'"));
    expect(repository, isNot(contains('customers(name)')));
    expect(repository, isNot(contains('sites(name)')));
    expect(repository, contains("snapshotMap['sites']"));
    expect(repository, contains('A related customer lookup must not hide the invoice'));
    expect(repository, contains('An unavailable detail relation should not hide the invoice'));
    expect(repository, contains('Keep other valid invoices visible'));
  });

  test('invoice page opens latest available month if current month is empty', () {
    final page = read('lib/features/invoices/invoice_cloud_page.dart');

    expect(page, contains('final hasCurrentPeriod = _invoices.any'));
    expect(page, contains('if (!hasCurrentPeriod && _invoices.isNotEmpty)'));
    expect(page, contains('..sort((a, b) => b.compareTo(a))'));
    expect(page, contains('_period = DateTime(months.first.year, months.first.month)'));
  });
}


  test('invoice loader prefers saved snapshot before normalized detail relations', () {
    final repository =
        read('lib/features/invoices/invoice_cloud_repository.dart');

    final snapshotIndex = repository.indexOf("final snapshotSites = snapshotMap['sites']");
    final normalizedIndex = repository.indexOf("from('invoice_site_calculations')");
    expect(snapshotIndex, greaterThanOrEqualTo(0));
    expect(normalizedIndex, greaterThan(snapshotIndex));
    expect(repository, contains("manualAdjustmentYen:\n                    _toInt(siteMap['manual_adjustment'])"));
    expect(repository, contains("welfareRateBps: _toInt(siteMap['welfare_rate_bps'])"));
  });
