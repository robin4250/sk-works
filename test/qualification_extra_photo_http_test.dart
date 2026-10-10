import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/qualifications/qualification_certificate_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _company = '10000000-0000-0000-0000-000000000001';
const _actor = '10000000-0000-0000-0000-000000000002';
const _worker = '10000000-0000-0000-0000-000000000003';
const _status = '10000000-0000-0000-0000-000000000005';

class _Fixture {
  late HttpServer server;
  late SupabaseClient client;
  final requests = <({String method, Uri uri, List<int> body})>[];
  bool rejectUpload = false;
  bool loseStatusResponse = false;
  bool noStatusRow = false;

  Future<void> start() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen(_respond);
    client = SupabaseClient(
      'http://127.0.0.1:${server.port}',
      'synthetic-anon-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    await client.auth.signInWithPassword(
      email: 'fixture@example.test',
      password: 'synthetic-password',
    );
    requests.clear();
  }

  Future<void> close() async {
    await client.dispose();
    await server.close(force: true);
  }

  Future<void> _respond(HttpRequest request) async {
    final body = await request.fold<List<int>>(
      [],
      (result, next) => result..addAll(next),
    );
    requests.add((method: request.method, uri: request.uri, body: body));
    final path = request.uri.path;
    Object? response;
    if (path == '/auth/v1/token') {
      String encode(Object value) =>
          base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
      final token =
          '${encode({'alg': 'HS256', 'typ': 'JWT'})}.${encode({'sub': _actor, 'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600})}.c3ludGhldGlj';
      response = {
        'access_token': token,
        'refresh_token': 'synthetic-refresh',
        'token_type': 'bearer',
        'expires_in': 3600,
        'user': {
          'id': _actor,
          'aud': 'authenticated',
          'role': 'authenticated',
          'email': 'fixture@example.test',
          'app_metadata': <String, dynamic>{},
          'user_metadata': <String, dynamic>{},
          'created_at': '2026-01-01T00:00:00Z',
        },
      };
    } else if (path == '/rest/v1/rpc/current_feature_permissions') {
      response = {'can_manage_people': true};
    } else if (path == '/rest/v1/company_members') {
      response = [
        {'company_id': _company},
      ];
    } else if (path == '/rest/v1/worker_qualifications') {
      if (request.method == 'GET') {
        final row = {
          'id': _status,
          'worker_id': _worker,
          'attachment_path': 'front.jpg',
          'attachment_back_path': 'back.jpg',
          'attachment_extra_paths': ['extra.jpg'],
        };
        response = request.uri.queryParameters.containsKey('limit')
            ? [row]
            : row;
      } else if (loseStatusResponse) {
        final socket = await request.response.detachSocket(writeHeaders: false);
        socket.destroy();
        return;
      } else if (noStatusRow) {
        request.response.statusCode = 406;
        response = {
          'code': 'PGRST116',
          'message': 'No rows',
          'details': '',
          'hint': null,
        };
      } else {
        response = {
          'id': _status,
          'worker_id': _worker,
          'attachment_path': 'front.jpg',
          'attachment_back_path': 'back.jpg',
          ...jsonDecode(utf8.decode(body)) as Map<String, dynamic>,
        };
      }
    } else if (path.startsWith(
      '/storage/v1/object/qualification-certificates/',
    )) {
      if (rejectUpload) {
        request.response.statusCode = 403;
        response = {
          'statusCode': '403',
          'error': 'Forbidden',
          'message': 'new row violates row-level security policy',
        };
      } else {
        response = {
          'Key': path.substring('/storage/v1/object/'.length),
          'Id': _status,
        };
      }
    } else if (path == '/storage/v1/object/qualification-certificates' &&
        request.method == 'DELETE') {
      response = [];
    } else {
      request.response.statusCode = 404;
      response = {'message': 'unexpected synthetic request'};
    }
    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode(response));
    await request.response.close();
  }

  Future<Map<String, dynamic>> saveExtra({String? replacingPath}) =>
      QualificationCertificateRepository.forTesting(client)
          .uploadExtraCertificate(
            qualificationId: _status,
            workerId: _worker,
            bytes: Uint8List.fromList([1, 2, 3]),
            originalFilename: 'extra.jpg',
            replacingPath: replacingPath,
          );
}

void main() {
  late _Fixture fixture;
  setUp(() async {
    fixture = _Fixture();
    await fixture.start();
  });
  tearDown(() async {
    await fixture.close();
  });

  test('extra upload preserves front/back and previous extra path', () async {
    final updated = await fixture.saveExtra();
    expect(updated['attachment_path'], 'front.jpg');
    expect(updated['attachment_back_path'], 'back.jpg');
    expect(updated['attachment_extra_paths'], hasLength(2));
    expect((updated['attachment_extra_paths'] as List).first, 'extra.jpg');
    final write = fixture.requests.singleWhere((r) => r.method == 'PATCH');
    expect(write.uri.queryParameters['worker_id'], 'eq.$_worker');
    expect(
      write.uri.queryParameters['attachment_extra_paths'],
      'eq.{"extra.jpg"}',
    );
    expect(fixture.requests.where((r) => r.method == 'DELETE'), isEmpty);
  });
  test('Storage rejection does not write certificate metadata', () async {
    fixture.rejectUpload = true;
    await expectLater(fixture.saveExtra(), throwsA(isA<StorageException>()));
    expect(fixture.requests.where((r) => r.method == 'PATCH'), isEmpty);
    expect(fixture.requests.where((r) => r.method == 'DELETE'), isEmpty);
  });
  test('lost write response preserves every uploaded object', () async {
    fixture.loseStatusResponse = true;
    await expectLater(fixture.saveExtra(), throwsA(anything));
    expect(fixture.requests.where((r) => r.method == 'DELETE'), isEmpty);
  });
  test('conflicting update never deletes either photo', () async {
    fixture.noStatusRow = true;
    await expectLater(
      fixture.saveExtra(replacingPath: 'extra.jpg'),
      throwsA(isA<PostgrestException>()),
    );
    expect(fixture.requests.where((r) => r.method == 'DELETE'), isEmpty);
  });
  test('confirmed replacement preserves shared snapshot objects', () async {
    final updated = await fixture.saveExtra(replacingPath: 'extra.jpg');
    expect(updated['attachment_path'], 'front.jpg');
    expect(updated['attachment_back_path'], 'back.jpg');
    expect(updated['attachment_extra_paths'], hasLength(1));
    expect(fixture.requests.where((r) => r.method == 'DELETE'), isEmpty);
  });
  test('stale replacement stops before uploading', () async {
    await expectLater(
      fixture.saveExtra(replacingPath: 'missing.jpg'),
      throwsStateError,
    );
    expect(
      fixture.requests.where((r) => r.uri.path.startsWith('/storage/')),
      isEmpty,
    );
  });
}
