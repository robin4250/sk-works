import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/people/phone_display.dart';

void main() {
  test('employee list and detail use domestic phone display', () {
    expect(domesticPhoneDisplay('+819012345678'), '09012345678');

    final list =
        File('lib/features/people/people_cloud_page.dart').readAsStringSync();
    final detail = File(
      'lib/features/people/employee_personnel_detail_page.dart',
    ).readAsStringSync();

    expect(list, contains('domesticPhoneDisplay(record.phone)'));
    expect(list, contains("Uri(scheme: 'tel'"));
    expect(detail, contains('domesticPhoneDisplay(record.phone)'));
    expect(detail, contains('domesticPhoneDisplay(record.emergencyPhone)'));
    expect(detail, contains("Uri(scheme: 'tel'"));
  });

  test('employee and emergency addresses open Google Maps', () {
    final detail = File(
      'lib/features/people/employee_personnel_detail_page.dart',
    ).readAsStringSync();
    final profile =
        File('lib/features/profile/profile_page.dart').readAsStringSync();

    expect(detail, contains("'www.google.com'"));
    expect(detail, contains("'/maps/search/'"));
    expect(detail, contains("'query': query"));
    expect(detail, contains('record.address'));
    expect(detail, contains('record.emergencyAddress'));
    expect(profile, contains("'Googleマップで開く'"));
    expect(profile, contains("'www.google.com'"));
  });
}
