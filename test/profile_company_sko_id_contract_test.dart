import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('profile exposes company SKO ID and editable personal SKO ID', () {
    final page = File('lib/features/profile/profile_page.dart').readAsStringSync();
    final repository =
        File('lib/features/profile/profile_repository.dart').readAsStringSync();

    expect(page, contains("SkoLanguageController.tr('SKO会社ID')"));
    expect(page, contains('SelectableText(data!.companyId)'));
    expect(repository, contains('required this.companyId'));
    expect(repository, contains("memberships.first['company_id']"));

    expect(page, contains('個人SKO ID'));
    expect(page, contains('_personalSkoId'));
    expect(page, contains('_changePersonalSkoId'));
    expect(repository, contains('personalSkoId'));
    expect(repository, contains("'change_personal_sko_id'"));
    expect(repository, contains('domesticJapanesePhoneValue'));
    expect(repository, contains("startsWith('+81')"));
    expect(page, contains('ProfileRepository.domesticJapanesePhoneValue(data.phone)'));
  });
}
