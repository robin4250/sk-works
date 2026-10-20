// Pure Dart only. No Flutter startup, RPC, upload, Storage or user data.
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
const baseline = ['front.jpg', 'back.jpg'];
var checks = 0;
void check(bool value, String label) {
  if (!value) throw StateError(label);
  checks++;
}

void rejects(void Function() run, String label) {
  try {
    run();
  } on StateError {
    checks++;
    return;
  }
  throw StateError('Expected refusal: $label');
}

void immutable(void Function() run, String label) {
  try {
    run();
  } on UnsupportedError {
    checks++;
    return;
  }
  throw StateError('Expected immutable values: $label');
}

AdminSavedQualificationPhotoCapability capability({bool available = true}) =>
    AdminSavedQualificationPhotoCapability.parse(
      {
        'version': 1,
        'contract': 'qualification_admin_saved_photos',
        'company_id': company,
        'actor_id': actor,
        'photo_submission_available': available,
        'photo_upload_allowed': false,
        'max_photos': 20,
        'self_approval_allowed': false,
      },
      companyId: company,
      actorId: actor,
    );

AdminSavedQualificationPhotoPrepareReadiness readiness() =>
    AdminSavedQualificationPhotoPrepareReadiness.parse(
      {
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
      },
      companyId: company,
      actorId: actor,
    );

AdminSavedQualificationPhotoPrepare command({
  List<String> saved = baseline,
  List<String> selected = const ['back.jpg'],
  String companyId = company,
  String actorId = actor,
  String targetId = target,
  String requestId = request,
}) => AdminSavedQualificationPhotoPrepare.fromDraft(
  draft: AdminSavedQualificationPhotoDraft(
    companyId: companyId,
    actorId: actorId,
    targetId: targetId,
    savedPaths: saved,
    selectedPaths: selected,
  ),
  capability: capability(),
  readiness: readiness(),
  requestId: requestId,
  scopeActive: true,
  currentCompanyId: company,
  currentActorId: actor,
  currentTargetId: target,
  currentSavedPaths: saved,
);
Map<String, dynamic> payload(
  AdminSavedQualificationPhotoPrepare command, {
  String? companyId = company,
  String? actorId = actor,
  String? targetId = target,
  List<String> saved = baseline,
  bool active = true,
  AdminSavedQualificationPhotoCapability? currentCapability,
}) => command.toPayload(
  currentCapability: currentCapability ?? capability(),
  currentReadiness: readiness(),
  scopeActive: active,
  currentCompanyId: companyId,
  currentActorId: actorId,
  currentTargetId: targetId,
  currentSavedPaths: saved,
);

void main() {
  final prepared = command(selected: ['back.jpg', 'front.jpg']);
  final value = payload(prepared);
  check(
    value.keys.join(',') ==
        'company_id,target_id,request_id,expected_photo_paths,photo_slots',
    'exact prepare keys',
  );
  check(
    value['company_id'] == company &&
        value['target_id'] == target &&
        value['request_id'] == request,
    'exact IDs',
  );
  check(
    (value['expected_photo_paths'] as List).join(',') == 'front.jpg,back.jpg',
    'baseline preserves displayed order',
  );
  check(
    (value['photo_slots'] as List)
            .map((entry) => entry['existing_path'])
            .join(',') ==
        'back.jpg,front.jpg',
    'selection preserves chosen order',
  );
  check(
    (payload(command(selected: []))['photo_slots'] as List).isEmpty,
    'empty selection means all photos removed',
  );
  check(
    !value.containsKey('actor_id') &&
        !value.containsKey('delete') &&
        !value.containsKey('upload'),
    'no actor claim/delete/upload command',
  );
  immutable(() => value['target_id'] = other, 'payload map');
  immutable(
    () => (value['expected_photo_paths'] as List).add('new.jpg'),
    'baseline list',
  );
  immutable(() => (value['photo_slots'] as List).clear(), 'slots list');
  immutable(
    () => ((value['photo_slots'] as List).first as Map)['existing_path'] =
        'new.jpg',
    'slot map',
  );
  final incomingSaved = ['front.jpg', 'back.jpg'];
  final incomingSelected = ['front.jpg'];
  final frozen = command(saved: incomingSaved, selected: incomingSelected);
  incomingSaved.clear();
  incomingSelected.clear();
  check(
    frozen.savedPaths.length == 2 && frozen.selectedPaths.length == 1,
    'source list mutation does not alter snapshot',
  );
  for (final run in <void Function()>[
    () => command(companyId: other),
    () => command(actorId: other),
    () => command(targetId: other),
    () => command(requestId: 'bad'),
    () => command(saved: []),
    () => command(saved: ['front.jpg', 'front.jpg']),
    () => command(saved: [' ']),
    () => command(saved: List.generate(21, (i) => '$i.jpg')),
    () => command(selected: ['front.jpg', 'front.jpg']),
    () => command(selected: ['new.jpg']),
  ]) {
    rejects(run, 'invalid draft');
  }
  for (final run in <void Function()>[
    () => payload(command(), companyId: other),
    () => payload(command(), actorId: other),
    () => payload(command(), targetId: other),
    () => payload(command(), saved: ['back.jpg', 'front.jpg']),
    () => payload(command(), saved: ['front.jpg', 'back.jpg', 'new.jpg']),
    () => payload(command(), currentCapability: capability(available: false)),
    () => payload(command(), active: false),
  ]) {
    rejects(run, 'changed current scope/baseline');
  }
  final revoked = command();
  rejects(() => payload(revoked, actorId: other), 'scope changed');
  rejects(() => payload(revoked), 'scope ABA remains revoked');
  final stable = command();
  check(
    payload(stable)['request_id'] == payload(stable)['request_id'],
    'same request ID retained for transport retry',
  );
  stdout.writeln(
    'PASS $checks saved-photo prepare checks: exact ordered payload, immutable snapshot, all-photo exclusion, scope/baseline mismatch, sticky revocation, stable request ID',
  );
}
