import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/people/personnel_family_member.dart';

void main() {
  test('family member age is computed from birthday', () {
    final member = PersonnelFamilyMember(
      name: '子',
      relation: '子',
      birthDate: DateTime(2010, 10, 3),
      isDependent: true,
    );
    expect(member.ageOn(DateTime(2026, 10, 2)), 15);
    expect(member.ageOn(DateTime(2026, 10, 3)), 16);
  });

  test('family details stay in profile and out of employee detail/list print', () {
    final detail = File(
      'lib/features/people/employee_personnel_detail_page.dart',
    ).readAsStringSync();
    final profile =
        File('lib/features/profile/profile_page.dart').readAsStringSync();
    final printPage = File(
      'lib/features/people/employee_personnel_print_page.dart',
    ).readAsStringSync();

    expect(detail, isNot(contains("'家族・扶養情報'")));
    expect(detail, isNot(contains("'扶養対象'")));
    expect(profile, contains("'家族・扶養情報'"));
    expect(profile, contains("'配偶者・子供・扶養家族を追加'"));
    expect(printPage, isNot(contains("'家族・扶養情報'")));
    expect(printPage, isNot(contains("'扶養対象'")));
  });

  test('family details are part of personnel approval payload', () {
    final peopleRepo = File(
      'lib/features/people/people_cloud_repository.dart',
    ).readAsStringSync();
    final profile =
        File('lib/features/profile/profile_page.dart').readAsStringSync();
    final migration = File(
      'supabase/migrations/'
      '20261002013355_add_worker_family_social_insurance_details.sql',
    ).readAsStringSync();

    expect(peopleRepo, contains("'family_composition'"));
    expect(peopleRepo, contains("'family_members'"));
    expect(profile, contains("'family_members'"));
    expect(migration, contains('private.apply_worker_personnel_payload'));
    expect(migration, contains('public.worker_family_members'));
    expect(migration, contains('is_dependent'));
  });
}
