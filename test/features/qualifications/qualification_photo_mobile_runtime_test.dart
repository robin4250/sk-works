import 'dart:async';
import 'dart:io';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sk_works/features/qualifications/admin_saved_qualification_photo_submission_repository.dart';
import 'package:sk_works/features/qualifications/qualification_photo_mobile_runtime.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _RejectClient extends http.BaseClient {
  int requests = 0;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests++;
    throw StateError('No network permitted in OFF runtime fixture');
  }
}

void main() {
  test('default OFF never reads scope, provider, RPC or native channel', () async {
    final transport = _RejectClient();
    final client = SupabaseClient(
      'https://fixture.invalid',
      'synthetic-public-key',
      httpClient: transport,
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    var paths = 0;
    var scopeReads = 0;
    final runtime = QualificationPhotoMobileRuntime.forTesting(
      client: client,
      scope: () {
        scopeReads++;
        throw StateError('OFF must not inspect scope');
      },
      scopeChanges: const Stream<AdminSavedQualificationPhotoSubmissionScope>.empty(),
      foreground: () => throw StateError('OFF must not inspect lifecycle'),
      foregroundChanges: const Stream<bool>.empty(),
      supportDirectory: () async {
        paths++;
        return Directory('/unreachable-fixture');
      },
    );
    await expectLater(runtime.open(), throwsStateError);
    await runtime.dispose();
    await runtime.dispose();
    expect(paths, 0);
    expect(scopeReads, 0);
    expect(transport.requests, 0);
    await client.dispose();
  });

  test('dispose before explicitly enabled open prevents every dependency', () async {
    final transport = _RejectClient();
    final client = SupabaseClient(
      'https://fixture.invalid',
      'synthetic-public-key',
      httpClient: transport,
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    var paths = 0;
    final runtime = QualificationPhotoMobileRuntime.forTesting(
      client: client,
      scope: () => throw StateError('Disposed runtime must not inspect scope'),
      scopeChanges: const Stream<AdminSavedQualificationPhotoSubmissionScope>.empty(),
      foreground: () => true,
      foregroundChanges: const Stream<bool>.empty(),
      supportDirectory: () async {
        paths++;
        return Directory('/unreachable-fixture');
      },
      enabled: true,
    );
    await runtime.dispose();
    await expectLater(runtime.open(), throwsStateError);
    expect(paths, 0);
    expect(transport.requests, 0);
    await client.dispose();
  });
  test('enabled readiness refusal never reads support directory', () async {
    final fixture = await _EnabledFixture.create(ready: false);
    final runtime = fixture.runtime(() async {
      fixture.paths++;
      throw StateError('Readiness must precede paths');
    });
    await expectLater(runtime.open(), throwsStateError);
    expect(fixture.actions, ['admin_saved_photo_capability', 'admin_saved_photo_prepare_readiness']);
    expect(fixture.paths, 0);
    await runtime.dispose();
    await fixture.client.dispose();
  });

  test('dispose awaits blocked provider and rejects late path result', () async {
    final fixture = await _EnabledFixture.create();
    final arrived = Completer<void>();
    final directory = Completer<Directory>();
    final runtime = fixture.runtime(() {
      fixture.paths++;
      arrived.complete();
      return directory.future;
    });
    final opening = runtime.open();
    final rejected = expectLater(opening, throwsStateError);
    await arrived.future;
    var disposed = false;
    final disposing = runtime.dispose().then((_) { disposed = true; });
    await Future<void>.delayed(Duration.zero);
    expect(disposed, false);
    directory.complete(Directory('/unreachable-fixture'));
    await rejected;
    await disposing;
    expect(disposed, true);
    expect(fixture.paths, 1);
    expect(fixture.actions.length, 2);
    await fixture.client.dispose();
  });

}

class _EnabledFixture {
  static const actor = '00000000-0000-0000-0000-000000000001';
  static const company = '00000000-0000-0000-0000-000000000002';
  static const target = '00000000-0000-0000-0000-000000000003';
  late final SupabaseClient client;
  final actions = <String>[];
  final contexts = StreamController<AdminSavedQualificationPhotoSubmissionScope>.broadcast();
  final foregrounds = StreamController<bool>.broadcast();
  int paths = 0;

  static Future<_EnabledFixture> create({bool ready = true}) async {
    final fixture = _EnabledFixture();
    fixture.client = SupabaseClient(
      'https://fixture.invalid',
      'synthetic-public-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((request) async {
        if (request.url.path != '/rest/v1/rpc/personal_qualification_submission') {
          throw StateError('Unexpected fixture request');
        }
        final body = jsonDecode(request.body) as Map;
        final action = body['p_action'] as String;
        fixture.actions.add(action);
        final readiness = action == 'admin_saved_photo_prepare_readiness';
        if (action != 'admin_saved_photo_capability' && !readiness) {
          throw StateError('No data RPC permitted in bootstrap fixture');
        }
        return http.Response(jsonEncode({
          'version': 1,
          'contract': readiness ? 'qualification_admin_photo_prepare_baseline' : 'qualification_admin_saved_photos',
          'company_id': company,
          'actor_id': actor,
          if (readiness) 'baseline_guard_version': 1,
          if (readiness) 'prepare_action': 'prepare_admin_saved_photos',
          'photo_submission_available': readiness ? ready : true,
          'photo_upload_allowed': false,
          'max_photos': 20,
          'self_approval_allowed': false,
        }), 200, headers: {'content-type': 'application/json'});
      }),
    );
    String part(Object value) => base64Url.encode(utf8.encode(jsonEncode(value)));
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final token = '${part({'alg': 'HS256'})}.${part({'sub': actor, 'role': 'authenticated', 'exp': now + 3600, 'iat': now})}.synthetic';
    await fixture.client.auth.setInitialSession(jsonEncode({
      'access_token': token,
      'refresh_token': 'synthetic-not-used',
      'token_type': 'bearer',
      'expires_in': 3600,
      'user': {
        'id': actor,
        'aud': 'authenticated',
        'created_at': '2026-01-01T00:00:00Z',
        'app_metadata': {'provider': 'google'},
        'user_metadata': <String, dynamic>{},
      },
    }));
    return fixture;
  }

  QualificationPhotoMobileRuntime runtime(Future<Directory> Function() directory) =>
      QualificationPhotoMobileRuntime.forTesting(
        client: client,
        scope: () => const AdminSavedQualificationPhotoSubmissionScope(
          actorId: actor,
          companyId: company,
          targetId: target,
          active: true,
        ),
        scopeChanges: contexts.stream,
        foreground: () => true,
        foregroundChanges: foregrounds.stream,
        supportDirectory: directory,
        enabled: true,
      );
}
