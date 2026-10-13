import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sk_works/features/qualifications/qualification_photo_submission_review_repository.dart';

void main() {
  late HttpServer server;
  late SupabaseClient client;
  late QualificationPhotoSubmissionReviewRepository repository;
  final actions = <String>[];
  String status = 'pending';
  bool loseMutation = false;
  bool wrongTarget = false;
  bool rejectCas = false;
  bool keepPending = false;
  bool switchActorOnList = false;
  String actor = 'actor';
  final row = <String, dynamic>{
    'id': 'request',
    'target_id': 'qualification',
    'requested_by': 'owner',
    'status': 'pending',
    'can_review': true,
    'photo_contract_version': 1,
  };
  setUp(() async {
    actions.clear();
    status = 'pending';
    loseMutation = false;
    wrongTarget = false;
    rejectCas = false;
    keepPending = false;
    switchActorOnList = false;
    actor = 'actor';
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final data = jsonDecode(await utf8.decoder.bind(request).join()) as Map;
      Object response;
      if (request.uri.path.startsWith('/auth/')) {
        String encode(Object value) => base64Url
            .encode(utf8.encode(jsonEncode(value)))
            .replaceAll('=', '');
        response = {
          'access_token':
              '${encode({'alg': 'HS256'})}.${encode({'sub': actor, 'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600})}.fake',
          'refresh_token': 'fake',
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
      } else {
        final action = data['p_action'] as String;
        actions.add(action);
        if (action == 'approve' || action == 'reject') {
          if (!keepPending && !(rejectCas && action == 'approve')) {
            status = action == 'approve' ? 'approved' : 'rejected';
          }
          if (rejectCas && action == 'approve') {
            request.response.statusCode = 400;
            response = {
              'code': 'P0001',
              'message': 'qualification has changed',
            };
          } else if (loseMutation) {
            request.response.statusCode = 503;
            response = {'message': 'response unavailable'};
          } else {
            response = <String, dynamic>{};
          }
        } else if (action == 'list') {
          if (switchActorOnList) {
            switchActorOnList = false;
            actor = 'another-actor';
            await client.auth.signInWithPassword(
              email: 'another@example.test',
              password: 'fake',
            );
          }
          response = [
            row,
            {...row, 'id': 'forbidden', 'can_review': false},
            {...row, 'id': 'finished', 'status': 'approved'},
          ];
        } else {
          response = {
            'version': 1,
            'id': 'request',
            'target_id': wrongTarget ? 'another' : 'qualification',
            'requested_by': 'owner',
            'status': status,
            'cancelled': false,
            'photo_paths': ['front.jpg', 'back.pdf', 'extra.jpg'],
          };
        }
      }
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode(response));
      await request.response.close();
    });
    client = SupabaseClient(
      'http://127.0.0.1:${server.port}',
      'fake-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    await client.auth.signInWithPassword(
      email: 'fixture@example.test',
      password: 'fake',
    );
    repository = QualificationPhotoSubmissionReviewRepository(client);
  });
  tearDown(() async {
    await client.dispose();
    await server.close(force: true);
  });
  test('pending list excludes nonreviewable and completed requests', () async {
    expect((await repository.pending()).map((r) => r['id']), ['request']);
  });
  test('all photos use exact same request proof and order', () async {
    expect(await repository.photos(row), [
      'front.jpg',
      'back.pdf',
      'extra.jpg',
    ]);
    wrongTarget = true;
    await expectLater(repository.photos(row), throwsStateError);
  });
  test(
    'lost approve response verifies terminal state without repeating mutation',
    () async {
      loseMutation = true;
      await repository.review(row, approve: true);
      expect(actions, ['approve', 'get_photos']);
    },
  );
  test('lost response with mismatched target stays uncertain', () async {
    loseMutation = true;
    wrongTarget = true;
    await expectLater(repository.review(row, approve: true), throwsStateError);
    expect(actions, ['approve', 'get_photos']);
  });
  test('reject requires a reason before RPC', () async {
    await expectLater(
      repository.review(row, approve: false, reason: '  '),
      throwsStateError,
    );
    expect(actions, isEmpty);
  });
  test('confirmed CAS rejection remains rejectable with a reason', () async {
    rejectCas = true;
    await expectLater(
      repository.review(row, approve: true),
      throwsA(
        isA<PostgrestException>().having(
          (error) => error.code,
          'code',
          'P0001',
        ),
      ),
    );
    await repository.review(
      row,
      approve: false,
      reason: 'newer saved qualification takes precedence',
    );
    expect(actions, ['approve', 'reject']);
    expect(status, 'rejected');
  });
  test(
    'unknown mutation reconciled as pending is not an uncertain lock',
    () async {
      loseMutation = true;
      keepPending = true;
      await expectLater(
        repository.review(row, approve: true),
        throwsA(
          isA<StateError>().having(
            (error) => error is QualificationReviewUncertain,
            'uncertain',
            false,
          ),
        ),
      );
      expect(actions, ['approve', 'get_photos']);
      loseMutation = false;
      keepPending = false;
      await repository.review(
        row,
        approve: false,
        reason: 'requested correction',
      );
      expect(actions, ['approve', 'get_photos', 'reject']);
    },
  );
  test(
    'actor change before response delivery prevents returning pending data',
    () async {
      switchActorOnList = true;
      await expectLater(repository.pending(), throwsStateError);
      expect(client.auth.currentUser?.id, 'another-actor');
      expect(actions, ['list']);
    },
  );
}
