import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('disabled company modules are blocked across all primary routes', () {
    final app = File('lib/app_v2.dart').readAsStringSync();
    final home =
        File('lib/features/home/friendly_home_content.dart').readAsStringSync();

    expect(app, contains("'clock_in' || 'clock_out'"));
    expect(app, contains("_ModuleDisabledPage(label: SkoLanguageController.tr('出勤表'))"));
    expect(app, contains("SkoLanguageController.tr('現場')"));
    expect(app, contains("SkoLanguageController.tr('チャット')"));
    expect(app, contains('この機能は会社設定でOFFになっています'));
    expect(app, contains("_moduleEnabled('invoices')"));
    expect(app, contains("_moduleEnabled('vehicle_routes')"));
    expect(home, contains("moduleEnabled('attendance')"));
    expect(home, contains("moduleEnabled('vehicle_routes')"));
  });

  test('company switches cover alternate routes without replacing permissions', () {
    final app = File('lib/app_v2.dart').readAsStringSync();
    final start = app.indexOf('final requiredModule = switch (key)');
    final end = app.indexOf('if (requiredModule != null', start);
    final routes = app.substring(start, end);
    for (final key in [
      'attendance_today', 'attendance_management',
      'attendance_method_vehicle', 'workplace_select',
      'admin_sites', 'qualification_register',
      'employee_qualifications', 'document_register',
    ]) {
      expect(routes, contains("'$key'"), reason: '$key must honor its company switch');
    }
    final normalized = app.replaceAll(RegExp(r'\s+'), ' ');
    expect(normalized, contains("if (_moduleEnabled('sites') && _identity.can('can_view_admin_site_data'))"));
    expect(normalized, contains("if (key == 'settings' || key == 'company_documents' || key == 'company_modules')"));
    expect(normalized, isNot(contains("key: 'company_modules'")));
    expect(normalized, contains("if (key == 'company_modules')"));
    expect(normalized, isNot(contains('page = const CompanyModuleSettingsPage();')));
    final settings = File('lib/features/settings/settings_page.dart').readAsStringSync();
    final masterSection = settings.substring(settings.indexOf('if (_isMasterAdmin) ...['));
    expect(masterSection, contains('child: CompanyModuleSettingsPage()'));
    expect(masterSection, contains('MasterProtectedPage('));
    final repository = File('lib/features/settings/company_module_settings_repository.dart').readAsStringSync();
    expect(repository, isNot(contains('.delete(')));
    expect(repository, contains("membership.role != 'owner' && membership.role != 'admin'"));
  });
}
