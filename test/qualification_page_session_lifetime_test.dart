// UI State-unit tests only. Real Session model/provider injection, mocked data;
// not SDK Auth transport, server/RLS, or certificate/photo-client qualification.
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sk_works/features/qualifications/qualification_cloud_page.dart';
import 'package:sk_works/features/qualifications/qualification_cloud_repository.dart';

Session session(String uid, String sid) {
  String part(Object value) =>
      base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  final token =
      '${part({'alg': 'HS256'})}.${part({'sub': uid, 'session_id': sid, 'role': 'authenticated', 'exp': 4102444800})}.fixture';
  return Session.fromJson({
    'access_token': token,
    'refresh_token': 'synthetic-refresh',
    'token_type': 'bearer',
    'expires_in': 3600,
    'expires_at': 4102444800,
    'user': {
      'id': uid,
      'aud': 'authenticated',
      'role': 'authenticated',
      'app_metadata': <String, dynamic>{},
      'user_metadata': <String, dynamic>{},
      'created_at': '2026-01-01T00:00:00Z',
    },
  })!;
}

class PageRepository extends QualificationCloudRepository {
  PageRepository(this.observed)
    : super.forTesting(
        SupabaseClient(
          'http://127.0.0.1:1',
          'synthetic-anon',
          authOptions: const AuthClientOptions(autoRefreshToken: false),
        ),
      );
  Session observed;
  final events = StreamController<AuthState>.broadcast();
  final pending = Completer<Map<String, dynamic>>();
  @override
  Session? get currentSession => observed;
  @override
  Stream<AuthState> get attachmentAuthChanges => events.stream;
  @override
  Future<bool Function()> captureAttachmentReadScope() async =>
      () => true;
  @override
  Future<Map<String, dynamic>> loadAll() => pending.future;
  @override
  Future<bool> canManageMaster() async => false;
  @override
  Future<bool> canManageWorkerQualifications() async => false;
}

const actor = '11111111-1111-4111-8111-111111111111';
const sidA = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const sidB = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
Map<String, dynamic> rows() => {
  'masters': <Map<String, dynamic>>[],
  'workers': <Map<String, dynamic>>[
    {
      'id': '22222222-2222-4222-8222-222222222222',
      'name': 'SYNTHETIC OLD PERSON',
    },
  ],
  'qualifications': <Map<String, dynamic>>[],
};

void main() {
  testWidgets(
    'observed silent SID change is terminal even after original SID returns',
    (tester) async {
      final a = session(actor, sidA);
      final repo = PageRepository(a);
      await tester.pumpWidget(
        MaterialApp(home: QualificationCloudPage(repository: repo)),
      );
      repo.pending.complete(rows());
      await tester.pumpAndSettle();
      expect(find.text('SYNTHETIC OLD PERSON'), findsOneWidget);
      repo.observed = session(actor, sidB);
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: QualificationCloudPage(repository: repo),
        ),
      );
      await tester.pump();
      expect(find.text('SYNTHETIC OLD PERSON'), findsNothing);
      repo.observed = a;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.light(),
          home: QualificationCloudPage(repository: repo),
        ),
      );
      await tester.pump();
      expect(find.text('SYNTHETIC OLD PERSON'), findsNothing);
      expect(find.byType(FloatingActionButton), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await repo.events.close();
    },
  );
  testWidgets(
    'auth event retires pending old response and retained role actions',
    (tester) async {
      final repo = PageRepository(session(actor, sidA));
      await tester.pumpWidget(
        MaterialApp(home: QualificationCloudPage(repository: repo)),
      );
      repo.observed = session('33333333-3333-4333-8333-333333333333', sidB);
      repo.events.add(AuthState(AuthChangeEvent.signedIn, repo.observed));
      await tester.pump();
      repo.pending.complete(rows());
      await tester.pumpAndSettle();
      expect(find.text('SYNTHETIC OLD PERSON'), findsNothing);
      expect(find.byType(FloatingActionButton), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await repo.events.close();
    },
  );
}
