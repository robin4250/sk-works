import 'dart:async';

import '../lib/features/qualifications/qualification_photo_session_rpc.dart';
import '../lib/features/qualifications/admin_saved_qualification_photo_draft.dart';
import '../lib/features/qualifications/admin_saved_qualification_photo_prepare.dart';
import '../lib/features/qualifications/admin_saved_qualification_photo_submission_repository.dart';

const actor = '00000000-0000-0000-0000-000000000001';
const company = '00000000-0000-0000-0000-000000000002';
const target = '00000000-0000-0000-0000-000000000003';
const request = '00000000-0000-0000-0000-000000000004';
const other = '00000000-0000-0000-0000-000000000005';
int checks = 0;
void check(bool value, String label) {
  if (!value) throw StateError('FAIL $label');
  checks++;
}

Future<void> rejects(Future<Object?> Function() operation, String label) async {
  var rejected = false;
  try {
    await operation();
  } catch (_) {
    rejected = true;
  }
  check(rejected, label);
}

QualificationPhotoRpcSession session({
  String? a = actor,
  String? c = company,
  String? t = target,
  String? token = 'fixture-token',
  bool active = true,
}) => QualificationPhotoRpcSession(
  actorId: a,
  companyId: c,
  targetId: t,
  accessToken: token,
  active: active,
);
Map<String, dynamic> prepare() => {
  'company_id': company,
  'target_id': target,
  'request_id': request,
  'expected_photo_paths': ['saved.jpg'],
  'photo_slots': <Object>[],
};

class Fixture {
  Fixture({bool enabled = true}) {
    guard = QualificationPhotoSessionRpc(
      current: () => current,
      transport: transport,
      enabled: enabled,
    );
  }
  QualificationPhotoRpcSession current = session();
  late final QualificationPhotoSessionRpc guard;
  final calls = <(String, Map<String, dynamic>)>[];
  Completer<Object?>? readinessGate, resultGate;
  String receiptTarget = target, receiptActor = actor;
  bool ready = true;
  String status = 'draft';
  Object? fail;
  Map<String, dynamic> capability() => {
    'version': 1,
    'contract': 'qualification_admin_saved_photos',
    'company_id': company,
    'actor_id': actor,
    'photo_submission_available': true,
    'photo_upload_allowed': false,
    'max_photos': 20,
    'self_approval_allowed': false,
  };
  Map<String, dynamic> readiness() => {
    'version': 1,
    'contract': 'qualification_admin_photo_prepare_baseline',
    'company_id': company,
    'actor_id': actor,
    'baseline_guard_version': 1,
    'prepare_action': 'prepare_admin_saved_photos',
    'photo_submission_available': ready,
    'photo_upload_allowed': false,
    'max_photos': 20,
    'self_approval_allowed': false,
  };
  Map<String, dynamic> receipt() => {
    'version': 1,
    'id': request,
    'target_id': receiptTarget,
    'requested_by': receiptActor,
    'status': status,
    'cancelled': status == 'rejected',
    'reason': status == 'rejected' ? 'cancelled' : null,
    'photo_paths': <String>[],
    'upload_paths': <String>[],
  };
  Future<Object?> transport(
    String function,
    Map<String, dynamic> params,
    Map<String, String> headers,
  ) async {
    check(
      function == 'personal_qualification_submission',
      'single existing RPC',
    );
    check(
      headers.length == 1 && headers['Authorization'] == 'Bearer fixture-token',
      'explicit captured bearer',
    );
    final action = params['p_action'] as String;
    final data = Map<String, dynamic>.from(params['p_data'] as Map);
    calls.add((action, data));
    if (action == 'admin_saved_photo_capability') return capability();
    if (action == 'admin_saved_photo_prepare_readiness') {
      return readinessGate == null ? readiness() : await readinessGate!.future;
    }
    if (fail != null) throw fail!;
    if (action == 'submit') status = 'pending';
    if (action == 'cancel_photos') status = 'rejected';
    return resultGate == null ? receipt() : await resultGate!.future;
  }
}

class MemoryStore extends AdminSavedQualificationPhotoPendingStore {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<bool> compareAndSet(
    String key,
    String? expected,
    String? replacement,
  ) async {
    if (values[key] != expected) return false;
    if (replacement == null) {
      values.remove(key);
    } else {
      values[key] = replacement;
    }
    return true;
  }
}

Future<void> main() async {
  final off = Fixture(enabled: false);
  await rejects(
    () => off.guard.rpc('get_photos', {'id': request}),
    'default OFF sends nothing',
  );
  check(off.calls.isEmpty, 'OFF transport zero');
  await off.guard.dispose();

  final normal = Fixture();
  await normal.guard.rpc('prepare_admin_saved_photos', prepare());
  check(
    normal.calls.map((c) => c.$1).join(',') == 'admin_saved_photo_capability,admin_saved_photo_prepare_readiness,prepare_admin_saved_photos',
    'prepare rechecks dedicated authorization',
  );
  await normal.guard.rpc('get_photos', {'id': request});
  check(normal.calls.length == 6, 'every data call rechecks readiness');
  await rejects(
    () => normal.guard.rpc('submit', {'id': other}),
    'different request forbidden',
  );
  check(normal.calls.length == 6, 'different request never sent');
  await normal.guard.dispose();

  for (final changed in [
    session(a: other),
    session(c: other),
    session(t: other),
    session(token: 'refreshed'),
    session(active: false),
    session(token: null),
  ]) {
    final f = Fixture();
    final events = <bool>[];
    final subscription = f.guard.scopeChanges.listen(
      (s) => events.add(s.active),
    );
    f.guard.observe(changed);
    f.current = session();
    f.guard.observe(f.current);
    await rejects(
      () => f.guard.rpc('get_photos', {'id': request}),
      'observed mismatch remains revoked after ABA',
    );
    check(
      f.calls.isEmpty && events.length == 1 && events.single == false,
      'sticky scope invalidation and no request',
    );
    await subscription.cancel();
    await f.guard.dispose();
  }
  final unobserved = Fixture()..current = session(token: 'new-token');
  await rejects(
    () => unobserved.guard.authorization(),
    'current token checked without event',
  );
  unobserved.current = session();
  await rejects(() => unobserved.guard.authorization(), 'poll mismatch sticky');
  await unobserved.guard.dispose();

  final stream = Fixture();
  stream.guard.invalidate();
  await rejects(
    () => stream.guard.authorization(),
    'stream error/done invalidation entry',
  );
  check(stream.calls.isEmpty, 'stream invalidation sends nothing');
  await stream.guard.dispose();

  final delayed = Fixture()..readinessGate = Completer<Object?>();
  final old = delayed.guard.rpc('prepare_admin_saved_photos', prepare());
  final oldCheck = rejects(() => old, 'old readiness response rejected');
  await Future<void>.delayed(Duration.zero);
  delayed.guard.observe(session(token: 'new-token'));
  delayed.readinessGate!.complete(delayed.readiness());
  await oldCheck;
  check(delayed.calls.length == 2, 'no write after delayed scope change');
  await delayed.guard.dispose();

  final response = Fixture()..resultGate = Completer<Object?>();
  final outstanding = response.guard.rpc(
    'prepare_admin_saved_photos',
    prepare(),
  );
  final responseCheck = rejects(
    () => outstanding,
    'old data response rejected',
  );
  await Future<void>.delayed(Duration.zero);
  response.guard.observe(session(active: false));
  response.resultGate!.complete(response.receipt());
  await responseCheck;
  check(response.calls.length == 3, 'sent write not retried after background');
  await response.guard.dispose();

  final notReady = Fixture()..ready = false;
  await rejects(
    () => notReady.guard.rpc('submit', {'id': request}),
    'readiness false rejects writes',
  );
  check(notReady.calls.length == 2, 'no personal capability fallback');
  await notReady.guard.dispose();

  for (final action in [
    'approve',
    'reject',
    'prepare_photos',
    'delete',
    'photo_capability',
  ]) {
    final f = Fixture();
    await rejects(
      () => f.guard.rpc(action, {}),
      'unallowlisted action rejected',
    );
    check(f.calls.isEmpty, 'no unallowlisted transport');
    await f.guard.dispose();
  }
  final wrongScope = Fixture();
  await rejects(
    () => wrongScope.guard.rpc('prepare_admin_saved_photos', {
      ...prepare(),
      'target_id': other,
    }),
    'wrong prepare target rejected',
  );
  check(wrongScope.calls.isEmpty, 'wrong prepare target no request');
  await wrongScope.guard.dispose();

  final recovery = Fixture();
  await recovery.guard.rpc('submit', {'id': request});
  check(
    recovery.calls.map((c) => c.$1).join(',') == 'admin_saved_photo_capability,admin_saved_photo_prepare_readiness,get_photos,submit',
    'first write proves actor/target receipt before submit',
  );
  await recovery.guard.dispose();
  for (final wrongActor in [false, true]) {
    final f = Fixture();
    if (wrongActor) {
      f.receiptActor = other;
    } else {
      f.receiptTarget = other;
    }
    await rejects(
      () => f.guard.rpc('cancel_photos', {'id': request}),
      'foreign receipt rejects write',
    );
    check(
      f.calls.last.$1 == 'get_photos' && f.calls.length == 3,
      'foreign receipt read only',
    );
    await f.guard.dispose();
  }

  final copy = Fixture()..readinessGate = Completer<Object?>();
  final mutable = prepare();
  final copyFuture = copy.guard.rpc('prepare_admin_saved_photos', mutable);
  await Future<void>.delayed(Duration.zero);
  mutable['target_id'] = other;
  (mutable['expected_photo_paths'] as List).add('other.jpg');
  copy.readinessGate!.complete(copy.readiness());
  await copyFuture;
  check(
    copy.calls.last.$2['target_id'] == target &&
        (copy.calls.last.$2['expected_photo_paths'] as List).length == 1,
    'caller mutation cannot retarget payload during readiness',
  );
  await copy.guard.dispose();
  await rejects(
    () => copy.guard.authorization(),
    'disposed guard remains closed',
  );
  check(
    !session().toString().contains('fixture-token'),
    'token not in snapshot string',
  );
  final serial = Fixture()..readinessGate = Completer<Object?>();
  final first = serial.guard.rpc('prepare_admin_saved_photos', prepare());
  await Future<void>.delayed(Duration.zero);
  await rejects(
    () => serial.guard.rpc('prepare_admin_saved_photos', {
      ...prepare(),
      'request_id': other,
    }),
    'overlapping request rejected before transport',
  );
  check(serial.calls.length == 2, 'overlapping call adds no request');
  serial.readinessGate!.complete(serial.readiness());
  await first;
  await serial.guard.dispose();

  final connected = Fixture();
  final store = MemoryStore();
  final repository = AdminSavedQualificationPhotoSubmissionRepository(
    scope: connected.guard.scope,
    scopeChanges: connected.guard.scopeChanges,
    authorization: connected.guard.authorization,
    rpc: connected.guard.rpc,
    store: store,
    enabled: true,
  );
  final authorized = await connected.guard.authorization();
  final command = AdminSavedQualificationPhotoPrepare.fromDraft(
    draft: AdminSavedQualificationPhotoDraft(
      companyId: company,
      actorId: actor,
      targetId: target,
      savedPaths: ['saved.jpg'],
      selectedPaths: [],
    ),
    capability: authorized.capability,
    readiness: authorized.readiness,
    requestId: request,
    scopeActive: true,
    currentCompanyId: company,
    currentActorId: actor,
    currentTargetId: target,
    currentSavedPaths: ['saved.jpg'],
  );
  final prepared = await repository.prepare(
    command: command,
    currentSavedPaths: ['saved.jpg'],
  );
  check(
    prepared.status == 'draft',
    'existing submission repository composes with session guard',
  );
  final submitted = await repository.submit(expectedRequestId: request);
  check(
    submitted.status == 'pending',
    'composed submit confirms exact receipt',
  );
  check(
    !store.values.values.any((v) => v.contains('fixture-token')),
    'session token never added to existing pending storage',
  );
  connected.guard.observe(session(token: 'refreshed'));
  final callsBefore = connected.calls.length;
  await rejects(
    () => repository.recover(expectedRequestId: request),
    'token change invalidates composed repository before recovery',
  );
  check(
    connected.calls.length == callsBefore,
    'composed stale recovery sends nothing',
  );
  await repository.dispose();
  await connected.guard.dispose();
  print(
    'PASS $checks qualification photo session RPC assertions (pure fake transport; no SDK/server/mobile)',
  );
}
