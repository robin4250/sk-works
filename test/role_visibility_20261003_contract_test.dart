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

  test('viewer footer hides attendance and sites but keeps chat', () {
    final app = File('lib/app_v2.dart').readAsStringSync();

    expect(app, contains("bool get _isViewer => _identity.role == 'viewer'"));
    expect(app, contains('if (!_isViewer) 1'));
    expect(app, contains('if (!_isViewer) 2'));
    expect(app, contains("label: SkoLanguageController.tr('チャット')"));
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
    expect(repo, contains("static String _subAdminKey(String key) => 'subadmin_home:$key'"));
    expect(repo, contains('loadSubAdminHomeStates'));
    expect(repo, contains('setSubAdminHomeEnabled'));
    expect(page, contains("'サブ管理者に表示する機能'"));
    expect(page, contains('CheckboxListTile'));
    expect(
      app,
      contains(
        'CompanyModuleSettingsRepository.subAdminHomeKeys.contains(item.key)',
      ),
    );
    expect(app, contains('_subAdminFeatureEnabled(item.key)'));
  });
}
