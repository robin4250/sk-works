import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('attendance cards are visible to viewer and general roles', () {
    final app = File('lib/app_v2.dart').readAsStringSync();
    final home =
        File('lib/features/home/friendly_home_content.dart').readAsStringSync();

    expect(app, contains("label: SkoLanguageController.tr('本日の勤怠報告')"));
    expect(app, contains("label: SkoLanguageController.tr('本日の出勤')"));
    expect(home, contains("SkoLanguageController.tr('本日の勤怠報告')"));
    expect(
      home,
      isNot(
        contains(
          "identity.isManagement &&\n          moduleEnabled('attendance')",
        ),
      ),
    );
    expect(app, isNot(contains("if (!_identity.can('can_manage_attendance'))")));
  });

  test('all roles retain personal attendance and sites footer while module and management guards remain', () {
    final app = File('lib/app_v2.dart').readAsStringSync();
    final compact = app.replaceAll(RegExp(r'\s+'), '');
    final footerStart = app.indexOf('final pageIndexes = <int>[');
    final footerEnd = app.indexOf('final selectedPosition', footerStart);
    expect(footerStart, greaterThanOrEqualTo(0));
    expect(footerEnd, greaterThan(footerStart));
    final footer = app.substring(footerStart, footerEnd).replaceAll(RegExp(r'\s+'), '').replaceAll(',]', ']');
    expect(footer, contains('finalpageIndexes=<int>[0,1,2,3,4];'));
    expect(footer, isNot(contains('_isViewer')));
    for (final label in ['出勤表', '現場', 'チャット']) {
      expect(footer, contains("label:SkoLanguageController.tr('$label')"));
    }
    expect(compact, contains("_moduleEnabled('attendance')?WorkerAttendanceSheetPage(isActive:_selectedIndex==1):_ModuleDisabledPage(label:SkoLanguageController.tr('出勤表'))"));
    expect(compact, contains("_moduleEnabled('sites')?constSiteCloudPage():_ModuleDisabledPage(label:SkoLanguageController.tr('現場'))"));
    expect(compact, contains("_identity.can('can_manage_attendance')?constAttendanceCloudPage():constWorkerAttendanceSheetPage()"));
    expect(compact, contains("if(_moduleEnabled('sites')&&_identity.can('can_view_admin_site_data'))"));
    expect(compact, contains('ChatCloudPage(viewerOnlyFriends:_isViewer'));
  });

  test('viewer chat is limited to registered direct friends', () {
    final chat =
        File('lib/features/chat/chat_cloud_page.dart').readAsStringSync();

    expect(chat, contains('this.viewerOnlyFriends = false'));
    expect(chat, contains('if (widget.viewerOnlyFriends)'));
    expect(chat, contains("workspace['friends']"));
    expect(chat, contains("group['group_type']?.toString() != 'direct'"));
    expect(chat, contains("friendIds.contains(otherUserId)"));
  });

  test('sub-admin classified features require administrator checkboxes', () {
    final app = File('lib/app_v2.dart').readAsStringSync();
    final repo = File(
      'lib/features/settings/company_module_settings_repository.dart',
    ).readAsStringSync();
    final page = File(
      'lib/features/settings/company_module_settings_page.dart',
    ).readAsStringSync();

    expect(repo, contains('subAdminHomeKeys'));
    expect(repo, contains(r"static String _subAdminKey(String key) => 'subadmin_home:$key'"));
    expect(repo, contains('loadSubAdminHomeStates'));
    expect(repo, contains('setSubAdminHomeEnabled'));
    expect(page, contains("'既存のサブ管理者共通表示設定（保管中）'"));
    expect(page, contains('CheckboxListTile'));
    expect(page, contains('onChanged: null'));
    expect(page, isNot(contains('repository.setSubAdminHomeEnabled')));
    expect(
      app,
      contains(
        'CompanyModuleSettingsRepository.subAdminHomeKeys.contains(item.key)',
      ),
    );
    expect(app, contains('_subAdminFeatureEnabled(item.key)'));
  });
}
