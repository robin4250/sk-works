// Pure Dart contract checks only; no Flutter, RPC or live state.
import 'dart:io';

import 'package:sk_works/features/qualifications/admin_saved_qualification_photo_contract.dart';
import 'package:sk_works/features/qualifications/admin_saved_qualification_photo_draft.dart';
import 'package:sk_works/features/qualifications/admin_saved_qualification_photo_prepare.dart';
import 'package:sk_works/features/qualifications/admin_saved_qualification_photo_prepare_readiness.dart';

const company = '00000000-0000-0000-0000-000000000001';
const actor = '00000000-0000-0000-0000-000000000002';
const target = '00000000-0000-0000-0000-000000000003';
const request = '00000000-0000-0000-0000-000000000004';
const other = '00000000-0000-0000-0000-000000000005';
Map<String, Object> valid() => {
  'version': 1,
  'contract': 'qualification_admin_photo_prepare_baseline',
  'company_id': company,
  'actor_id': actor,
  'baseline_guard_version': 1,
  'prepare_action': 'prepare_admin_saved_photos',
  'photo_submission_available': true,
  'photo_upload_allowed': false,
  'max_photos': 20,
  'self_approval_allowed': false,
};
final management = AdminSavedQualificationPhotoCapability.parse(
  {
    'version': 1,
    'contract': 'qualification_admin_saved_photos',
    'company_id': company,
    'actor_id': actor,
    'photo_submission_available': true,
    'photo_upload_allowed': false,
    'max_photos': 20,
    'self_approval_allowed': false,
  },
  companyId: company,
  actorId: actor,
);
AdminSavedQualificationPhotoPrepareReadiness parse(Object? raw) =>
    AdminSavedQualificationPhotoPrepareReadiness.parse(
      raw,
      companyId: company,
      actorId: actor,
    );
AdminSavedQualificationPhotoPrepare create(
  AdminSavedQualificationPhotoPrepareReadiness readiness,
) => AdminSavedQualificationPhotoPrepare.fromDraft(
  draft: AdminSavedQualificationPhotoDraft(
    companyId: company,
    actorId: actor,
    targetId: target,
    savedPaths: ['front.jpg'],
    selectedPaths: [],
  ),
  capability: management,
  readiness: readiness,
  requestId: request,
  scopeActive: true,
  currentCompanyId: company,
  currentActorId: actor,
  currentTargetId: target,
  currentSavedPaths: ['front.jpg'],
);
Map<String, dynamic> payload(
  AdminSavedQualificationPhotoPrepare command,
  AdminSavedQualificationPhotoPrepareReadiness readiness,
) => command.toPayload(
  currentCapability: management,
  currentReadiness: readiness,
  scopeActive: true,
  currentCompanyId: company,
  currentActorId: actor,
  currentTargetId: target,
  currentSavedPaths: ['front.jpg'],
);
void main() {
  var checks = 0;
  void check(bool condition, String label) {
    if (!condition) throw StateError(label);
    checks++;
  }

  void rejects(void Function() run) {
    try {
      run();
    } on StateError {
      checks++;
      return;
    }
    throw StateError('unready server must not yield a prepare command');
  }

  final ready = parse(valid());
  check(
    ready.available && ready.matchesScope(companyId: company, actorId: actor),
    'exact contract accepted',
  );
  check(!ready.matchesScope(companyId: other, actorId: actor), 'company scope');
  check(!ready.matchesScope(companyId: company, actorId: other), 'actor scope');
  check(
    !parse({...valid(), 'photo_submission_available': false}).available,
    'server permission OFF',
  );
  for (final invalid in <Object?>[
    null,
    {},
    [],
    {...valid()}..remove('baseline_guard_version'),
    {...valid(), 'version': 2},
    {...valid(), 'version': 1.0},
    {...valid(), 'contract': 'qualification_admin_saved_photos'},
    {...valid(), 'baseline_guard_version': 0},
    {...valid(), 'baseline_guard_version': 1.0},
    {...valid(), 'baseline_guard_version': true},
    {...valid(), 'prepare_action': 'delete'},
    {...valid(), 'company_id': other},
    {...valid(), 'actor_id': other},
    {...valid(), 'photo_submission_available': 1},
    {...valid(), 'photo_upload_allowed': true},
    {...valid(), 'self_approval_allowed': true},
    {...valid(), 'max_photos': 21},
    {...valid(), 'max_photos': 20.0},
    {...valid(), 'unknown': true},
    {
      'version': 1,
      'photo_submission_available': true,
      'photo_upload_allowed': false,
      'max_photos': 20,
    },
  ]) {
    check(
      !parse(invalid).available,
      'invalid or legacy response must remain OFF',
    );
  }
  check(
    !AdminSavedQualificationPhotoPrepareReadiness.parse(
      valid(),
      companyId: 'bad',
      actorId: actor,
    ).available,
    'invalid caller scope',
  );
  rejects(
    () => create(AdminSavedQualificationPhotoPrepareReadiness.unavailable),
  );
  final command = create(ready);
  check(
    (payload(command, ready)['photo_slots'] as List).isEmpty,
    'ready server allows all-photo exclusion payload',
  );
  rejects(
    () => payload(
      command,
      AdminSavedQualificationPhotoPrepareReadiness.unavailable,
    ),
  );
  rejects(() => payload(command, ready));
  stdout.writeln(
    'PASS $checks readiness parser/prepare checks: strict dedicated contract, legacy/unknown OFF, current scope, mandatory readiness, sticky invalidation',
  );
}
