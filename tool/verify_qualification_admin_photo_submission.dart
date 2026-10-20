// Pure in-process transport/store fixtures. No Flutter, network or user data.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:sk_works/features/qualifications/admin_saved_qualification_photo_contract.dart';
import 'package:sk_works/features/qualifications/admin_saved_qualification_photo_draft.dart';
import 'package:sk_works/features/qualifications/admin_saved_qualification_photo_prepare.dart';
import 'package:sk_works/features/qualifications/admin_saved_qualification_photo_prepare_readiness.dart';
import 'package:sk_works/features/qualifications/admin_saved_qualification_photo_submission_repository.dart';

const company = '00000000-0000-0000-0000-000000000001';
const actor = '00000000-0000-0000-0000-000000000002';
const target = '00000000-0000-0000-0000-000000000003';
const request = '00000000-0000-0000-0000-000000000004';
const other = '00000000-0000-0000-0000-000000000005';
const key = 'sko.admin.qualification.photos.pending.v1.$actor.$company';
const baseline = ['front.jpg', 'back.jpg'];
var checks = 0;
void check(bool value, String label) {
  if (!value) {
    throw StateError(label);
  }
  checks++;
}

Future<void> rejects(Future<Object?> Function() call, String label) async {
  try {
    await call();
  } catch (_) {
    checks++;
    return;
  }
  throw StateError('Expected refusal: $label');
}

AdminSavedQualificationPhotoAuthorization auth({bool available = true}) => (
  capability: AdminSavedQualificationPhotoCapability.parse(
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
  ),
  readiness: AdminSavedQualificationPhotoPrepareReadiness.parse(
    {
      'version': 1,
      'contract': 'qualification_admin_photo_prepare_baseline',
      'company_id': company,
      'actor_id': actor,
      'baseline_guard_version': 1,
      'prepare_action': 'prepare_admin_saved_photos',
      'photo_submission_available': available,
      'photo_upload_allowed': false,
      'max_photos': 20,
      'self_approval_allowed': false,
    },
    companyId: company,
    actorId: actor,
  ),
);
AdminSavedQualificationPhotoPrepare command({
  String id = request,
  List<String> selected = const ['back.jpg'],
}) => AdminSavedQualificationPhotoPrepare.fromDraft(
  draft: AdminSavedQualificationPhotoDraft(
    companyId: company,
    actorId: actor,
    targetId: target,
    savedPaths: baseline,
    selectedPaths: selected,
  ),
  capability: auth().capability,
  readiness: auth().readiness,
  requestId: id,
  scopeActive: true,
  currentCompanyId: company,
  currentActorId: actor,
  currentTargetId: target,
  currentSavedPaths: baseline,
);

class Store extends AdminSavedQualificationPhotoPendingStore {
  final values = <String, String>{};
  int reads = 0, writes = 0;
  bool refuse = false, throwAfter = false;
  void Function()? afterWrite;
  @override
  Future<String?> read(String key) async {
    reads++;
    return values[key];
  }

  @override
  Future<bool> compareAndSet(
    String key,
    String? expected,
    String? replacement,
  ) async {
    writes++;
    if (refuse || values[key] != expected) {
      return false;
    }
    if (replacement == null) {
      values.remove(key);
    } else {
      values[key] = replacement;
    }
    afterWrite?.call();
    if (throwAfter) {
      throwAfter = false;
      throw StateError('synthetic durable commit with lost acknowledgement');
    }
    return true;
  }
}

class Fixture {
  final store = Store();
  final scopes =
      StreamController<AdminSavedQualificationPhotoSubmissionScope>.broadcast(
        sync: true,
      );
  AdminSavedQualificationPhotoSubmissionScope current =
      const AdminSavedQualificationPhotoSubmissionScope(
        actorId: actor,
        companyId: company,
        targetId: target,
        active: true,
      );
  final records = <String, Map<String, dynamic>>{};
  final calls = <String>[];
  final ids = <String>[];
  bool allowed = true;
  int authReads = 0;
  String? failAfter, failBefore;
  int failGets = 0;
  Object? Function(String, Map<String, dynamic>)? alter;
  Future<void> Function(String)? before, after;
  final repos = <AdminSavedQualificationPhotoSubmissionRepository>[];
  AdminSavedQualificationPhotoSubmissionRepository repo({bool enabled = true}) {
    final result = AdminSavedQualificationPhotoSubmissionRepository(
      scope: () => current,
      scopeChanges: scopes.stream,
      authorization: () async {
        authReads++;
        return auth(available: allowed);
      },
      rpc: rpc,
      store: store,
      enabled: enabled,
    );
    repos.add(result);
    return result;
  }

  Future<Object?> rpc(String action, Map<String, dynamic> data) async {
    calls.add(action);
    ids.add((data['request_id'] ?? data['id']).toString());
    await before?.call(action);
    if (action == failBefore) {
      failBefore = null;
      throw StateError('synthetic pre-commit failure');
    }
    if (action == 'get_photos' && failGets > 0) {
      failGets--;
      throw StateError('synthetic read timeout');
    }
    final id = (data['request_id'] ?? data['id']) as String;
    if (action != 'get_photos') {
      final pending = jsonDecode(store.values[key]!);
      check(
        pending['request_id'] == id,
        'fixed request persisted before every write RPC',
      );
      check(
        pending['phase'] ==
            (action == 'prepare_admin_saved_photos'
                ? 'prepare_unknown'
                : action == 'submit'
                ? 'submit_unknown'
                : 'cancel_unknown'),
        'intent persisted before write RPC',
      );
    }
    if (action == 'prepare_admin_saved_photos') {
      check(
        data.keys.toSet().difference({
          'company_id',
          'target_id',
          'request_id',
          'expected_photo_paths',
          'photo_slots',
        }).isEmpty,
        'only existing management prepare contract',
      );
      check(
        jsonEncode(data['expected_photo_paths']) == jsonEncode(baseline),
        'ordered baseline carried into prepare',
      );
      records.putIfAbsent(
        id,
        () => {
          'version': 1,
          'id': id,
          'target_id': data['target_id'],
          'requested_by': actor,
          'status': 'draft',
          'cancelled': false,
          'reason': null,
          'photo_paths': (data['photo_slots'] as List)
              .map((slot) => slot['existing_path'])
              .toList(),
          'upload_paths': <Object?>[],
        },
      );
    } else if (action == 'submit') {
      final row = records[id];
      if (row == null) {
        throw StateError('missing');
      }
      if (row['status'] == 'draft') {
        row['status'] = 'pending';
      }
      if (!{'pending', 'approved'}.contains(row['status'])) {
        throw StateError('not submit-ready');
      }
    } else if (action == 'cancel_photos') {
      final row = records[id];
      if (row == null || row['status'] != 'draft') {
        throw StateError('not draft');
      }
      row.addAll({
        'status': 'rejected',
        'cancelled': true,
        'reason': '合成fixtureの下書き取消',
      });
    } else if (action != 'get_photos') {
      throw StateError('new/unsupported RPC action');
    }
    final row = records[id];
    if (row == null) {
      throw StateError('missing');
    }
    await after?.call(action);
    if (action == failAfter) {
      failAfter = null;
      throw StateError('synthetic post-commit timeout');
    }
    final result = jsonDecode(jsonEncode(row)) as Map<String, dynamic>;
    return alter?.call(action, result) ?? result;
  }

  void switchScope({
    String? user = actor,
    String? cid = company,
    String? tid = target,
    bool active = true,
  }) {
    current = AdminSavedQualificationPhotoSubmissionScope(
      actorId: user,
      companyId: cid,
      targetId: tid,
      active: active,
    );
    scopes.add(current);
  }

  String get phase =>
      (jsonDecode(store.values[key]!) as Map)['phase'] as String;
  Future<void> close() async {
    for (final repo in repos) {
      await repo.dispose();
    }
    await scopes.close();
  }
}

Future<void> run(Future<void> Function(Fixture) test) async {
  final f = Fixture();
  try {
    await test(f);
  } finally {
    await f.close();
  }
}

Future<void> main() async {
  await run((f) async {
    final repo = f.repo(enabled: false);
    check(await repo.pendingRequestId() == null, 'OFF pending is empty');
    await rejects(
      () => repo.prepare(command: command(), currentSavedPaths: baseline),
      'default OFF',
    );
    check(
      f.calls.isEmpty &&
          f.store.reads == 0 &&
          f.store.writes == 0 &&
          f.authReads == 0,
      'OFF makes no transport/store/auth calls',
    );
  });
  await run((f) async {
    final repo = f.repo();
    final prepared = await repo.prepare(
      command: command(),
      currentSavedPaths: baseline,
    );
    check(
      prepared.status == 'draft' &&
          f.calls.join(',') == 'prepare_admin_saved_photos,get_photos',
      'prepare then read, never auto-submit',
    );
    check(
      f.phase == 'prepared' && await repo.pendingRequestId() == request,
      'fixed request retained after prepare',
    );
    await rejects(
      () => repo.acknowledge(expectedRequestId: request),
      'cannot discard unsubmitted draft',
    );
    check(f.store.values.containsKey(key), 'unsubmitted receipt retained');
    final sent = await repo.submit(expectedRequestId: request);
    check(
      sent.status == 'pending' && f.phase == 'confirmed',
      'explicit submit readback confirmed',
    );
    check(
      await repo.pendingRequestId() == request,
      'sent receipt retained without unproven list',
    );
    final writes = f.calls.where((a) => a == 'submit').length;
    await repo.submit(expectedRequestId: request);
    check(
      f.calls.where((a) => a == 'submit').length == writes,
      'known pending never submitted twice',
    );
    await rejects(
      () => repo.cancelDraft(expectedRequestId: request),
      'pending cannot be cancelled',
    );
    check(
      !f.calls.contains('cancel_photos'),
      'no cancel transport for pending',
    );
    await repo.acknowledge(expectedRequestId: request);
    check(
      !f.store.values.containsKey(key),
      'only explicit acknowledged receipt removed',
    );
    check(
      f.records[request]!['status'] == 'pending',
      'ack does not change server record',
    );
  });
  await run((f) async {
    final repo = f.repo();
    await repo.prepare(
      command: command(selected: []),
      currentSavedPaths: baseline,
    );
    check(
      (f.records[request]!['photo_paths'] as List).isEmpty,
      'all-photo exclusion uses empty slots',
    );
    f.failAfter = 'cancel_photos';
    final cancelled = await repo.cancelDraft(expectedRequestId: request);
    check(
      cancelled.cancelled && cancelled.status == 'rejected',
      'lost cancel acknowledgement recovered by same ID read',
    );
    check(
      f.phase == 'confirmed' && f.records.length == 1,
      'cancellation retains recoverable receipt and record',
    );
  });
  for (final failure in ['prepare_admin_saved_photos', 'submit']) {
    await run((f) async {
      final repo = f.repo();
      if (failure == 'prepare_admin_saved_photos') {
        f.failAfter = failure;
      }
      await repo.prepare(command: command(), currentSavedPaths: baseline);
      if (failure == 'submit') {
        f.failAfter = failure;
        await repo.submit(expectedRequestId: request);
      }
      check(
        f.records.length == 1 && f.ids.every((id) => id == request),
        'lost write response never creates another identity',
      );
    });
  }
  await run((f) async {
    var repo = f.repo();
    f.failGets = 1;
    await rejects(
      () => repo.prepare(command: command(), currentSavedPaths: baseline),
      'prepare readback timeout',
    );
    check(
      f.phase == 'prepare_unknown' && f.records.length == 1,
      'unknown prepare kept durably',
    );
    await repo.dispose();
    repo = f.repo();
    final recovered = await repo.recover(expectedRequestId: request);
    check(
      recovered.status == 'draft' && f.records.length == 1,
      'restart repeats same prepare and confirms original draft',
    );
    check(!f.calls.contains('submit'), 'recovery has no implicit submit');
  });
  await run((f) async {
    var repo = f.repo();
    await repo.prepare(command: command(), currentSavedPaths: baseline);
    f.failAfter = 'submit';
    f.failGets = 1;
    // The pre-submit get uses this first read; make only post-submit reads fail.
    f.failGets = 0;
    f.after = (action) async {
      if (action == 'submit') {
        f.failGets = 1;
      }
    };
    await rejects(
      () => repo.submit(expectedRequestId: request),
      'submit result unknown',
    );
    check(
      f.phase == 'submit_unknown' && f.records[request]!['status'] == 'pending',
      'unknown submit retains intent',
    );
    await repo.dispose();
    repo = f.repo();
    f.after = null;
    final prior = f.calls.where((a) => a == 'submit').length;
    final recovered = await repo.recover(expectedRequestId: request);
    check(
      recovered.submitted &&
          f.calls.where((a) => a == 'submit').length == prior,
      'restart resolves submit via get only',
    );
  });
  await run((f) async {
    final repo = f.repo();
    await repo.prepare(command: command(), currentSavedPaths: baseline);
    f.failBefore = 'submit';
    await rejects(
      () => repo.submit(expectedRequestId: request),
      'uncommitted submit remains draft',
    );
    final prior = f.calls.where((a) => a == 'submit').length;
    check(
      (await repo.recover(expectedRequestId: request)).status == 'draft',
      'recovery returns actual draft',
    );
    check(
      f.calls.where((a) => a == 'submit').length == prior,
      'recovery never retries an unconfirmed submit',
    );
    await repo.submit(expectedRequestId: request);
    check(
      f.records[request]!['status'] == 'pending',
      'new explicit submit may retry same ID',
    );
  });
  for (final durableFailure in ['refuse', 'ack_lost']) {
    await run((f) async {
      final repo = f.repo();
      f.store.refuse = durableFailure == 'refuse';
      f.store.throwAfter = durableFailure == 'ack_lost';
      await rejects(
        () => repo.prepare(command: command(), currentSavedPaths: baseline),
        'persistence failure',
      );
      check(f.calls.isEmpty, 'RPC never precedes confirmed durable write');
      if (durableFailure == 'ack_lost') {
        check(
          await repo.pendingRequestId() == request,
          'uncertain durable write keeps fixed identity',
        );
        await repo.recover(expectedRequestId: request);
        check(
          f.records.length == 1,
          'persisted intent can recover without fresh ID',
        );
      }
    });
  }
  for (final corrupt in <Map<String, dynamic> Function(Map<String, dynamic>)>[
    (r) => {...r, 'version': 1.0},
    (r) => {...r, 'id': other},
    (r) => {...r, 'target_id': other},
    (r) => {...r, 'requested_by': other},
    (r) => {...r, 'status': 'unknown'},
    (r) => {...r, 'cancelled': null},
    (r) => {...r, 'cancelled': true},
    (r) => {...r, 'reason': 42},
    (r) => {
      ...r,
      'photo_paths': ['front.jpg'],
    },
    (r) => {
      ...r,
      'photo_paths': ['back.jpg', 'back.jpg'],
    },
    (r) => {
      ...r,
      'upload_paths': [
        {'index': 0, 'path': 'new.jpg', 'extension': 'jpg'},
      ],
    },
    (r) => {...r, 'company_id': company},
    (r) => {...r}..remove('reason'),
  ]) {
    await run((f) async {
      final repo = f.repo();
      f.alter = (action, row) =>
          action == 'prepare_admin_saved_photos' ? corrupt(row) : row;
      await rejects(
        () => repo.prepare(command: command(), currentSavedPaths: baseline),
        'response scope/shape/order',
      );
      check(
        f.calls.length == 1 && f.phase == 'prepare_unknown',
        'invalid response stops without fallback and keeps pending',
      );
      f.alter = null;
      await repo.recover(expectedRequestId: request);
      check(
        f.records.length == 1,
        'invalid response recovery retains original identity',
      );
    });
  }
  for (final kind in [
    'actor',
    'company',
    'target',
    'background',
    'stream_error',
  ]) {
    await run((f) async {
      final repo = f.repo();
      final entered = Completer<void>(), release = Completer<void>();
      f.after = (action) async {
        if (action == 'prepare_admin_saved_photos') {
          entered.complete();
          await release.future;
        }
      };
      final result = repo.prepare(
        command: command(),
        currentSavedPaths: baseline,
      );
      // Attach a consuming error handler before releasing the late response.
      final observed = result.then<Object?>((v) => v, onError: (Object e) => e);
      await entered.future;
      if (kind == 'actor') {
        f.switchScope(user: other);
        f.switchScope();
      }
      if (kind == 'company') {
        f.switchScope(cid: other);
        f.switchScope();
      }
      if (kind == 'target') {
        f.switchScope(tid: other);
        f.switchScope();
      }
      if (kind == 'background') {
        f.switchScope(active: false);
        f.switchScope();
      }
      if (kind == 'stream_error') {
        f.scopes.addError(StateError('synthetic scope failure'));
      }
      release.complete();
      check(
        await observed is StateError,
        'late response refused after scope invalidation',
      );
      await rejects(
        () => repo.recover(expectedRequestId: request),
        'sticky invalidation',
      );
      check(
        f.calls.length == 1 && f.store.values.containsKey(key),
        'no follow-up get/write under revoked scope',
      );
    });
  }
  await run((f) async {
    final repo = f.repo();
    await repo.prepare(command: command(), currentSavedPaths: baseline);
    final before = f.calls.length;
    await rejects(
      () => repo.recover(expectedRequestId: other),
      'displayed request mismatch',
    );
    check(f.calls.length == before, 'wrong expected identity has no RPC');
    f.allowed = false;
    await rejects(
      () => repo.recover(expectedRequestId: request),
      'permission revoked',
    );
    check(
      f.calls.length == before,
      'readiness/permission refusal has no mutation or fallback',
    );
  });
  await run((f) async {
    final repo = f.repo(), second = f.repo();
    final entered = Completer<void>(), release = Completer<void>();
    f.before = (action) async {
      if (action == 'prepare_admin_saved_photos') {
        entered.complete();
        await release.future;
      }
    };
    final first = repo.prepare(command: command(), currentSavedPaths: baseline);
    await entered.future;
    await rejects(
      () => second.prepare(
        command: command(id: other),
        currentSavedPaths: baseline,
      ),
      'another repository pending request',
    );
    await rejects(
      () => repo.recover(expectedRequestId: request),
      'same repository busy',
    );
    release.complete();
    await first;
    check(
      f.records.length == 1 && f.records.containsKey(request),
      'concurrent requests never overwrite persisted identity',
    );
  });
  await run((f) async {
    var repo = f.repo();
    await repo.prepare(command: command(), currentSavedPaths: baseline);
    f.failAfter = 'cancel_photos';
    f.after = (action) async {
      if (action == 'cancel_photos') {
        f.failGets = 1;
      }
    };
    await rejects(
      () => repo.cancelDraft(expectedRequestId: request),
      'cancel result unknown',
    );
    check(
      f.phase == 'cancel_unknown' && f.records[request]!['cancelled'] == true,
      'unknown cancel retains intent',
    );
    await repo.dispose();
    repo = f.repo();
    f.after = null;
    final prior = f.calls.where((action) => action == 'cancel_photos').length;
    final result = await repo.recover(expectedRequestId: request);
    check(
      result.cancelled &&
          f.calls.where((action) => action == 'cancel_photos').length == prior,
      'cancel recovery is get-only',
    );
  });
  await run((f) async {
    final repo = f.repo();
    await repo.prepare(command: command(), currentSavedPaths: baseline);
    f.failBefore = 'cancel_photos';
    await rejects(
      () => repo.cancelDraft(expectedRequestId: request),
      'uncommitted cancellation',
    );
    final prior = f.calls.where((action) => action == 'cancel_photos').length;
    check(
      (await repo.recover(expectedRequestId: request)).status == 'draft',
      'cancel recovery reports actual draft',
    );
    check(
      f.calls.where((action) => action == 'cancel_photos').length == prior,
      'recover never silently cancels',
    );
    await repo.cancelDraft(expectedRequestId: request);
    check(
      f.records[request]!['cancelled'] == true,
      'explicit same-ID cancellation retries safely',
    );
  });
  for (final corrupt in <Map<String, dynamic> Function(Map<String, dynamic>)>[
    (r) => {...r, 'version': 1.0},
    (r) => {...r, 'actor_id': other},
    (r) => {...r, 'company_id': other},
    (r) => {...r, 'target_id': other},
    (r) => {...r, 'request_id': other},
    (r) => {...r, 'phase': 'pending'},
    (r) => {...r, 'revision': -1},
    (r) => {...r, 'expected_photo_paths': []},
    (r) => {
      ...r,
      'expected_photo_paths': ['front.jpg', 'front.jpg'],
    },
    (r) => {
      ...r,
      'selected_photo_paths': ['new.jpg'],
    },
    (r) => {
      ...r,
      'selected_photo_paths': ['back.jpg', 'back.jpg'],
    },
    (r) => {...r, 'unexpected': true},
  ]) {
    await run((f) async {
      final repo = f.repo();
      await repo.prepare(command: command(), currentSavedPaths: baseline);
      final original = f.store.values[key]!;
      f.store.values[key] = jsonEncode(
        corrupt(jsonDecode(original) as Map<String, dynamic>),
      );
      final prior = f.calls.length;
      await rejects(
        () => repo.recover(expectedRequestId: request),
        'malformed or different local identity',
      );
      check(
        f.calls.length == prior && f.store.values.containsKey(key),
        'invalid pending record is neither replayed nor silently deleted',
      );
    });
  }
  await run((f) async {
    final repo = f.repo();
    await repo.prepare(command: command(), currentSavedPaths: baseline);
    f.store.refuse = true;
    await rejects(
      () => repo.submit(expectedRequestId: request),
      'submit intent CAS failure',
    );
    check(
      !f.calls.contains('submit') && f.phase == 'prepared',
      'submit does not precede durable intent update',
    );
  });
  await run((f) async {
    final repo = f.repo();
    f.store.afterWrite = () {
      f.store.values[key] = f.store.values[key]!.replaceFirst(
        'prepare_unknown',
        'prepared',
      );
    };
    await rejects(
      () => repo.prepare(command: command(), currentSavedPaths: baseline),
      'durable readback differs',
    );
    check(f.calls.isEmpty, 'unverified durable readback makes no RPC');
  });
  await run((f) async {
    final repo = f.repo();
    await repo.prepare(command: command(), currentSavedPaths: baseline);
    await repo.submit(expectedRequestId: request);
    f.after = (action) async {
      if (action == 'get_photos') {
        final value = jsonDecode(f.store.values[key]!) as Map<String, dynamic>;
        value['request_id'] = other;
        f.store.values[key] = jsonEncode(value);
      }
    };
    await rejects(
      () => repo.acknowledge(expectedRequestId: request),
      'ack must not clear a replacement request',
    );
    check(
      (jsonDecode(f.store.values[key]!) as Map)['request_id'] == other,
      'replacement local request retained',
    );
  });
  await run((f) async {
    final repo = f.repo();
    await repo.prepare(command: command(), currentSavedPaths: baseline);
    f.current = const AdminSavedQualificationPhotoSubmissionScope(
      actorId: other,
      companyId: company,
      targetId: target,
      active: true,
    );
    final prior = f.calls.length;
    await rejects(
      () => repo.recover(expectedRequestId: request),
      'scope getter detects change without event',
    );
    f.current = const AdminSavedQualificationPhotoSubmissionScope(
      actorId: actor,
      companyId: company,
      targetId: target,
      active: true,
    );
    await rejects(
      () => repo.recover(expectedRequestId: request),
      'observed getter ABA stays revoked',
    );
    check(
      f.calls.length == prior,
      'no old-scope recovery after getter invalidation',
    );
  });
  await run((f) async {
    final repo = f.repo();
    await repo.prepare(command: command(), currentSavedPaths: baseline);
    f.alter = (action, row) =>
        action == 'submit' ? {...row, 'status': 'draft'} : row;
    await rejects(
      () => repo.submit(expectedRequestId: request),
      'write response with impossible submit status',
    );
    check(
      f.phase == 'submit_unknown',
      'bad write response retains unknown intent',
    );
    f.alter = null;
    check(
      (await repo.recover(expectedRequestId: request)).submitted,
      'same-ID recovery resolves real pending state',
    );
  });
  for (final operation in ['submit', 'cancel', 'acknowledge']) {
    await run((f) async {
      final repo = f.repo();
      await repo.prepare(command: command(), currentSavedPaths: baseline);
      await repo.submit(expectedRequestId: request);
      final prior = f.calls.length;
      f.alter = (action, row) =>
          action == 'get_photos' ? {...row, 'status': 'draft'} : row;
      await rejects(
        () => switch (operation) {
          'submit' => repo.submit(expectedRequestId: request),
          'cancel' => repo.cancelDraft(expectedRequestId: request),
          _ => repo.acknowledge(expectedRequestId: request),
        },
        'confirmed state regression refuses $operation',
      );
      check(f.calls.length == prior + 1, 'regression performs only read');
      check(f.store.values.containsKey(key), 'regression retains receipt');
    });
  }
  stdout.writeln(
    'PASS $checks management submission checks: durable fixed identity, explicit submit/cancel, strict response, transport uncertainty recovery, scope ABA, pending retention, no new APIs/uploads/review',
  );
}
