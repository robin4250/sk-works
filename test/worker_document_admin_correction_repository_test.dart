import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sk_works/features/people/worker_document_admin_correction_repository.dart';

void main() {
  const actor = '70000000-0000-0000-0000-000000000004';
  const company = '70000000-0000-0000-0000-000000000001';
  const target = '70000000-0000-0000-0000-000000000006';
  const request = '70000000-0000-0000-0000-000000000020';
  const key = 'sko.document.admin.correction.v1:$actor:$company:$target';
  final snapshot = <String, dynamic>{
    'id': target,
    'company_id': company,
    'notes': 'private original',
    'updated_by': actor,
    'template_version_id': null,
  };
  Map<String, dynamic> receipt(String status) => {
    'version': 1,
    'contract': 'worker_document_admin_self_correction',
    'request_id': request,
    'company_id': company,
    'target_id': target,
    'actor_id': actor,
    'status': status,
  };
  late SharedPreferences preferences;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    preferences = await SharedPreferences.getInstance();
  });
  WorkerDocumentAdminCorrectionRepository create(
    Future<Object?> Function(String, Map<String, dynamic>) rpc, {
    void Function()? current,
  }) => WorkerDocumentAdminCorrectionRepository.forTesting(
    actor: actor,
    companyId: company,
    targetId: target,
    preferences: preferences,
    rpc: rpc,
    requireCurrent: current ?? () {},
  );
  Future<String> correct(WorkerDocumentAdminCorrectionRepository repository) =>
      repository.correct(
        requestId: request,
        expectedSnapshot: snapshot,
        paths: ['private-photo-path'],
        expiresAt: '2030-01-01',
        notes: 'private new notes',
        reason: 'private reason',
      );

  test(
    'malformed capability is unknown and never coerced to unavailable',
    () async {
      final base = <String, dynamic>{
        'version': 1,
        'contract': 'worker_document_admin_self_correction',
        'company_id': company,
        'target_id': target,
        'actor_id': actor,
        'available': false,
        'new_upload_available': false,
        'max_photos': 20,
      };
      for (final raw in [
        null,
        {...base, 'company_id': 'foreign'},
        {...base, 'available': 'false'},
        {...base, 'version': 1.0},
      ]) {
        final repository = create((action, data) async => raw);
        await expectLater(repository.available(), throwsFormatException);
      }
      expect(await create((action, data) async => base).available(), false);
    },
  );
  test(
    'persist only IDs and verify journal before one write; applied clears it',
    () async {
      final repository = create((action, data) async {
        expect(action, 'correct');
        final journal = jsonDecode(preferences.getString(key)!) as Map;
        expect(journal.keys.toSet(), {
          'version',
          'actor_id',
          'company_id',
          'target_id',
          'request_id',
        });
        expect(preferences.getString(key), isNot(contains('private')));
        expect(data['reason'], 'private reason');
        return receipt('applied');
      });
      expect(await correct(repository), 'applied');
      expect(preferences.getString(key), isNull);
    },
  );
  test('lost response retains ID; ID-only cancellation reconciles before another command', () async {
    var writes = 0;
    final repository = create((action, data) async {
      if (action == 'correct') {
        writes++;
        throw TimeoutException('unknown result');
      }
      expect(action, 'reconcile_cancel');
      expect(data, {
        'company_id': company,
        'target_id': target,
        'request_id': request,
      });
      return receipt('applied');
    });
    await expectLater(correct(repository), throwsA(isA<TimeoutException>()));
    await expectLater(correct(repository), throwsStateError);
    expect(writes, 1);
    expect(await repository.recover(), 'applied');
    expect(repository.pendingRequest(), isNull);
  });
  test(
    'unknown recovery keeps journal; cancelled tombstone then clears it',
    () async {
      var status = 'unknown';
      final repository = create((action, data) async => receipt(status));
      expect(await correct(repository), 'unknown');
      expect(await repository.recover(), 'unknown');
      expect(repository.pendingRequest(), request);
      status = 'cancelled';
      expect(await repository.recover(), 'cancelled');
      expect(repository.pendingRequest(), isNull);
    },
  );
  test('mismatched receipt cannot clear operation identity', () async {
    final repository = create(
      (action, data) async => {...receipt('applied'), 'target_id': 'other'},
    );
    await expectLater(correct(repository), throwsFormatException);
    expect(repository.pendingRequest(), request);
  });
  test(
    'scope retirement after HTTP does not adopt success or clear journal',
    () async {
      var current = true;
      final repository = create(
        (action, data) async {
          current = false;
          return receipt('applied');
        },
        current: () {
          if (!current) {
            throw StateError('scope retired');
          }
        },
      );
      await expectLater(correct(repository), throwsStateError);
      expect(preferences.getString(key), isNotNull);
    },
  );
  test('second repository cannot race a write for the same target', () async {
    final pending = Completer<Object?>();
    final entered = Completer<void>();
    final first = create((action, data) {
      entered.complete();
      return pending.future;
    });
    final second = create((action, data) async => receipt('cancelled'));
    final write = correct(first);
    await entered.future;
    await expectLater(second.recover(), throwsStateError);
    pending.complete(receipt('applied'));
    expect(await write, 'applied');
  });
}
