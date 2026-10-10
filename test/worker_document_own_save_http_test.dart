import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/people/worker_document_repository.dart';
import 'package:sk_works/features/people/worker_document_photos.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _company = '10000000-0000-0000-0000-000000000001';
const _actor = '10000000-0000-0000-0000-000000000002';
const _worker = '10000000-0000-0000-0000-000000000003';
const _requirement = '10000000-0000-0000-0000-000000000004';
const _status = '10000000-0000-0000-0000-000000000005';

class _Fixture {
  late HttpServer server;
  late SupabaseClient client;
  final requests = <({String method, Uri uri, List<int> body})>[];
  bool existingStatus = true;
  bool rejectUpload = false;
  bool loseStatusResponse = false;
  bool noStatusRow = false;
  bool echoPhotos = false;
  int? rejectUploadNumber;
  int uploads = 0;
  Map<String, dynamic>? savedPhotos;

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
    } else if (path == '/rest/v1/rpc/ensure_current_user_worker') {
      response = _worker;
    } else if (path == '/rest/v1/company_members') {
      response = [
        {'company_id': _company, 'role': 'admin'},
      ];
    } else if (path == '/rest/v1/workers') {
      response = [
        {'id': _worker, 'name': 'synthetic worker', 'status': 'active'},
      ];
    } else if (path == '/rest/v1/document_requirements') {
      response = [
        {'id': _requirement, 'name': 'synthetic license', 'is_active': true},
      ];
    } else if (path == '/rest/v1/worker_document_statuses') {
      if (request.method == 'GET') {
        response = existingStatus
            ? [
                {
                  'id': _status,
                  'worker_id': _worker,
                  'requirement_id': _requirement,
                  'attachment_path': 'synthetic/old.jpg',
                  'updated_at': '2026-10-11T00:00:00Z',
                  ...?savedPhotos,
                },
              ]
            : [];
      } else if (loseStatusResponse) {
        // The server may have accepted the write; client confirmation is lost.
        final socket = await request.response.detachSocket(writeHeaders: false);
        socket.destroy();
        return;
      } else if (noStatusRow) {
        request.response.statusCode = 406;
        response = {
          'code': 'PGRST116',
          'message': 'JSON object requested, multiple (or no) rows returned',
          'details': 'The result contains 0 rows',
          'hint': null,
        };
      } else {
        response = echoPhotos
            ? {
                'id': _status,
                ...jsonDecode(utf8.decode(body)) as Map<String, dynamic>,
              }
            : {'id': _status};
        if (echoPhotos) {
          savedPhotos = Map<String, dynamic>.from(response as Map);
        }
      }
    } else if (path.startsWith('/storage/v1/object/worker-documents/')) {
      uploads++;
      if (rejectUpload || uploads == rejectUploadNumber) {
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
            r.uri.path == '/rest/v1/worker_document_statuses' &&
            r.method != 'GET',
      )
      .toList();

  Future<void> savePhoto() =>
      WorkerDocumentRepository.forTesting(client).saveOwnDocument(
        requirementId: _requirement,
        notes: 'synthetic note',
        attachmentBytes: Uint8List.fromList([1, 2, 3]),
        originalFilename: 'license.jpg',
      );
}

void main() {
  // Ordinary unit tests: no widget binding and no global test HttpClient override.
  late _Fixture fixture;
  setUp(() async {
    fixture = _Fixture();
    await fixture.start();
  });
  tearDown(() async {
    await fixture.close();
  });

  Future<void> savePhotos() =>
      WorkerDocumentRepository.forTesting(fixture.client).saveOwnDocumentPhotos(
        requirementId: _requirement,
        notes: 'multi-photo',
        expectedPaths: ['synthetic/old.jpg'],
        photos: [
          const WorkerDocumentPhoto.saved('synthetic/old.jpg'),
          WorkerDocumentPhoto.pending(Uint8List.fromList([1, 2]), 'back.jpg'),
          WorkerDocumentPhoto.pending(Uint8List.fromList([3, 4]), 'extra.jpg'),
        ],
      );

  test('all photos upload before one confirmed write and reload retains every path', () async {
    fixture.echoPhotos = true;
    await savePhotos();
    expect(fixture.uploads, 2);
    final loaded = await WorkerDocumentRepository.forTesting(fixture.client)
        .loadOwnDocuments();
    expect(workerDocumentPaths(loaded['statuses']!.single), hasLength(3));
    expect(fixture.writes, hasLength(1));
    final payload = jsonDecode(
      utf8.decode(fixture.writes.single.body),
    ) as Map<String, dynamic>;
    final paths = workerDocumentPaths(payload);
    expect(paths, hasLength(3));
    expect(paths.first, 'synthetic/old.jpg');
    expect(paths[1], endsWith('.jpg'));
    expect(paths.toSet(), hasLength(3));
    expect(payload['attachment_path'], paths.first);
    final writeIndex = fixture.requests.indexOf(fixture.writes.single);
    expect(
      fixture.requests
          .take(writeIndex)
          .where((r) => r.uri.path.startsWith('/storage/')),
      hasLength(2),
    );
    expect(fixture.requests.where((r) => r.method == 'DELETE'), isEmpty);
  });

  test('second photo rejection preserves old and uncertain objects without status write', () async {
    fixture.rejectUploadNumber = 2;
    await expectLater(savePhotos(), throwsA(isA<StorageException>()));
    expect(fixture.uploads, 2);
    expect(fixture.writes, isEmpty);
    expect(fixture.requests.where((r) => r.method == 'DELETE'), isEmpty);
  });

  test('multi-photo lost confirmation performs no cleanup', () async {
    fixture.loseStatusResponse = true;
    await expectLater(savePhotos(), throwsA(anything));
    expect(fixture.uploads, 2);
    expect(fixture.writes, hasLength(1));
    expect(fixture.requests.where((r) => r.method == 'DELETE'), isEmpty);
  });

  test('unconfirmed photo list is not treated as successful save', () async {
    await expectLater(savePhotos(), throwsStateError);
    expect(fixture.requests.where((r) => r.method == 'DELETE'), isEmpty);
  });

  test('changed current photos reject stale draft before uploading', () async {
    await expectLater(
      WorkerDocumentRepository.forTesting(fixture.client).saveOwnDocumentPhotos(
        requirementId: _requirement,
        notes: '',
        expectedPaths: [],
        photos: [
          WorkerDocumentPhoto.pending(Uint8List.fromList([1]), 'new.jpg'),
        ],
      ),
      throwsStateError,
    );
    expect(fixture.uploads, 0);
    expect(fixture.writes, isEmpty);
  });

  test('Storage 403 is propagated before any submitted status write', () async {
    fixture.rejectUpload = true;
    await expectLater(fixture.savePhoto(), throwsA(isA<StorageException>()));
    expect(fixture.writes, isEmpty);
    expect(fixture.requests.where((r) => r.method == 'DELETE'), isEmpty);
    expect(
      fixture.requests.where(
        (r) => r.uri.path.startsWith('/storage/v1/object/'),
      ),
      hasLength(1),
    );
  });

  test(
    'upload precedes confirmed update and old object is never deleted',
    () async {
      await fixture.savePhoto();
      final upload = fixture.requests.indexWhere(
        (r) => r.uri.path.startsWith('/storage/v1/object/'),
      );
      final write = fixture.requests.indexWhere(
        (r) =>
            r.uri.path == '/rest/v1/worker_document_statuses' &&
            r.method == 'PATCH',
      );
      expect(upload, greaterThanOrEqualTo(0));
      expect(write, greaterThan(upload));
      expect(fixture.requests.where((r) => r.method == 'DELETE'), isEmpty);
      final payload = jsonDecode(
        utf8.decode(fixture.writes.single.body),
      ) as Map<String, dynamic>;
      expect(
        payload['attachment_path'],
        startsWith('$_company/$_worker/$_requirement/$_status/'),
      );
      expect(payload['status'], 'submitted');
      expect(
        fixture.writes.single.uri.queryParameters['company_id'],
        'eq.$_company',
      );
      expect(
        fixture.writes.single.uri.queryParameters['worker_id'],
        'eq.$_worker',
      );
      expect(
        fixture.writes.single.uri.queryParameters['requirement_id'],
        'eq.$_requirement',
      );
      expect(fixture.writes.single.uri.queryParameters['id'], 'eq.$_status');
    },
  );

  test('lost status confirmation preserves the uploaded object', () async {
    fixture.loseStatusResponse = true;
    await expectLater(fixture.savePhoto(), throwsA(anything));
    expect(fixture.writes, hasLength(1));
    expect(fixture.requests.where((r) => r.method == 'DELETE'), isEmpty);
  });

  test('new status is inserted only after upload succeeds', () async {
    fixture.existingStatus = false;
    await fixture.savePhoto();
    final upload = fixture.requests.indexWhere(
      (r) => r.uri.path.startsWith('/storage/v1/object/'),
    );
    final write = fixture.requests.indexWhere(
      (r) =>
          r.uri.path == '/rest/v1/worker_document_statuses' &&
          r.method == 'POST',
    );
    expect(write, greaterThan(upload));
    final payload = jsonDecode(
      utf8.decode(fixture.writes.single.body),
    ) as Map<String, dynamic>;
    expect(
      payload['attachment_path'],
      startsWith('$_company/$_worker/$_requirement/own-upload/'),
    );
    expect(fixture.requests.where((r) => r.method == 'DELETE'), isEmpty);
  });

  test(
    'metadata-only zero-row response is not a successful registration',
    () async {
      fixture.noStatusRow = true;
      await expectLater(
        WorkerDocumentRepository.forTesting(
          fixture.client,
        ).saveOwnDocument(requirementId: _requirement, notes: 'metadata only'),
        throwsA(isA<PostgrestException>()),
      );
      expect(fixture.writes, hasLength(1));
      expect(
        fixture.requests.where((r) => r.uri.path.startsWith('/storage/')),
        isEmpty,
      );
      expect(
        fixture.writes.single.uri.queryParameters['worker_id'],
        'eq.$_worker',
      );
    },
  );

  test(
    'own document loading scopes even an administrator to their worker',
    () async {
      final result = await WorkerDocumentRepository.forTesting(fixture.client)
          .loadOwnDocuments();
      expect(result['workers']!.single['id'], _worker);
      final workers = fixture.requests.singleWhere(
        (r) =>
            r.uri.path == '/rest/v1/workers' &&
            r.uri.queryParameters['select'] != 'name',
      );
      final statuses = fixture.requests.singleWhere(
        (r) => r.uri.path == '/rest/v1/worker_document_statuses',
      );
      final requirements = fixture.requests.singleWhere(
        (r) => r.uri.path == '/rest/v1/document_requirements',
      );
      expect(workers.uri.queryParameters['company_id'], 'eq.$_company');
      expect(workers.uri.queryParameters['id'], 'eq.$_worker');
      expect(statuses.uri.queryParameters['company_id'], 'eq.$_company');
      expect(statuses.uri.queryParameters['worker_id'], 'eq.$_worker');
      expect(requirements.uri.queryParameters['company_id'], 'eq.$_company');
      expect(requirements.uri.queryParameters['is_active'], 'eq.true');
    },
  );
}
