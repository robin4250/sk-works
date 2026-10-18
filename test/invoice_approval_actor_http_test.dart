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
  String? v2Error;
  int v2Status = 404;
  bool loadingRows = false;
  final payloads = <String, Map<String, dynamic>>{};

  Future<void> start() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final body = await utf8.decoder.bind(request).join();
      final path = request.uri.path;
      paths.add(path);
      if (body.isNotEmpty) payloads[path] = Map<String, dynamic>.from(jsonDecode(body) as Map);
      Object? response;
      if (path == '/auth/v1/token') {
        String encode(Object value) => base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
        final token = '${encode({'alg': 'HS256', 'typ': 'JWT'})}.${encode({'sub': actor, 'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600})}.c3ludGhldGlj';
        response = {'access_token': token, 'refresh_token': 'synthetic-refresh',
          'token_type': 'bearer', 'expires_in': 3600,
          'user': {'id': actor, 'aud': 'authenticated', 'role': 'authenticated',
            'email': 'fixture@example.test', 'app_metadata': <String, dynamic>{},
            'user_metadata': <String, dynamic>{}, 'created_at': '2026-01-01T00:00:00Z'}};
      } else if (path == '/rest/v1/rpc/invoice_approval_status_rows_v2' ||
          path == '/rest/v1/rpc/invoice_approval_status_rows') {
        if (path.endsWith('_v2') && v2Error != null) {
          request.response.statusCode = v2Status;
          response = {'code': v2Error, 'message': 'original status failure',
            'details': 'original detail', 'hint': 'original hint'};
        } else {
          response = [{'approver_user_id': actor, 'approver_name': 'Fixture approver',
            'position': 1, 'status': 'pending', 'can_current_user_approve': true,
            'stamp_role': 'confirmation', 'display_date_mode': 'actual'}];
        }
      } else if (path == '/rest/v1/rpc/invoice_stamp_surname_rows') {
        if (signOutOnContract) await client.auth.signOut();
        response = {'enabled': true, 'names': <Object>[
          if (loadingRows) {'invoice_id': invoice, 'user_id': actor, 'status': 'pending',
            'can_set_surname': true, 'draft_surname': 'Fixture'}
        ]};
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
    payloads.clear();
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

  for (final strict in [false, true]) {
    test('successful v2 read keeps rows and surname contract, strict=$strict', () async {
      fixture.loadingRows = true;
      final repository = InvoiceApprovalRepository.forTesting(fixture.client);
      final rows = await repository.loadForInvoice(invoice,
        allowLegacyInitialization: !strict);
      expect(rows, hasLength(1));
      expect(rows.single.userId, actor);
      expect(rows.single.name, 'Fixture approver');
      expect(rows.single.status, 'pending');
      expect(rows.single.canCurrentUserApprove, isTrue);
      expect(rows.single.draftStampSurname, 'Fixture');
      expect(rows.single.canCurrentUserSetStampSurname, isTrue);
      expect(fixture.paths, ['/rest/v1/rpc/invoice_approval_status_rows_v2',
        '/rest/v1/rpc/invoice_stamp_surname_rows']);
      expect(fixture.payloads.values, everyElement({'p_invoice_id': invoice}));
    });
  }

  for (final error in ['PGRST202', '42883', '42501']) {
    test('strict read preserves $error without a legacy RPC', () async {
      fixture.v2Error = error;
      fixture.v2Status = error == '42501' ? 403 : 404;
      final repository = InvoiceApprovalRepository.forTesting(fixture.client);
      await expectLater(repository.loadForInvoice(invoice,
        allowLegacyInitialization: false), throwsA(isA<PostgrestException>()
          .having((e) => e.code, 'code', error)
          .having((e) => e.message, 'message', 'original status failure')
          .having((e) => e.details, 'details', 'original detail')
          .having((e) => e.hint, 'hint', 'original hint')));
      expect(fixture.paths, ['/rest/v1/rpc/invoice_approval_status_rows_v2']);
    });
  }

  for (final error in ['PGRST202', '42883']) {
    test('default read retains legacy fallback and surname contract for $error', () async {
      fixture.loadingRows = true;
      fixture.v2Error = error;
      final repository = InvoiceApprovalRepository.forTesting(fixture.client);
      final rows = await repository.loadForInvoice(invoice);
      expect(rows, hasLength(1));
      expect(rows.single.userId, actor);
      expect(rows.single.draftStampSurname, 'Fixture');
      expect(fixture.paths, ['/rest/v1/rpc/invoice_approval_status_rows_v2',
        '/rest/v1/rpc/invoice_approval_status_rows', '/rest/v1/rpc/invoice_stamp_surname_rows']);
      expect(fixture.payloads.values, everyElement({'p_invoice_id': invoice}));
    });
  }

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
