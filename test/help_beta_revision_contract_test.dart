import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/help/manual_content.dart';
import 'package:sk_works/features/help/menu_help_catalog.dart';

void main() {
  test('beta help retains role filtering and explains authoritative data sources', () {
    final admin = MenuHelpCatalog.visibleFor(role: ManualRole.admin);
    String details(String key) => admin.singleWhere((item) => item.key == key).details;
    expect(details('company_documents'), contains('個別の給与単価は個別給与設定'));
    expect(admin.where((item) => item.key == 'company_modules'), isEmpty);
    expect(details('payroll'), contains('同一PDF'));
    expect(details('payroll'), contains('実際の確認日時'));
    expect(details('payroll'), contains('夜間割増'));
    expect(details('people'), contains('社員番号'));
    expect(MenuHelpCatalog.visibleFor(
      role: ManualRole.general, visibleKeys: {'company_modules'},
    ), isEmpty);
    for (final file in ['help_page.dart', 'floating_help_overlay.dart']) {
      final source = File('lib/features/help/$file').readAsStringSync();
      expect(source, contains('ManualVersion.revisionLabel'));
      expect(source, contains('SkoLanguageController.watch(context)'));
    }
  });
}
