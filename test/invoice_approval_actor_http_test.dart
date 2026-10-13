import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/invoices/invoice_approval_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const actor = '10000000-0000-0000-0000-000000000002';
const invoice = '10000000-0000-0000-0000-000000000003';

class _Fixture {
  late HttpServer server;
  late SupabaseClient client;
  final paths = <String>[];
  bool signOutOnContract = false;
  bool approved = true;

  Future<void> start() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      await request.drain<void>();
      final path = request.uri.path;
      paths.add(path);
      Object? response;
      if (path == '/auth/v1/token') {
        String encode(Object value) => base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
        final token = '${encode({'alg': 'HS256', 'typ': 'JWT'})}.${encode({'sub': actor, 'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600})}.c3ludGhldGlj';
        response = {'access_token': token, 'refresh_token': 'synthetic-refresh',
          'token_type': 'bearer', 'expires_in': 3600,
          'user': {'id': actor, 'aud': 'authenticated', 'role': 'authenticated',
            'email': 'fixture@example.test', 'app_metadata': <String, dynamic>{},
            'user_metadata': <String, dynamic>{}, 'created_at': '2026-01-01T00:00:00Z'}};
      } else if (path == '/rest/v1/rpc/invoice_stamp_surname_rows') {
        if (signOutOnContract) await client.auth.signOut();
        response = {'enabled': true, 'names': <Object>[]};
      } else if (path == '/rest/v1/rpc/approve_invoice_with_stamp_surname') {
        response = approved;
      } else {
        response = <String, dynamic>{};
      }
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode(response));
      await request.response.close();
    });
    client = SupabaseClient('http://127.0.0.1:${server.port}', 'synthetic-anon-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false));
    await client.auth.signInWithPassword(email: 'fixture@example.test', password: 'synthetic-password');
    paths.clear();
  }

  Future<void> close() async {
    await client.dispose();
    await server.close(force: true);
  }
}

void main() {
  late _Fixture fixture;
  setUp(() async { fixture = _Fixture(); await fixture.start(); });
  tearDown(() async { await fixture.close(); });

  test('actor change during surname contract read stops the approval write', () async {
    fixture.signOutOnContract = true;
    final repository = InvoiceApprovalRepository.forTesting(fixture.client);
    await expectLater(repository.approve(invoice), throwsStateError);
    expect(fixture.paths.any((path) => path.contains('/approve_invoice')), isFalse);
  });

  test('actual false approval result remains false and true remains true', () async {
    final repository = InvoiceApprovalRepository.forTesting(fixture.client);
    fixture.approved = false;
    expect(await repository.approve(invoice), isFalse);
    fixture.approved = true;
    expect(await repository.approve(invoice), isTrue);
    expect(fixture.paths.where((path) => path.endsWith('/approve_invoice_with_stamp_surname')), hasLength(2));
  });
}
