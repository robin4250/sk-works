import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('site detail and edit request support Japanese and English', () {
    final page =
        File('lib/features/sites/site_detail_page.dart').readAsStringSync();

    expect(page, contains("SkoLanguageController.isEnglish"));
    expect(page, contains("'Site Details'"));
    expect(page, contains("'Share with Subcontractors / Business Partners'"));
    expect(page, contains("'Business Partner'"));
    expect(page, contains("'Site Address'"));
    expect(page, contains("'Nearest Station'"));
    expect(page, contains("'Site Manager'"));
    expect(page, contains("'Site Photos'"));
    expect(page, contains("'Edit / Register'"));
    expect(page, contains("'Request Site Completion'"));
    expect(page, contains("'Edit / Register Site'"));
    expect(page, contains("'Review Changes'"));
    expect(page, contains('repository.sendSiteShare('));
    expect(page, contains('repository.submitInformationChange('));
    expect(page, contains('repository.uploadPhoto('));
  });
}
