import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/people/company_submitted_document_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _company = '10000000-0000-0000-0000-000000000001';
const _actor = '10000000-0000-0000-0000-000000000002';
const _status = '10000000-0000-0000-0000-000000000005';

class _Fixture {
  late HttpServer server;
  late SupabaseClient client;
  final requests = <({String method, Uri uri, List<int> body})>[];
  bool rejectUpload = false;
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
    } else if (path == '/rest/v1/company_members') {
      response = [
        {'company_id': _company, 'role': 'admin'},
      ];
    } else if (path == '/rest/v1/company_required_documents') {
      if (request.method == 'GET') {
        response = {
          'id': _status,
          'attachment_path': '$_company/$_status/old.jpg',
          'attachment_paths': ['$_company/$_status/old.jpg'],
          'updated_at': '2026-01-01T00:00:00Z',
        };
      } else if (noStatusRow) {
        request.response.statusCode = 406;
        response = {'code': 'PGRST116', 'message': 'No matching row'};
      } else {
        response = {
          'id': _status,
          ...jsonDecode(utf8.decode(body)) as Map<String, dynamic>,
        };
      }
    } else if (path.startsWith(
      '/storage/v1/object/company-required-documents/',
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
    } else {
      request.response.statusCode = 404;
      response = {'message': 'unexpected synthetic request'};
    }
    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode(response));
    await request.response.close();
  }

  List<({String method, Uri uri, List<int> body})> get writes => requests
      .where(
        (r) =>
            r.uri.path == '/rest/v1/company_required_documents' &&
            r.method != 'GET',
      )
      .toList();

  Future<Map<String, dynamic>> savePhoto() =>
      CompanySubmittedDocumentRepository.forTesting(client).savePhotos(
        id: _status,
        retainedPaths: ['$_company/$_status/old.jpg'],
        files: [
          (
            bytes: Uint8List.fromList([1, 2]),
            filename: 'front.jpg',
            contentType: 'image/jpeg',
          ),
          (
            bytes: Uint8List.fromList([3, 4]),
            filename: 'back.jpg',
            contentType: 'image/jpeg',
          ),
        ],
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
  test('uploads the full set before one confirmed row write, preserving legacy first photo', () async {
    final saved = await fixture.savePhoto();
    expect(saved['attachment_paths'], hasLength(3));
    expect(saved['attachment_path'], '$_company/$_status/old.jpg');
    expect(fixture.writes, hasLength(1));
    expect(
      fixture.requests.where(
        (r) => r.uri.path.startsWith('/storage/v1/object/'),
      ),
      hasLength(2),
    );
    expect(fixture.requests.where((r) => r.method == 'DELETE'), isEmpty);
  });
  test(
    'upload failure never mutates the saved set or deletes objects',
    () async {
      fixture.rejectUpload = true;
      await expectLater(fixture.savePhoto(), throwsA(isA<StorageException>()));
      expect(fixture.writes, isEmpty);
      expect(fixture.requests.where((r) => r.method == 'DELETE'), isEmpty);
    },
  );
  test('unconfirmed row update never deletes uploaded or old photos', () async {
    fixture.noStatusRow = true;
    await expectLater(fixture.savePhoto(), throwsA(isA<PostgrestException>()));
    expect(fixture.requests.where((r) => r.method == 'DELETE'), isEmpty);
  });
}
