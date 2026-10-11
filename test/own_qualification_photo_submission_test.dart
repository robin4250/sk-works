import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sk_works/features/people/worker_document_photos.dart';
import 'package:sk_works/features/qualifications/own_qualification_photo_contract.dart';
import 'package:sk_works/features/qualifications/own_qualification_photo_submission_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('displayed request mismatch refuses cancellation and recovery before any RPC', () async {
    final fixture = PhotoFixture()..failUploadAt = 1;
    await expectLater(
      fixture.repository.submitSelection(
        row: fixture.row,
        photos: fixture.photos,
      ),
      throwsStateError,
    );
    final before = fixture.actions.length;
    await expectLater(
      fixture.repository.cancelDraft(expectedRequestId: 'another-request'),
      throwsStateError,
    );
    await expectLater(
      fixture.repository.recover(expectedRequestId: 'another-request'),
      throwsStateError,
    );
    expect(fixture.actions.length, before);
    expect(await fixture.repository.pending(), isNotNull);
  });

  test('confirmed pending recovery does not submit or upload again', () async {
    final fixture = PhotoFixture()..loseGetPending = true;
    await expectLater(
      fixture.repository.submitSelection(
        row: fixture.row,
        photos: fixture.photos,
      ),
      throwsStateError,
    );
    expect(await fixture.repository.pending(), isNotNull);
    fixture.loseGetPending = false;
    final actionCount = fixture.actions.length;
    expect((await fixture.repository.recover()).status, 'pending');
    expect(fixture.actions.skip(actionCount), ['get_photos']);
    expect(fixture.uploads, hasLength(2));
    expect(await fixture.repository.pending(), isNull);
  });

  test(
    'definite first prepare rejection clears pending and permits a new command',
    () async {
      final fixture = PhotoFixture()
        ..prepareError = const PostgrestException(
          message: '対象の写真が変更されています',
          code: 'P0001',
        );
      await expectLater(
        fixture.repository.submitSelection(
          row: fixture.row,
          photos: fixture.photos,
        ),
        throwsA(isA<PostgrestException>()),
      );
      expect(await fixture.repository.pending(), isNull);
      fixture.prepareError = null;
      expect(
        (await fixture.repository.submitSelection(
          row: fixture.row,
          photos: fixture.photos,
        )).status,
        'pending',
      );
    },
  );

  test(
    'missing or malformed capability keeps submission and uploads disabled',
    () {
      for (final raw in [
        null,
        {},
        {'version': 0},
        {
          'version': 1,
          'photo_submission_available': true,
          'photo_upload_allowed': true,
          'max_photos': 21,
        },
      ]) {
        final cap = OwnQualificationPhotoCapability.parse(raw);
        expect(cap.available, false);
        expect(cap.uploadAllowed, false);
      }
      final cap = OwnQualificationPhotoCapability.parse({
        'version': 1,
        'photo_submission_available': true,
        'photo_upload_allowed': false,
        'max_photos': 20,
      });
      expect(cap.available, true);
      expect(cap.uploadAllowed, false);
    },
  );

  test(
    'lost submit response proves pending through get without another upload',
    () async {
      final fixture = PhotoFixture()..loseSubmitResponse = true;
      final result = await fixture.repository.submitSelection(
        row: fixture.row,
        photos: fixture.photos,
      );
      expect(result.status, 'pending');
      expect(fixture.uploads, hasLength(2));
      expect(fixture.actions, [
        'photo_capability',
        'prepare_photos',
        'submit',
        'get_photos',
      ]);
      expect(await fixture.repository.pending(), isNull);
      expect(fixture.commands.single['request_id'], result.id);
    },
  );

  test('partial upload retains fixed request and cancellation proof permits a new request', () async {
    final fixture = PhotoFixture()..failUploadAt = 2;
    await expectLater(
      fixture.repository.submitSelection(
        row: fixture.row,
        photos: fixture.photos,
      ),
      throwsStateError,
    );
    final pending = await fixture.repository.pending();
    expect(pending, isNotNull);
    final id = pending!['request_id'];
    await expectLater(fixture.repository.recover(), throwsStateError);
    expect(fixture.uploads, hasLength(2));
    expect((await fixture.repository.pending())!['request_id'], id);
    final cancelled = await fixture.repository.cancelDraft();
    expect(cancelled.cancelled, true);
    expect(await fixture.repository.pending(), isNull);
    fixture.failUploadAt = null;
    final next = await fixture.repository.submitSelection(
      row: fixture.row,
      photos: fixture.photos,
    );
    expect(next.id, isNot(id));
    expect(next.status, 'pending');
  });

  test(
    'prepare response loss repeats the fixed command without uploading',
    () async {
      final fixture = PhotoFixture()..losePrepareResponse = true;
      await expectLater(
        fixture.repository.submitSelection(
          row: fixture.row,
          photos: fixture.photos,
        ),
        throwsStateError,
      );
      final command = await fixture.repository.pending();
      await expectLater(fixture.repository.recover(), throwsStateError);
      expect(fixture.commands, hasLength(2));
      expect(fixture.commands[0], fixture.commands[1]);
      expect(fixture.commands[0]['request_id'], command!['request_id']);
      expect(fixture.uploads, isEmpty);
      expect((await fixture.repository.cancelDraft()).cancelled, true);
    },
  );

  test(
    'account switch after prepare stops before uploading or submitting',
    () async {
      final fixture = PhotoFixture()..switchAfterPrepare = true;
      await expectLater(
        fixture.repository.submitSelection(
          row: fixture.row,
          photos: fixture.photos,
        ),
        throwsStateError,
      );
      expect(fixture.uploads, isEmpty);
      expect(fixture.actions, ['photo_capability', 'prepare_photos']);
      fixture.actor = 'user';
      expect(await fixture.repository.pending(), isNotNull);
    },
  );

  test('unknown cancellation does not clear local pending proof', () async {
    final fixture = PhotoFixture()..failUploadAt = 1;
    await expectLater(
      fixture.repository.submitSelection(
        row: fixture.row,
        photos: fixture.photos,
      ),
      throwsStateError,
    );
    fixture.loseGetAfterCancel = true;
    await expectLater(fixture.repository.cancelDraft(), throwsStateError);
    expect(await fixture.repository.pending(), isNotNull);
    fixture.loseGetAfterCancel = false;
    expect((await fixture.repository.recover()).cancelled, true);
    expect(await fixture.repository.pending(), isNull);
  });

  test('legacy RPC unsupported capability alone is unavailable; permission error propagates', () async {
    final fixture = PhotoFixture();
    fixture.capabilityError = const PostgrestException(
      message: '申請が見つかりません',
      code: 'P0001',
    );
    expect((await fixture.repository.capability()).available, false);
    fixture.capabilityError = const PostgrestException(
      message: 'permission denied',
      code: '42501',
    );
    await expectLater(
      fixture.repository.capability(),
      throwsA(isA<PostgrestException>()),
    );
  });
}

class PhotoFixture {
  String actor = 'user';
  bool loseSubmitResponse = false;
  bool loseGetPending = false;
  bool losePrepareResponse = false;
  bool switchAfterPrepare = false;
  bool loseGetAfterCancel = false;
  int? failUploadAt;
  Object? capabilityError;
  Object? prepareError;
  final actions = <String>[];
  final uploads = <String>[];
  final successfulUploads = <String>{};
  final commands = <Map<String, dynamic>>[];
  final requests = <String, Map<String, dynamic>>{};
  final row = <String, dynamic>{
    'id': 'target',
    'worker_id': 'worker',
    'attachment_path': 'legacy.pdf',
  };
  List<WorkerDocumentPhoto> get photos => [
    WorkerDocumentPhoto.pending(Uint8List.fromList([1]), 'front.jpg'),
    WorkerDocumentPhoto.pending(Uint8List.fromList([2]), 'back.png'),
    const WorkerDocumentPhoto.saved('legacy.pdf'),
  ];
  late final repository = OwnQualificationPhotoSubmissionRepository.forTesting(
    actor: () => actor,
    scope: () async =>
        (userId: actor, companyId: 'company', workerId: 'worker'),
    rpc: rpc,
    upload: (path, bytes, options) async {
      expect(options.upsert, false);
      uploads.add(path);
      if (uploads.length == failUploadAt) {
        throw StateError('upload interrupted');
      }
      successfulUploads.add(path);
    },
  );
  Future<Object?> rpc(String action, Map<String, dynamic> data) async {
    actions.add(action);
    if (action == 'photo_capability') {
      if (capabilityError != null) throw capabilityError!;
      return {
        'version': 1,
        'photo_submission_available': true,
        'photo_upload_allowed': true,
        'max_photos': 20,
      };
    }
    if (action == 'prepare_photos') {
      if (prepareError != null) throw prepareError!;
      commands.add(Map<String, dynamic>.from(data));
      final id = data['request_id'] as String;
      requests.putIfAbsent(id, () {
        final slots = List<Map<String, dynamic>>.from(
          data['photo_slots'] as List,
        );
        final paths = <String>[];
        final uploadPaths = <Map<String, dynamic>>[];
        for (var i = 0; i < slots.length; i++) {
          if (slots[i]['existing_path'] != null) {
            paths.add(slots[i]['existing_path'] as String);
          } else {
            final ext = slots[i]['extension'];
            final path = 'company/worker/target/submissions/$id-${i + 1}.$ext';
            paths.add(path);
            uploadPaths.add({'index': i, 'path': path, 'extension': ext});
          }
        }
        return {
          'version': 1,
          'id': id,
          'target_id': 'target',
          'requested_by': 'user',
          'photo_paths': paths,
          'upload_paths': uploadPaths,
          'status': 'draft',
          'cancelled': false,
        };
      });
      if (switchAfterPrepare) actor = 'other';
      if (losePrepareResponse) {
        losePrepareResponse = false;
        throw StateError('prepare response lost');
      }
      return requests[id];
    }
    final request = requests[data['id']]!;
    if (action == 'submit') {
      if ((request['upload_paths'] as List).any(
        (entry) => !successfulUploads.contains(entry['path']),
      )) {
        throw StateError('missing files');
      }
      request['status'] = 'pending';
      if (loseSubmitResponse) {
        loseSubmitResponse = false;
        throw StateError('submit response lost');
      }
    }
    if (action == 'cancel_photos') {
      request['status'] = 'rejected';
      request['cancelled'] = true;
    }
    if (action == 'get_photos' &&
        request['status'] == 'pending' &&
        loseGetPending) {
      throw StateError('get response lost');
    }
    if (action == 'get_photos' &&
        request['cancelled'] == true &&
        loseGetAfterCancel) {
      throw StateError('unknown result');
    }
    return Map<String, dynamic>.from(request);
  }
}
