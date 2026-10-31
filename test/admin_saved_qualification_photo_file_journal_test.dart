import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/qualifications/admin_saved_qualification_photo_file_journal.dart';
import 'package:sk_works/features/qualifications/admin_saved_qualification_photo_submission_repository.dart';

import 'admin_saved_qualification_photo_submission_repository_test.dart'
    show Port, row, sessionB;

const actor = '10000000-0000-0000-0000-000000000001';
const company = '10000000-0000-0000-0000-000000000002';
const target = '10000000-0000-0000-0000-000000000004';
const request = '10000000-0000-0000-0000-000000000007';
const key = 'sko.admin.qualification.saved.v1.$actor.$company.$target';
Map<String, dynamic> record({
  String id = request,
  String stage = 'prepare_started',
}) => {
  'version': 1,
  'actor_id': actor,
  'company_id': company,
  'worker_id': '10000000-0000-0000-0000-000000000003',
  'target_id': target,
  'session_id': '10000000-0000-0000-0000-000000000005',
  'request_id': id,
  'expected_photo_paths': ['synthetic/front'],
  'selected_paths': <String>[],
  'stage': stage,
};

class FilePort extends Port {
  FilePort(this.root, {this.afterFlush});
  final Directory root;
  final Future<void> Function()? afterFlush;
  late final file = FileAdminSavedQualificationPhotoJournal(
    currentActor: () => actor,
    requireScope: () {
      if (!current) throw StateError('fixture retired');
    },
    directory: () async => root,
    afterFlush: afterFlush,
  );
  @override
  Future<String?> readJournal(String key) => file.read(key);
  @override
  Future<void> writeJournal(String key, String value) => file.write(key, value);
  @override
  Future<void> clearJournal(String key) => file.clear(key);
  @override
  Future<Object?> call(String action, Map<String, dynamic> data) async {
    if (action != 'prepare_admin_saved_photos') return super.call(action, data);
    await check();
    calls.add(action);
    request = jsonDecode((await file.read(key))!) as Map<String, dynamic>;
    expect(request!['stage'], 'prepare_started');
    expect(data['request_id'], request!['request_id']);
    expect(data['expected_photo_paths'], ['synthetic/front', 'synthetic/back']);
    if (unknownPrepare) throw StateError('fixture prepare unknown');
    return result();
  }
}

void main() {
  late Directory root;
  late String current;
  setUp(() async {
    root = await Directory.systemTemp.createTemp(
      'qualification-journal-fixture-',
    );
    current = actor;
  });
  tearDown(() async {
    await root.delete(recursive: true);
  });
  FileAdminSavedQualificationPhotoJournal store({
    Future<void> Function()? afterFlush,
    Future<String?> Function(String)? legacy,
  }) => FileAdminSavedQualificationPhotoJournal(
    currentActor: () => current,
    requireScope: () {},
    directory: () async => root,
    afterFlush: afterFlush,
    legacyRead: legacy,
  );
  test(
    'real flushed file failure blocks prepare and retains restart intent',
    () async {
      final p = FilePort(
        root,
        afterFlush: () async => throw StateError('fixture disk stage'),
      );
      final repo = AdminSavedQualificationSubmissionRepository(
        p,
        AdminSavedQualificationTarget(row()),
      );
      await expectLater(repo.submit([]), throwsStateError);
      expect(p.calls, ['admin_saved_photo_capability']);
      final next = FilePort(root)..sid = sessionB;
      final reopened = AdminSavedQualificationSubmissionRepository(
        next,
        AdminSavedQualificationTarget(row()),
      );
      final pending = await reopened.journal();
      expect(pending, isNotNull);
      expect(pending!['stage'], 'prepare_started');
      await expectLater(reopened.submit([]), throwsStateError);
      expect(next.calls, isEmpty);
    },
  );
  test('new repository and SID read same file request after unknown submit, never resend', () async {
    final p = FilePort(root)..unknownSubmit = true;
    final repo = AdminSavedQualificationSubmissionRepository(
      p,
      AdminSavedQualificationTarget(row()),
    );
    await expectLater(repo.submit([]), throwsStateError);
    final original = await repo.journal();
    final next = FilePort(root)
      ..sid = sessionB
      ..request = p.request
      ..status = p.status;
    final reopened = AdminSavedQualificationSubmissionRepository(
      next,
      AdminSavedQualificationTarget(row()),
    );
    expect((await reopened.reconcile())!.status, 'pending');
    expect(next.calls, ['get_photos']);
    expect((await reopened.journal())!['request_id'], original!['request_id']);
    expect((await reopened.journal())!['session_id'], original['session_id']);
    await expectLater(reopened.submit([]), throwsStateError);
    expect(next.calls, ['get_photos']);
    next.status = 'approved';
    await reopened.acknowledgeFinal();
    expect(await reopened.journal(), isNull);
  });
  test(
    'flushed intent survives new store instance with same exact ID',
    () async {
      final value = jsonEncode(record());
      await store().write(key, value);
      expect(await store().read(key), value);
      final files = await root
          .list(recursive: true)
          .where((f) => f.path.endsWith('.json'))
          .toList();
      expect(files.length, 1);
      expect(await File(files.single.path).readAsString(), contains('sha256'));
    },
  );
  test('interrupted first write is retained and decoded on restart, never discarded', () async {
    final value = jsonEncode(record());
    await expectLater(
      store(afterFlush: () async => throw StateError('fixture after flush'))
          .write(key, value),
      throwsStateError,
    );
    expect(
      (await root.list(recursive: true).toList()).any(
        (f) => f.path.endsWith('.tmp'),
      ),
      isTrue,
    );
    expect(await store().read(key), value);
    expect(
      (await root.list(recursive: true).toList()).any(
        (f) => f.path.endsWith('.tmp'),
      ),
      isFalse,
    );
  });
  test(
    'interrupted replacement holds both records for explicit review',
    () async {
      await store().write(key, jsonEncode(record()));
      await expectLater(
        store(afterFlush: () async => throw StateError('fixture replacement'))
            .write(key, jsonEncode(record(stage: 'prepared'))),
        throwsStateError,
      );
      await expectLater(store().read(key), throwsStateError);
      final entries = await root.list(recursive: true).toList();
      expect(entries.where((f) => f.path.endsWith('.json')).length, 1);
      expect(entries.where((f) => f.path.endsWith('.tmp')).length, 1);
    },
  );
  test('corrupted checksum fails closed and keeps original file', () async {
    await store().write(key, jsonEncode(record()));
    final file =
        (await root
                .list(recursive: true)
                .where((f) => f.path.endsWith('.json'))
                .toList())
            .single;
    final envelope = jsonDecode(await File(file.path).readAsString()) as Map;
    envelope['value'] = jsonEncode(record(stage: 'approved'));
    await File(file.path).writeAsString(jsonEncode(envelope), flush: true);
    await expectLater(store().read(key), throwsStateError);
    expect(await File(file.path).exists(), isTrue);
  });
  test('scope or actor changes after flush preserve recovery record', () async {
    await expectLater(
      store(
        afterFlush: () async {
          current = company;
        },
      ).write(key, jsonEncode(record())),
      throwsStateError,
    );
    current = actor;
    expect(jsonDecode((await store().read(key))!)['request_id'], request);
    current = company;
    await expectLater(store().read(key), throwsStateError);
  });
  test('legacy preferences are not ignored or silently migrated', () async {
    final old = jsonEncode(record());
    await expectLater(
      store(legacy: (_) async => old).read(key),
      throwsStateError,
    );
    await expectLater(
      store(legacy: (_) async => old).write(key, jsonEncode(record())),
      throwsStateError,
    );
  });
  test(
    'only a matching final receipt permits active-pointer removal',
    () async {
      await store().write(key, jsonEncode(record(stage: 'pending')));
      await expectLater(store().clear(key), throwsStateError);
      final receipt = '$key.receipt.$request';
      await store().write(receipt, jsonEncode(record(stage: 'approved')));
      await store().clear(key);
      expect(await store().read(key), isNull);
      expect(jsonDecode((await store().read(receipt))!)['stage'], 'approved');
    },
  );
  test('different request or final status cannot overwrite active or archived intent', () async {
    await store().write(key, jsonEncode(record()));
    await expectLater(
      store().write(key, jsonEncode(record(id: company))),
      throwsStateError,
    );
    final receipt = '$key.receipt.$request';
    await store().write(receipt, jsonEncode(record(stage: 'approved')));
    await expectLater(
      store().write(receipt, jsonEncode(record(stage: 'rejected'))),
      throwsStateError,
    );
    expect(jsonDecode((await store().read(key))!)['request_id'], request);
  });
  test(
    'module-folder symlink is rejected without writing outside its namespace',
    () async {
      final outside = await Directory.systemTemp.createTemp(
        'qualification-journal-outside-',
      );
      addTearDown(() => outside.delete(recursive: true));
      await Link('${root.path}/qualification-admin-photo-pending-v1')
          .create(outside.path);
      await expectLater(
        store().write(key, jsonEncode(record())),
        throwsStateError,
      );
      expect(await outside.list().toList(), isEmpty);
    },
  );
  test(
    'competing new request identities do not replace the first accepted intent',
    () async {
      final outcomes = await Future.wait(
        [request, company].map((id) async {
          try {
            await store().write(key, jsonEncode(record(id: id)));
            return true;
          } catch (_) {
            return false;
          }
        }),
      );
      expect(outcomes.where((v) => v).length, 1);
      expect([
        request,
        company,
      ], contains(jsonDecode((await store().read(key))!)['request_id']));
    },
  );
}
