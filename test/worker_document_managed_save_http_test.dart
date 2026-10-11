import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/people/worker_document_repository.dart';
import 'package:sk_works/features/people/worker_document_photos.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const company = '10000000-0000-0000-0000-000000000001';
const actor = '10000000-0000-0000-0000-000000000002';
const worker = '10000000-0000-0000-0000-000000000003';
const requirement = '10000000-0000-0000-0000-000000000004';
const statusId = '10000000-0000-0000-0000-000000000005';
const savedPath = '$company/$worker/$requirement/$statusId/old.jpg';

class Fixture {
  late HttpServer server;
  late SupabaseClient client;
  String role = 'admin';
  bool foreignWorker = false,
      uploadDenied = false,
      casConflict = false,
      switchActor = false,
      switchActorDuringStatusRead = false;
  Map<String, dynamic>? existing;
  Map<String, dynamic>? saved;
  final requests = <({String method, Uri uri, List<int> bytes})>[];
  Future<void> start() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final bytes = await request.fold<List<int>>([], (a, b) => a..addAll(b));
      requests.add((method: request.method, uri: request.uri, bytes: bytes));
      Object? response;
      if (request.uri.path == '/auth/v1/token') {
        String encode(Object value) => base64Url
            .encode(utf8.encode(jsonEncode(value)))
            .replaceAll('=', '');
        response = {
          'access_token':
              '${encode({'alg': 'HS256'})}.${encode({'sub': actor, 'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600})}.fixture',
          'refresh_token': 'fixture',
          'token_type': 'bearer',
          'expires_in': 3600,
          'user': {
            'id': actor,
            'aud': 'authenticated',
            'role': 'authenticated',
            'email': 'fixture@example.test',
            'app_metadata': {},
            'user_metadata': {},
            'created_at': '2026-01-01T00:00:00Z',
          },
        };
      } else if (request.uri.path == '/auth/v1/logout') {
        response = {};
      } else if (request.uri.path == '/rest/v1/company_members') {
        response = [
          {'company_id': company, 'role': role},
        ];
      } else if (request.uri.path == '/rest/v1/workers') {
        response = foreignWorker
            ? []
            : [
                {'id': worker, 'company_id': company, 'status': 'active'},
              ];
      } else if (request.uri.path == '/rest/v1/document_requirements') {
        response = [
          {'id': requirement, 'company_id': company, 'is_active': true},
        ];
      } else if (request.uri.path == '/rest/v1/worker_document_statuses') {
        if (request.method == 'GET') {
          if (switchActorDuringStatusRead) {
            await client.auth.signOut(scope: SignOutScope.local);
          }
          response = existing == null ? [] : [existing];
        } else if (casConflict) {
          request.response.statusCode = 406;
          response = {'code': 'PGRST116', 'message': 'No matching row'};
        } else {
          saved = {
            ...jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>,
            'id': statusId,
          };
          response = saved;
        }
      } else if (request.uri.path.startsWith(
        '/storage/v1/object/worker-documents/',
      )) {
        if (uploadDenied) {
          request.response.statusCode = 403;
          response = {'error': 'Unauthorized', 'message': 'upload denied'};
        } else {
          if (switchActor) {
            await client.auth.signOut(scope: SignOutScope.local);
          }
          response = {'Key': 'worker-documents/fixture'};
        }
      } else {
        request.response.statusCode = 500;
        response = {'message': 'Unexpected request'};
      }
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode(response));
      await request.response.close();
    });
    client = SupabaseClient(
      'http://127.0.0.1:${server.port}',
      'fixture',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    await client.auth.signInWithPassword(
      email: 'fixture@example.test',
      password: 'fixture',
    );
    requests.clear();
  }

  Future<void> close() async {
    await client.dispose();
    await server.close(force: true);
  }

  Future<void> save(
    List<WorkerDocumentPhoto> photos, {
    Map<String, dynamic>? expected,
  }) => WorkerDocumentRepository.forTesting(client).saveManagedDocumentPhotos(
    workerId: worker,
    requirementId: requirement,
    status: 'submitted',
    originalVerified: false,
    notes: 'registered',
    photos: photos,
    expectedRow: expected,
  );
  List<({String method, Uri uri, List<int> bytes})> get mutations => requests
      .where(
        (r) =>
            r.method != 'GET' &&
            (r.uri.path.startsWith('/rest/v1/') ||
                r.uri.path.startsWith('/storage/v1/')),
      )
      .toList();
}

void main() {
  test('status-only actor change during read prevents writes', () async {
    final f = Fixture()..switchActorDuringStatusRead = true;
    await f.start();
    try {
      await expectLater(
        WorkerDocumentRepository.forTesting(f.client).updateStatus(
          workerId: worker,
          requirementId: requirement,
          status: 'submitted',
          originalVerified: false,
          notes: '',
        ),
        throwsA(isA<StateError>()),
      );
      expect(f.saved, isNull);
      expect(f.mutations, isEmpty);
      final read = f.requests.singleWhere(
        (r) => r.uri.path == '/rest/v1/worker_document_statuses',
      );
      expect(read.uri.queryParameters['company_id'], 'eq.$company');
    } finally {
      await f.close();
    }
  });

  for (final role in ['owner', 'admin', 'manager']) {
    test(
      '$role registers another company worker with all photos in one row',
      () async {
        final f = Fixture()..role = role;
        await f.start();
        try {
          await f.save([
            WorkerDocumentPhoto.pending(Uint8List.fromList([1]), 'front.jpg'),
            WorkerDocumentPhoto.pending(Uint8List.fromList([2]), 'back.jpg'),
          ]);
          expect(f.saved!['worker_id'], worker);
          expect(f.saved!['attachment_paths'], hasLength(2));
          expect(
            f.saved!['attachment_path'],
            (f.saved!['attachment_paths'] as List).first,
          );
          expect(
            f.requests.where(
              (r) =>
                  r.method == 'POST' &&
                  r.uri.path == '/rest/v1/worker_document_statuses',
            ),
            hasLength(1),
          );
          expect(f.requests.where((r) => r.method == 'DELETE'), isEmpty);
          for (final r in f.requests.where(
            (r) => r.uri.path.startsWith('/rest/v1/'),
          )) {
            if (r.uri.path.endsWith('/workers') ||
                r.uri.path.endsWith('/document_requirements')) {
              expect(r.uri.queryParameters['company_id'], 'eq.$company');
            }
          }
        } finally {
          await f.close();
        }
      },
    );
  }
  test(
    'existing photos keep mixed draft order and use updated_at CAS',
    () async {
      final row = {
        'id': statusId,
        'updated_at': '2026-10-11T00:00:00Z',
        'attachment_path': savedPath,
        'attachment_paths': [savedPath],
      };
      final f = Fixture()..existing = row;
      await f.start();
      try {
        await f.save([
          WorkerDocumentPhoto.pending(Uint8List.fromList([2]), 'front.jpg'),
          const WorkerDocumentPhoto.saved(savedPath),
        ], expected: row);
        expect((f.saved!['attachment_paths'] as List)[1], savedPath);
        final write = f.requests.singleWhere((r) => r.method == 'PATCH');
        expect(
          write.uri.queryParameters['updated_at'],
          'eq.${row['updated_at']}',
        );
        expect(write.uri.queryParameters['company_id'], 'eq.$company');
        expect(f.requests.where((r) => r.method == 'DELETE'), isEmpty);
      } finally {
        await f.close();
      }
    },
  );
  for (final failure in [
    'foreign worker',
    'viewer',
    'upload denied',
    'CAS conflict',
    'stale screen',
    'actor changed',
  ]) {
    test(
      '$failure does not report registration or delete saved photos',
      () async {
        final row = {
          'id': statusId,
          'updated_at': '2026-10-11T00:00:00Z',
          'attachment_path': savedPath,
          'attachment_paths': [savedPath],
        };
        final f = Fixture()
          ..foreignWorker = failure == 'foreign worker'
          ..role = failure == 'viewer' ? 'viewer' : 'admin'
          ..uploadDenied = failure == 'upload denied'
          ..casConflict = failure == 'CAS conflict'
          ..switchActor = failure == 'actor changed';
        if (failure == 'CAS conflict' || failure == 'stale screen') {
          f.existing = row;
        }
        await f.start();
        try {
          await expectLater(
            f.save([
              WorkerDocumentPhoto.pending(Uint8List.fromList([1]), 'new.jpg'),
            ], expected: failure == 'CAS conflict' ? row : null),
            throwsA(anything),
          );
          expect(f.saved, isNull);
          expect(f.requests.where((r) => r.method == 'DELETE'), isEmpty);
          if (['foreign worker', 'viewer', 'stale screen'].contains(failure)) {
            expect(f.mutations, isEmpty);
          }
          if (failure == 'upload denied' || failure == 'actor changed') {
            expect(
              f.requests.where(
                (r) =>
                    r.uri.path == '/rest/v1/worker_document_statuses' &&
                    r.method != 'GET',
              ),
              isEmpty,
            );
          }
        } finally {
          await f.close();
        }
      },
    );
  }
}
