import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
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
}
