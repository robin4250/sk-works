import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/common/data_date_labels.dart';
import 'package:sk_works/features/help/manual_content.dart';
import 'package:sk_works/features/help/menu_help_catalog.dart';

void main() {
  test('help catalog covers restored menu functions', () {
    final keys = MenuHelpCatalog.items.map((item) => item.key).toSet();
    expect(keys, contains('attendance'));
    expect(keys, contains('chat'));
    expect(keys, contains('people'));
    expect(keys, contains('payroll'));
    expect(keys, contains('payroll_settings'));
    expect(keys, contains('payroll_adjustments'));
    expect(keys, contains('company_deliveries'));
    expect(keys, contains('company_documents'));
    expect(keys, contains('help'));
  });

  test('help filters by visible keys and role', () {
    final items = MenuHelpCatalog.visibleFor(
      role: ManualRole.general,
      visibleKeys: const {'attendance', 'help'},
    );
    expect(items.map((item) => item.key).toSet(), {'attendance', 'help'});
  });

  test('unchanged update date is hidden', () {
    final labels = DataDateLabels.labels(
      createdAt: '2026-10-01T12:00:00Z',
      updatedAt: '2026-10-01T12:00:00Z',
    );
    expect(labels.length, 1);
    expect(labels.first, startsWith('登録日:'));
  });

  test('data pages use shared date labels', () {
    final companyRepo = File(
      'lib/features/people/company_submitted_document_repository.dart',
    ).readAsStringSync();
    expect(companyRepo, contains('created_at, updated_at'));

    for (final path in [
      'lib/features/people/people_cloud_page.dart',
      'lib/features/qualifications/qualification_cloud_page.dart',
      'lib/features/people/worker_document_page.dart',
      'lib/features/people/company_submitted_documents_page.dart',
    ]) {
      expect(File(path).readAsStringSync(), contains('DataDateLabels.labels'));
    }
  });

  test('backup restore contract keeps recovery baseline', () {
    final doc =
        File('docs/BACKUP_RESTORE_CONTRACT_20261002.md').readAsStringSync();
    expect(doc, contains('backup/pre-restore-20261002-0532'));
    expect(doc, contains('b230b4b578c02642fd3911472a13288eabdbccde'));
    expect(doc, contains('forward-only migrations'));
    expect(doc, contains('tool/pre_device_release_gate.sh'));
    expect(doc, contains('Release build'));
  });
}
