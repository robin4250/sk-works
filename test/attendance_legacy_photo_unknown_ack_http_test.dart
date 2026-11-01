import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sk_works/features/attendance/attendance_shift_context.dart';
import 'package:sk_works/features/attendance/attendance_verification_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _actor = '11111111-1111-4111-8111-111111111111';
const _otherActor = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const _company = '22222222-2222-4222-8222-222222222222';
const _worker = '33333333-3333-4333-8333-333333333333';
const _site = '44444444-4444-4444-8444-444444444444';
const _source = '55555555-5555-4555-8555-555555555555';
const _saved = '66666666-6666-4666-8666-666666666666';
final _photo = Uint8List.fromList(utf8.encode('immutable-original-photo-fixture'));

enum _Reply { lostAcknowledgement, rejected, success, actorAfterCommit, actorAfterUpload }

class _Harness {
  _Harness(this.reply) {
    client = SupabaseClient(
      'https://attendance.example.test',
      'fixture-public-key',
      httpClient: MockClient(_handle),
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    repository = AttendanceVerificationRepository.forTesting(client);
  }

  final _Reply reply;
  late final SupabaseClient client;
  late final AttendanceVerificationRepository repository;
  final objects = <String, Uint8List>{};
  Map<String, dynamic>? committed;
  Map<String, dynamic>? insertedPayload;
  String? uploadedPath;
  var inserts = 0;
  var uploads = 0;
  var deletes = 0;
  var uploadContainsOriginal = false;
  final calls = <String>[];

  Future<void> signIn([String actor = _actor]) =>
      client.auth.signInWithPassword(
        email: actor == _actor ? 'actor@example.test' : 'other@example.test',
        password: 'fixture-only',
      ).then((_) {});

  http.Response _json(Object? value, [int status = 200]) => http.Response(
      jsonEncode(value), status, headers: {'content-type': 'application/json'});

  String _token(String actor) {
    String part(Object value) =>
        base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
    return '${part({'alg': 'HS256'})}.${part({
      'sub': actor,
      'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600,
    })}.fixture-signature';
  }

  Future<http.Response> _handle(http.Request request) async {
    final path = request.url.path;
    calls.add('${request.method} $path');
    if (path == '/auth/v1/token') {
      final body = jsonDecode(request.body) as Map;
      final actor = body['email'] == 'other@example.test' ? _otherActor : _actor;
      return _json({
        'access_token': _token(actor), 'refresh_token': 'fixture-refresh',
        'expires_in': 3600, 'token_type': 'bearer',
        'user': {
          'id': actor, 'aud': 'authenticated', 'role': 'authenticated',
          'email': body['email'], 'created_at': '2026-01-01T00:00:00Z',
          'app_metadata': <String, Object?>{}, 'user_metadata': <String, Object?>{},
        },
      });
    }
    if (path == '/rest/v1/company_members' && request.method == 'GET') {
      expect(request.url.queryParameters['user_id'], 'eq.${client.auth.currentUser!.id}');
      return _json([{'company_id': _company}]);
    }
    if (path == '/rest/v1/work_vehicle_route_selections') {
      expect(request.method, 'GET');
      expect(request.url.queryParameters['company_id'], 'eq.$_company');
      expect(request.url.queryParameters['worker_id'], 'eq.$_worker');
      return _json([]);
    }
    const prefix = '/storage/v1/object/attendance-evidence/';
    if (path.startsWith(prefix) && request.method == 'POST') {
      uploads++;
      final object = Uri.decodeComponent(path.substring(prefix.length));
      expect(object, startsWith('$_company/attendance/$_site/$_worker/'));
      uploadedPath = object;
      uploadContainsOriginal = utf8.decode(request.bodyBytes, allowMalformed: true)
          .contains(utf8.decode(_photo));
      expect(uploadContainsOriginal, isTrue);
      objects[object] = Uint8List.fromList(_photo);
      if (reply == _Reply.actorAfterUpload) await signIn(_otherActor);
      return _json({'Key': 'attendance-evidence/$object'});
    }
    if (path == '/storage/v1/object/attendance-evidence' && request.method == 'DELETE') {
      deletes++;
      final body = jsonDecode(request.body) as Map;
      for (final key in body['prefixes'] as List) {
        objects.remove(key);
      }
      return _json([]);
    }
    if (path == '/rest/v1/attendance_verifications') {
      if (request.method == 'GET') {
        // Existing clock-out recovery stays result-only and exact-source scoped.
        expect(request.url.queryParameters['source_clock_in_id'], 'eq.$_source');
        expect(request.url.queryParameters['event_type'], 'eq.clock_out');
        return _json(committed == null ? [] : [committed]);
      }
      expect(request.method, 'POST');
      inserts++;
      final payload = Map<String, dynamic>.from(jsonDecode(request.body) as Map);
      insertedPayload = payload;
      expect(payload['company_id'], _company);
      expect(payload['worker_id'], _worker);
      expect(payload['site_id'], _site);
      expect(payload['created_by'], _actor);
      expect(payload['photo_storage_path'], uploadedPath);
      if (reply == _Reply.rejected) {
        return _json({'message': 'fixture definite rejection', 'code': '42501'}, 403);
      }
      committed = {
        ...payload, 'id': _saved, 'work_date': '2026-11-01',
        'confirmed_at': '2026-11-01T08:00:00Z',
      };
      if (reply == _Reply.lostAcknowledgement) {
        throw http.ClientException('fixture: committed response lost', request.url);
      }
      if (reply == _Reply.actorAfterCommit) await signIn(_otherActor);
      return _json(committed);
    }
    throw StateError('Unexpected synthetic request: ${request.method} $path');
  }

  Future<Map<String, dynamic>> save({bool clockOut = false, bool withPhoto = true}) =>
      repository.createVerification(
        workerId: _worker, siteId: _site,
        eventType: clockOut ? 'clock_out' : 'clock_in',
        verificationMode: withPhoto ? 'location_photo' : 'manual',
        latitude: withPhoto ? 35.0 : null,
        longitude: withPhoto ? 139.0 : null,
        accuracyM: withPhoto ? 5.0 : null,
        proximityStatus: 'near_site',
        photoBytes: withPhoto ? _photo : null,
        photoFilename: withPhoto ? 'original.jpg' : null,
        note: 'preserve original evidence',
        shift: clockOut ? AttendanceShiftContext(
          id: _source, workerId: _worker, workDate: DateTime(2026, 11, 1),
          clockIn: DateTime.utc(2026, 11, 1, 0), verificationMode: 'location_photo',
          siteId: _site,
        ) : null,
      );

  void expectOriginalRetained() {
    expect(uploads, 1);
    expect(deletes, 0);
    expect(uploadContainsOriginal, isTrue);
    expect(objects[uploadedPath], orderedEquals(_photo));
  }

  Future<void> close() => client.dispose();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('legacy clock-in commit then lost acknowledgement never deletes its photo', () async {
    final h = _Harness(_Reply.lostAcknowledgement);
    try {
      await h.signIn();
      await expectLater(h.save(), throwsA(anything));
      expect(h.inserts, 1);
      expect(h.committed?['id'], _saved);
      expect(h.committed?['photo_storage_path'], h.uploadedPath);
      h.expectOriginalRetained();
    } finally { await h.close(); }
  });

  test('post-insert definite rejection also retains photo for separate unused-object review', () async {
    final h = _Harness(_Reply.rejected);
    try {
      await h.signIn();
      await expectLater(h.save(), throwsA(isA<PostgrestException>()));
      expect(h.inserts, 1);
      expect(h.committed, isNull);
      h.expectOriginalRetained();
    } finally { await h.close(); }
  });

  test('ordinary successful clock-in keeps the original company path and saved payload', () async {
    final h = _Harness(_Reply.success);
    try {
      await h.signIn();
      final result = await h.save();
      expect(result, h.committed);
      expect(h.inserts, 1);
      expect(h.insertedPayload, {
        'company_id': _company, 'worker_id': _worker, 'site_id': _site,
        'event_type': 'clock_in', 'verification_mode': 'location_photo',
        'latitude': 35.0, 'longitude': 139.0, 'accuracy_m': 5.0,
        'distance_to_site_m': null, 'proximity_status': 'near_site',
        'photo_storage_path': h.uploadedPath, 'note': 'preserve original evidence',
        'vehicle_id': null, 'route_assignment_id': null, 'created_by': _actor,
      });
      h.expectOriginalRetained();
    } finally { await h.close(); }
  });

  test('actor change after committed insert denies success and retains the original', () async {
    final h = _Harness(_Reply.actorAfterCommit);
    try {
      await h.signIn();
      await expectLater(h.save(), throwsStateError);
      expect(h.inserts, 1);
      expect(h.committed?['created_by'], _actor);
      expect(h.client.auth.currentUser?.id, _otherActor);
      h.expectOriginalRetained();
    } finally { await h.close(); }
  });

  test('actor change during upload never inserts for the new actor or removes old photo', () async {
    final h = _Harness(_Reply.actorAfterUpload);
    try {
      await h.signIn();
      await expectLater(h.save(), throwsStateError);
      expect(h.inserts, 0);
      expect(h.committed, isNull);
      h.expectOriginalRetained();
    } finally { await h.close(); }
  });

  test('existing clock-out lost response recovers exact saved row without another insert', () async {
    final h = _Harness(_Reply.lostAcknowledgement);
    try {
      await h.signIn();
      final result = await h.save(clockOut: true);
      expect(result['id'], _saved);
      expect(result['source_clock_in_id'], _source);
      expect(h.inserts, 1);
      expect(h.calls.where((x) => x == 'GET /rest/v1/attendance_verifications'), hasLength(2));
      h.expectOriginalRetained();
    } finally { await h.close(); }
  });

  test('manual verification has no photo Storage side effects', () async {
    final h = _Harness(_Reply.success);
    try {
      await h.signIn();
      final result = await h.save(withPhoto: false);
      expect(result['photo_storage_path'], isNull);
      expect(h.uploads, 0);
      expect(h.deletes, 0);
      expect(h.objects, isEmpty);
      expect(h.inserts, 1);
    } finally { await h.close(); }
  });
}
