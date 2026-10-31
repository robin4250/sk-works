import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/qualifications/admin_saved_qualification_photo_contract.dart';

const company = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
const actor = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';
Map<String, Object?> validCapability() => {
  'version': 2,
    'expected_photo_paths_required': true,
  'contract': 'qualification_admin_saved_photos',
  'company_id': company,
  'actor_id': actor,
  'photo_submission_available': true,
  'photo_upload_allowed': false,
  'max_photos': 20,
  'self_approval_allowed': false,
};
AdminSavedQualificationPhotoCapability parse(
  Object? raw, {
  String companyId = company,
  String actorId = actor,
}) => AdminSavedQualificationPhotoCapability.parse(
  raw,
  companyId: companyId,
  actorId: actorId,
);

void main() {
  test(
    'accepts exact management contract only for bound actor and company',
    () {
      final cap = parse(validCapability());
      expect(cap.available, true);
      expect(cap.maxPhotos, 20);
      expect(cap.matchesScope(companyId: company, actorId: actor), true);
      expect(cap.matchesScope(companyId: actor, actorId: actor), false);
      expect(cap.matchesScope(companyId: company, actorId: company), false);
      expect(cap.matchesScope(companyId: null, actorId: actor), false);
      final denied = parse({
        ...validCapability(),
        'photo_submission_available': false,
      });
      expect(denied.available, false);
      expect(denied.matchesScope(companyId: company, actorId: actor), false);
    },
  );
  test(
    'rejects every missing key, extra key, personal response and nonobject',
    () {
      for (final key in validCapability().keys) {
        expect(
          parse(validCapability()..remove(key)).available,
          false,
          reason: key,
        );
      }
      for (final raw in [
        null,
        [],
        'capability',
        {...validCapability(), 'extra': false},
        {
          'version': 2,
    'expected_photo_paths_required': true,
          'photo_submission_available': true,
          'photo_upload_allowed': false,
          'max_photos': 20,
        },
      ]) {
        expect(parse(raw).available, false);
      }
    },
  );
  test('rejects wrong types, expansion of scope and unsupported versions', () {
    final mutations = <String, List<Object?>>{
      'version': [null, 0, 1, 3, 2.0, '2', true],
      'expected_photo_paths_required': [null, false, 'true', 1],
      'contract': [
        null,
        'photo_capability',
        'qualification_admin_saved_photos ',
      ],
      'company_id': [null, actor, ' $company'],
      'actor_id': [null, company, actor.toUpperCase()],
      'photo_submission_available': [null, 'true', 1],
      'photo_upload_allowed': [null, true, 'false', 0],
      'max_photos': [null, 0, 1, 19, 21, 20.0, '20'],
      'self_approval_allowed': [null, true, 'false', 0],
    };
    for (final entry in mutations.entries) {
      for (final value in entry.value) {
        expect(
          parse({...validCapability(), entry.key: value}).available,
          false,
          reason: '${entry.key}=$value',
        );
      }
    }
    for (final id in ['', 'bad', '$company\n', company.toUpperCase()]) {
      expect(
        parse({
          ...validCapability(),
          'company_id': id,
        }, companyId: id).available,
        false,
      );
      expect(
        parse({...validCapability(), 'actor_id': id}, actorId: id).available,
        false,
      );
    }
  });
}
