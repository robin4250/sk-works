import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/qualifications/admin_saved_qualification_photo_capability_repository.dart';

import 'admin_saved_qualification_photo_contract_test.dart'
    show company, actor, validCapability;

void main() {
  late StreamController<String?> actors, companies;
  late String? currentActor, currentCompany;
  late List<({String action, Map<String, dynamic> data})> calls;
  late Future<Object?> Function() reply;
  late AdminSavedQualificationPhotoCapabilityRepository repo;
  setUp(() {
    actors = StreamController<String?>.broadcast(sync: true);
    companies = StreamController<String?>.broadcast(sync: true);
    currentActor = actor;
    currentCompany = company;
    calls = [];
    reply = () async => validCapability();
  });
  void create({bool enabled = true}) {
    repo = AdminSavedQualificationPhotoCapabilityRepository.forTesting(
      actor: () => currentActor,
      companyId: () => currentCompany,
      actorChanges: actors.stream,
      companyChanges: companies.stream,
      rpc: (action, data) {
        calls.add((action: action, data: data));
        return reply();
      },
      enabled: enabled,
    );
  }

  tearDown(() async {
    await repo.dispose();
    await actors.close();
    await companies.close();
  });
  test(
    'OFF by default makes no transport calls; invalid identity does not read',
    () async {
      repo = AdminSavedQualificationPhotoCapabilityRepository.forTesting(
        actor: () => actor,
        companyId: () => company,
        actorChanges: actors.stream,
        companyChanges: companies.stream,
        rpc: (_, _) {
          fail('Default gate must not call transport');
        },
      );
      expect((await repo.capability()).available, false);
      await repo.dispose();
      currentActor = null;
      create();
      expect((await repo.capability()).available, false);
      expect(calls, isEmpty);
    },
  );
  test('dedicated read sends exact company and never falls back to personal capability', () async {
    create();
    final cap = await repo.capability();
    expect(cap.available, true);
    expect(repo.canUse(cap), true);
    expect(calls, hasLength(1));
    expect(calls.single.action, 'admin_saved_photo_capability');
    expect(calls.single.data, {'company_id': company});
    reply = () async => throw StateError('Synthetic missing API');
    expect((await repo.capability()).available, false);
    expect(calls.map((call) => call.action).toSet(), {
      'admin_saved_photo_capability',
    });
  });
  test(
    'rejects personal and other-scope responses without any second action',
    () async {
      create();
      for (final raw in [
        {
          'version': 1,
          'photo_submission_available': true,
          'photo_upload_allowed': false,
          'max_photos': 20,
        },
        {...validCapability(), 'actor_id': company},
        {...validCapability(), 'company_id': actor},
      ]) {
        reply = () async => raw;
        expect((await repo.capability()).available, false);
      }
      expect(calls.length, 3);
    },
  );
  for (final scope in ['actor', 'company']) {
    test(
      '$scope ABA during read stays revoked even after original identity returns',
      () async {
        create();
        final pending = Completer<Object?>();
        reply = () => pending.future;
        final result = repo.capability();
        if (scope == 'actor') {
          actors.add(null);
          actors.add(actor);
        } else {
          companies.add(actor);
          companies.add(company);
        }
        pending.complete(validCapability());
        expect((await result).available, false);
        expect((await repo.capability()).available, false);
        expect(calls.length, 1);
      },
    );
    test(
      '$scope switch after read revokes previously returned capability',
      () async {
        create();
        final cap = await repo.capability();
        expect(repo.canUse(cap), true);
        if (scope == 'actor') {
          currentActor = company;
        } else {
          currentCompany = actor;
        }
        expect(repo.canUse(cap), false);
        currentActor = actor;
        currentCompany = company;
        expect(repo.canUse(cap), false);
        expect((await repo.capability()).available, false);
        expect(calls.length, 1);
      },
    );
    test(
      '$scope stream error invalidates in-flight response and future reads',
      () async {
        create();
        final pending = Completer<Object?>();
        reply = () => pending.future;
        final result = repo.capability();
        (scope == 'actor' ? actors : companies).addError(
          StateError('Synthetic stream failure'),
        );
        pending.complete(validCapability());
        expect((await result).available, false);
        expect((await repo.capability()).available, false);
        expect(calls.length, 1);
      },
    );
  }
  Map<String, Object> validReadiness() => {
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
  test(
    'readiness stays OFF without the local gate and makes no calls',
    () async {
      create(enabled: false);
      expect((await repo.prepareReadiness()).available, false);
      expect(calls, isEmpty);
    },
  );
  test(
    'readiness reads only the dedicated action and never falls back',
    () async {
      create();
      reply = () async => validReadiness();
      expect((await repo.prepareReadiness()).available, true);
      expect(calls.single.action, 'admin_saved_photo_prepare_readiness');
      expect(calls.single.data, {'company_id': company});
      reply = () async => validCapability();
      expect((await repo.prepareReadiness()).available, false);
      reply = () async => throw StateError('Synthetic old server or denial');
      expect((await repo.prepareReadiness()).available, false);
      expect(calls, hasLength(3));
      expect(calls.map((call) => call.action).toSet(), {
        'admin_saved_photo_prepare_readiness',
      });
    },
  );
  test('readiness rejects a late actor ABA and remains OFF', () async {
    create();
    final pending = Completer<Object?>();
    reply = () => pending.future;
    final result = repo.prepareReadiness();
    actors.add(company);
    actors.add(actor);
    pending.complete(validReadiness());
    expect((await result).available, false);
    expect((await repo.prepareReadiness()).available, false);
    expect(calls, hasLength(1));
  });
  test('disposed readiness never reaches transport', () async {
    create();
    await repo.dispose();
    expect((await repo.prepareReadiness()).available, false);
    expect(calls, isEmpty);
  });
  test('disposed repository cannot reuse a completed response', () async {
    create();
    final cap = await repo.capability();
    await repo.dispose();
    expect(repo.canUse(cap), false);
    expect((await repo.capability()).available, false);
    expect(calls.length, 1);
  });
}
