import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:sk_works/features/notifications/app_notification_repository.dart';
import 'package:sk_works/features/sites/site_order_workflow_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const noticeActor = '91000000-0000-4000-8000-000000000001';
const noticeCompany = '91000000-0000-4000-8000-000000000002';
const noticeSid = '91000000-0000-4000-8000-000000000003';
const noticePackage = '91000000-0000-4000-8000-000000000004';
const noticeId = '91000000-0000-4000-8000-000000000005';
const otherNoticeId = '91000000-0000-4000-8000-000000000006';

Future<void> noticeStage(Completer<void> barrier, String stage) => barrier.future.timeout(
  const Duration(seconds: 5), onTimeout: () => throw StateError('Fixture stage not reached: $stage'));

class NoticeWire extends http.BaseClient {
  String mode = 'normal', company = noticeCompany, role = 'manager';
  String? readAt;
  int patches = 0, unsafePatches = 0, details = 0, memberships = 0, businessWrites = 0;
  bool holdDetail = false;
  Completer<void>? detailHold, detailStarted, patchHold, patchStarted;
  bool commitBeforeHold = false;
  final patchQueries = <Map<String, String>>[];
  final patchBodies = <Map<String, dynamic>>[];
  String? expectedBearer;
  Map<String, dynamic> session({String sid = noticeSid, String actor = noticeActor}) {
    String part(Object v) => base64Url.encode(utf8.encode(jsonEncode(v))).replaceAll('=', '');
    final expiry = DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600;
    final token = '${part({'alg': 'HS256', 'typ': 'JWT'})}.${part({'sub': actor, 'session_id': sid, 'role': 'authenticated', 'exp': expiry})}.${base64Url.encode(List<int>.filled(32, 9)).replaceAll('=', '')}';
    return {'access_token': token, 'refresh_token': 'synthetic-notice-refresh',
      'expires_in': 3600, 'expires_at': expiry, 'token_type': 'bearer',
      'user': {'id': actor, 'aud': 'authenticated', 'role': 'authenticated',
        'created_at': '2026-01-01T00:00:00Z'}};
  }
  Map<String, dynamic> row() => {
    'id': noticeId, 'company_id': mode == 'row-company' ? otherNoticeId : noticeCompany,
    'recipient_user_id': mode == 'row-actor' ? otherNoticeId : noticeActor,
    'action_key': mode == 'row-action' ? 'invoice_approval' : 'site_order_package',
    'action_id': mode == 'row-package' ? otherNoticeId : noticePackage,
    'read_at': readAt,
  };
  @override Future<http.StreamedResponse> send(http.BaseRequest request) async {
    Object? result;
    var status = 200;
    final path = request.url.path;
    if (path == '/rest/v1/company_members') {
      memberships++;
      result = [{'company_id': company, 'role': role}];
    } else if (path == '/functions/v1/site-order-workflow') {
      final command = jsonDecode((request as http.Request).body) as Map;
      if (command['action'] != 'detail') {
        businessWrites++;
        throw StateError('Unexpected business command');
      }
      details++;
      if (detailStarted?.isCompleted == false) detailStarted!.complete();
      if (holdDetail) await detailHold?.future;
      if (mode == 'unavailable') status = 404;
      result = {'result': {
        'package_id': mode == 'wrong-package' ? otherNoticeId : noticePackage,
        'is_sender': false, 'is_recipient': mode != 'denied', 'can_write': false,
        'approved': false, 'rejected': false,
        'body': {'work_name': '権限確認後の工事'},
        // There is deliberately no recipient local site ID before approval.
        'site_projection': <String, Object?>{},
      }};
    } else if (path == '/rest/v1/app_notifications') {
      final query = request.url.queryParameters;
      final current = row();
      bool tupleMatches() => const ['id', 'company_id', 'recipient_user_id', 'action_key', 'action_id']
        .every((key) => query[key] == 'eq.${current[key]}');
      if (request.method == 'PATCH') {
        patches++;
        patchQueries.add(Map.of(query));
        final body = Map<String, dynamic>.from(jsonDecode((request as http.Request).body) as Map);
        patchBodies.add(body);
        if (!tupleMatches() || query['read_at'] != 'is.null' || body.keys.toSet().difference({'read_at'}).isNotEmpty || body.length != 1) {
          unsafePatches++;
          throw StateError('Unbound fixture write rejected');
        }
        expect(request.headers['Authorization'] == expectedBearer, isTrue,
          reason: 'Write must retain the captured bearer without logging it');
        if (patchStarted?.isCompleted == false) patchStarted!.complete();
        if (commitBeforeHold) readAt = body['read_at'] as String;
        await patchHold?.future;
        if (mode == 'ack-loss') {
          readAt = body['read_at'] as String;
          throw http.ClientException('synthetic unknown write result');
        }
        if (mode == 'cas-zero') { result = <Object>[]; }
        else {
          readAt = body['read_at'] as String;
          result = [row()];
        }
      } else if (request.method == 'GET') {
        result = tupleMatches() && mode != 'missing-row' ? [current] : <Object>[];
      } else {
        throw StateError('Unexpected notification method');
      }
    } else {
      throw StateError('Unexpected fixture endpoint');
    }
    return http.StreamedResponse(Stream.value(utf8.encode(jsonEncode(result))), status,
      headers: {'content-type': 'application/json'}, request: request);
  }
}

class NoticeApi extends SiteOrderWorkflowRepository {
  NoticeApi(super.client);
  bool closed = false, missingBinding = false;
  String pendingJournalPhase = 'none';
  @override Future<bool> hasPendingApproval(String id) async {
    pendingJournalPhase = 'approval';
    final value = await super.hasPendingApproval(id);
    pendingJournalPhase = 'approval-complete'; return value;
  }
  @override Future<bool> hasPendingRefusal(String id) async {
    pendingJournalPhase = 'refusal';
    final value = await super.hasPendingRefusal(id);
    pendingJournalPhase = 'refusal-complete'; return value;
  }
  @override Future<bool> hasPendingReplyRecovery(String id) async {
    pendingJournalPhase = 'recovery';
    final value = await super.hasPendingReplyRecovery(id);
    pendingJournalPhase = 'recovery-complete'; return value;
  }
  ({String actorId, String companyId, String sessionId})? replacement;
  @override ({String actorId, String companyId, String sessionId})? get notificationReadBinding =>
    missingBinding ? null : replacement ?? super.notificationReadBinding;
  @override void dispose() { if (closed) return; closed = true; super.dispose(); }
}
class NoticeFixture {
  NoticeFixture._(this.wire, this.client, this.api, this.notifications);
  final NoticeWire wire;
  final SupabaseClient client;
  final NoticeApi api;
  final AppNotificationRepository notifications;
  static Future<NoticeFixture> create() async {
    final wire = NoticeWire();
    final client = SupabaseClient('https://notice-fixture.invalid', 'synthetic-public',
      httpClient: wire, authOptions: const AuthClientOptions(autoRefreshToken: false));
    final session = wire.session();
    await client.auth.setInitialSession(jsonEncode(session));
    await client.auth.recoverSession(jsonEncode(session));
    wire.expectedBearer = 'Bearer ${session['access_token']}';
    return NoticeFixture._(wire, client, NoticeApi(client), AppNotificationRepository.forTesting(client));
  }
  SiteOrderNotificationReadScope scope({String? expectedCompanyId,
      String? Function()? currentCompany, SiteOrderWorkflowApi? useApi}) => notifications.openSiteOrderReadScope(
    api: useApi ?? api, notificationId: noticeId, packageId: noticePackage,
    expectedCompanyId: expectedCompanyId, currentCompany: currentCompany);
  Future<void> close() async { api.dispose(); await client.dispose(); }
  Future<void> changeSession() async {
    final next = wire.session(sid: otherNoticeId);
    await client.auth.recoverSession(jsonEncode(next));
  }
}
void main() {
  test('opt-in parent lifetime permanently blocks child API after getter drift', () async {
    final f = await NoticeFixture.create(); var current = true;
    try {
      expect(f.api.bindNotificationUiContext(() => current), isTrue);
      await f.api.verify();
      current = false;
      final calls = f.wire.memberships;
      await expectLater(f.api.verify(), throwsStateError);
      current = true;
      await expectLater(f.api.verify(), throwsStateError);
      expect(f.wire.memberships, calls);
      expect(f.api.invalidated, isTrue); expect(f.wire.businessWrites, 0);
    } finally { await f.close(); }
  });

  TestWidgetsFlutterBinding.ensureInitialized();
  test('actual SDK read scope pins tuple and updates only read_at once', () async {
    final f = await NoticeFixture.create(); final scope = f.scope();
    try {
      await scope.verifyTarget();
      expect(f.wire.patches, 0);
      await scope.markRead(() {});
      expect(f.wire.patches, 1); expect(f.wire.unsafePatches, 0);
      expect(f.wire.patchBodies.single.keys, ['read_at']);
      expect(f.wire.businessWrites, 0);
      await expectLater(scope.markRead(() {}), throwsA(isA<SiteOrderNotificationReadUnknown>()));
      expect(f.wire.patches, 1);
    } finally { scope.dispose(); await f.close(); }
  });
  test('concurrent callbacks reserve one read attempt before asynchronous admission', () async {
    final f = await NoticeFixture.create();
    f.wire.holdDetail = true; f.wire.detailHold = Completer<void>(); f.wire.detailStarted = Completer<void>();
    final scope = f.scope();
    try {
      final first = scope.markRead(() {});
      await noticeStage(f.wire.detailStarted!, 'detail');
      await expectLater(scope.markRead(() {}), throwsA(isA<SiteOrderNotificationReadUnknown>()));
      expect(f.wire.patches, 0);
      f.wire.detailHold!.complete();
      await first;
      expect(f.wire.patches, 1);
    } finally { scope.dispose(); await f.close(); }
  });
  test('already-read exact row is verified without another update', () async {
    final f = await NoticeFixture.create(); f.wire.readAt = '2026-10-31T00:00:00Z';
    final scope = f.scope();
    try { await scope.markRead(() {}); expect(f.wire.patches, 0); }
    finally { scope.dispose(); await f.close(); }
  });
  for (final mode in ['missing-row','row-company','row-actor','row-action','row-package','wrong-package','denied','unavailable']) {
    test('$mode cannot fall back to ordinary marking', () async {
      final f = await NoticeFixture.create(); f.wire.mode = mode;
      final scope = f.scope();
      try { await expectLater(scope.markRead(() {}), throwsA(anything));
        final reads = f.wire.details;
        await expectLater(scope.markRead(() {}), throwsA(anything));
        expect(f.wire.details, reads); expect(f.wire.patches, 0); }
      finally { scope.dispose(); await f.close(); }
    });
  }
  for (final mode in ['actor','sid','company','missing']) {
    test('API binding $mode cannot substitute the captured SDK identity', () async {
      final f = await NoticeFixture.create();
      if (mode == 'missing') { f.api.missingBinding = true; }
      else { f.api.replacement = (actorId: mode == 'actor' ? otherNoticeId : noticeActor,
        companyId: mode == 'company' ? otherNoticeId : noticeCompany,
        sessionId: mode == 'sid' ? otherNoticeId : noticeSid); }
      final scope = f.scope();
      try { await expectLater(scope.markRead(() {}), throwsA(anything)); expect(f.wire.patches, 0); }
      finally { scope.dispose(); await f.close(); }
    });
  }
  test('another SDK client with the same tuple is refused', () async {
    final a = await NoticeFixture.create(), b = await NoticeFixture.create();
    try { expect(() => a.scope(useApi: b.api), throwsA(isA<SiteOrderNotificationReadUnknown>())); expect(a.wire.patches, 0); }
    finally { await a.close(); await b.close(); }
  });
  test('external company change without widget replacement retires before a read write', () async {
    final f = await NoticeFixture.create(); var company = noticeCompany;
    final scope = f.scope(expectedCompanyId: company, currentCompany: () => company);
    try {
      await scope.verifyTarget(); company = otherNoticeId;
      await expectLater(scope.markRead(() {}), throwsA(anything)); expect(f.wire.patches, 0);
    } finally { scope.dispose(); await f.close(); }
  });
  test('same actor new SID while detail waits produces no old read', () async {
    final f = await NoticeFixture.create();
    f.wire.holdDetail = true; f.wire.detailHold = Completer<void>(); f.wire.detailStarted = Completer<void>();
    final scope = f.scope();
    try {
      final checked = expectLater(scope.markRead(() {}), throwsA(anything));
      await noticeStage(f.wire.detailStarted!, 'detail'); await f.changeSession();
      f.wire.detailHold!.complete();
      await checked; expect(f.wire.patches, 0);
    } finally { scope.dispose(); await f.close(); }
  });
  for (final mode in ['cas-zero','ack-loss']) {
    test('$mode stays unknown and never retries the update', () async {
      final f = await NoticeFixture.create(); f.wire.mode = mode; final scope = f.scope();
      try {
        await expectLater(scope.markRead(() {}), throwsA(isA<SiteOrderNotificationReadUnknown>()));
        expect(f.wire.patches, 1);
        await expectLater(scope.markRead(() {}), throwsA(anything)); expect(f.wire.patches, 1);
      } finally { scope.dispose(); await f.close(); }
    });
  }
  test('abort after a simulated committed PATCH is unknown, not rollback proof', () async {
    final f = await NoticeFixture.create();
    f.wire.commitBeforeHold = true; f.wire.patchHold = Completer<void>(); f.wire.patchStarted = Completer<void>();
    final scope = f.scope();
    try {
      final checked = expectLater(scope.markRead(() {}), throwsA(anything));
      await noticeStage(f.wire.patchStarted!, 'read PATCH'); await f.changeSession(); f.wire.patchHold!.complete();
      await checked;
      expect(f.wire.readAt, isNotNull); expect(f.wire.patches, 1);
      await expectLater(scope.markRead(() {}), throwsA(anything)); expect(f.wire.patches, 1);
    } finally { scope.dispose(); await f.close(); }
  });
}
