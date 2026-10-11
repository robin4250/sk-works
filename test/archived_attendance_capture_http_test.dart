import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sk_works/features/attendance/attendance_verification_repository.dart';
import 'package:sk_works/features/attendance/capture_verification_draft.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('archived route attempt stays pending until exact acknowledgement and is retained locally', () async {
    SharedPreferences.setMockInitialValues({});
    const actor = '11111111-1111-4111-8111-111111111111',
        company = '22222222-2222-4222-8222-222222222222';
    final draft = CaptureVerificationDraft({
      'company_id': company,
      'worker_id': 'worker',
      'created_by': actor,
      'event_type': 'clock_in',
      'route_assignment_id': 'route',
      'verification_mode': 'location_photo',
      'capture_contract_version': 1,
      'photo_storage_path': 'company/owned.jpg',
    });
    final snapshot = <String, dynamic>{
      ...draft.payload,
      'confirmed_at': '2026-10-11T17:00:00Z',
      'work_date': '2026-10-12',
    };
    var unavailable = false, mismatch = false, inserts = 0;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
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
      } else if (request.uri.path == '/rest/v1/company_members') {
        response = [
          {'company_id': company},
        ];
      } else if (request.uri.path == '/rest/v1/attendance_verifications') {
        if (request.method == 'POST') inserts++;
        response = [];
      } else if (request.uri.path ==
          '/rest/v1/rpc/get_archived_attendance_capture') {
        final params = jsonDecode(await utf8.decoder.bind(request).join());
        expect(params['p_id'], draft.id);
        if (unavailable) {
          request.response.statusCode = 503;
          response = {'message': 'offline', 'code': 'fixture'};
        } else
          response = {
            'version': 1,
            'archived': true,
            'verification': {
              ...snapshot,
              if (mismatch) 'photo_storage_path': 'different',
            },
          };
      } else {
        request.response.statusCode = 500;
        response = {'message': 'Unexpected request'};
      }
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode(response));
      await request.response.close();
    });
    final client = SupabaseClient(
      'http://127.0.0.1:${server.port}',
      'fixture',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    try {
      await client.auth.signInWithPassword(
        email: 'fixture@example.test',
        password: 'fixture',
      );
      final repo = AttendanceVerificationRepository.forTesting(client);
      final key = 'sko.capture.pending.v1.$actor.$company';
      final prefs = await SharedPreferences.getInstance();
      await expectLater(
        repo.submitCaptureDraft(draft),
        throwsA(isA<ArchivedCaptureVerification>()),
      );
      expect(prefs.getString(key), draft.encoded);
      expect(inserts, 0);
      mismatch = true;
      await expectLater(
        repo.acknowledgeArchivedCaptureDraft(draft),
        throwsStateError,
      );
      expect(prefs.getString(key), draft.encoded);
      expect(prefs.getString('$key.archived.${draft.id}'), isNull);
      mismatch = false;
      unavailable = true;
      await expectLater(
        repo.acknowledgeArchivedCaptureDraft(draft),
        throwsA(isA<PostgrestException>()),
      );
      expect(prefs.getString(key), draft.encoded);
      expect(inserts, 0);
      unavailable = false;
      await repo.acknowledgeArchivedCaptureDraft(draft);
      expect(prefs.getString(key), isNull);
      final retained = jsonDecode(
        prefs.getString('$key.archived.${draft.id}')!,
      );
      expect(retained['draft'], draft.encoded);
      expect(
        retained['verification']['photo_storage_path'],
        snapshot['photo_storage_path'],
      );
      expect(inserts, 0);
    } finally {
      await client.dispose();
      await server.close(force: true);
    }
  });
}
