// Actual pinned SDK + loopback HTTP + mobile methodchannel binding.
// SQL rows are emulated; this is not an on-device/file-backed SQLite test.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:sk_works/features/qualifications/admin_saved_qualification_photo_contract.dart';
import 'package:sk_works/features/qualifications/admin_saved_qualification_photo_draft.dart';
import 'package:sk_works/features/qualifications/admin_saved_qualification_photo_prepare.dart';
import 'package:sk_works/features/qualifications/admin_saved_qualification_photo_prepare_readiness.dart';
import 'package:sk_works/features/qualifications/admin_saved_qualification_photo_submission_repository.dart';
import 'package:sk_works/features/qualifications/qualification_photo_mobile_runtime.dart';
import 'package:sqflite/sqflite.dart' show SqflitePlugin;
import 'package:supabase_flutter/supabase_flutter.dart';

const actor = '00000000-0000-0000-0000-000000000001';
const company = '00000000-0000-0000-0000-000000000002';
const target = '00000000-0000-0000-0000-000000000003';
const requestId = '00000000-0000-0000-0000-000000000004';

class _RealHttpOverrides extends HttpOverrides {}

/// Even an unexpected SDK request cannot leave this one synthetic server.
class _LoopbackOnlyClient extends http.BaseClient {
  _LoopbackOnlyClient(this.port)
    : _inner = IOClient(_RealHttpOverrides().createHttpClient(null));
  final int port;
  final IOClient _inner;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    if (request.url.scheme != 'http' ||
        request.url.host != '127.0.0.1' ||
        request.url.port != port) {
      throw StateError(
        'Only the isolated qualification HTTP fixture is allowed',
      );
    }
    return _inner.send(request);
  }

  @override
  void close() => _inner.close();
}

String _token(int revision, {String user = actor}) {
  String part(Object value) => base64Url.encode(utf8.encode(jsonEncode(value)));
  final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  return '${part({'alg': 'HS256'})}.${part({'sub': user, 'role': 'authenticated', 'exp': now + 3600, 'iat': now, 'fixture_revision': revision})}.synthetic';
}

String _session(String token, {String user = actor}) => jsonEncode({
  'access_token': token,
  'refresh_token': 'synthetic-not-used',
  'token_type': 'bearer',
  'expires_in': 3600,
  'user': {
    'id': user,
    'aud': 'authenticated',
    'created_at': '2026-01-01T00:00:00Z',
    'app_metadata': {'provider': 'google'},
    'user_metadata': <String, dynamic>{},
  },
});

Map<String, Object> capability() => {
  'version': 1,
  'contract': 'qualification_admin_saved_photos',
  'company_id': company,
  'actor_id': actor,
  'photo_submission_available': true,
  'photo_upload_allowed': false,
  'max_photos': 20,
  'self_approval_allowed': false,
};

Map<String, Object> readiness() => {
  ...capability(),
  'contract': 'qualification_admin_photo_prepare_baseline',
  'baseline_guard_version': 1,
  'prepare_action': 'prepare_admin_saved_photos',
};

class _Fixture {
  static const channel = MethodChannel('com.tekartik.sqflite');
  late Directory root;
  late HttpServer server;
  late SupabaseClient client;
  late String originalToken;
  final contexts = StreamController<AdminSavedQualificationPhotoSubmissionScope>.broadcast(sync: true);
  final lifecycle = StreamController<bool>.broadcast(sync: true);
  final nativeCalls = <MethodCall>[];
  final requests = <({String action, Map<String, dynamic> data, String? bearer})>[];
  final rows = <String, String>{};
  final runtimes = <QualificationPhotoMobileRuntime>[];
  bool foreground = true;
  int paths = 0, nextId = 1;
  Object? serverFailure;

  Future<void> start() async {
    root = await Directory.systemTemp.createTemp('sko-runtime-composition-');
    root = Directory(await root.resolveSymbolicLinks());
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      nativeCalls.add(call);
      final args = call.arguments as Map?;
      switch (call.method) {
        case 'openDatabase':
          expect(args!['path'], '${root.path}/sko-qualification-photo-pending-v1.sqlite3');
          expect(args['singleInstance'], false);
          return {'id': nextId++};
        case 'closeDatabase':
          return null;
        case 'getDatabasesPath':
          return root.path;
        case 'query':
          final sql = args!['sql'] as String;
          if (sql.contains('journal_mode')) {
            return [{'journal_mode': 'wal'}];
          }
          if (sql == 'PRAGMA synchronous') {
            return [{'synchronous': 2}];
          }
          if (sql == 'PRAGMA read_uncommitted') {
            return [{'read_uncommitted': 0}];
          }
          if (sql.startsWith('SELECT value')) {
            final key = (args['arguments'] as List).single as String;
            return rows.containsKey(key) ? [{'value': rows[key]}] : [];
          }
          throw StateError('Unexpected query: $sql');
        case 'update':
          final sql = args!['sql'] as String;
          final parameters = args['arguments'] as List;
          if (sql.startsWith('INSERT')) {
            final key = parameters[0] as String;
            if (rows.containsKey(key)) { return 0; }
            rows[key] = parameters[1] as String;
          } else if (sql.startsWith('UPDATE')) {
            final key = parameters[1] as String;
            if (rows[key] != parameters[2]) { return 0; }
            rows[key] = parameters[0] as String;
          } else {
            throw StateError('Runtime must retain pending rows');
          }
          return 1;
        case 'execute':
          if ((args!['sql'] as String).startsWith('BEGIN')) {
            return {'transactionId': 100};
          }
          return null;
        default:
          throw StateError('Unexpected native method ${call.method}');
      }
    });
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      try {
        if (request.method != 'POST' ||
            request.uri.path != '/rest/v1/rpc/personal_qualification_submission') {
          throw StateError('Unexpected loopback request');
        }
        final body = jsonDecode(await utf8.decoder.bind(request).join()) as Map;
        final action = body['p_action'] as String;
        final data = Map<String, dynamic>.from(body['p_data'] as Map);
        requests.add((
          action: action,
          data: data,
          bearer: request.headers.value(HttpHeaders.authorizationHeader),
        ));
        Object result;
        if (action == 'admin_saved_photo_capability') {
          result = capability();
        } else if (action == 'admin_saved_photo_prepare_readiness') {
          result = readiness();
        } else {
          if (action != 'prepare_admin_saved_photos' && action != 'get_photos') {
            throw StateError('No submit/cancel permitted in composition fixture');
          }
          if (action == 'prepare_admin_saved_photos') {
            expect(data['company_id'], company);
            expect(data['target_id'], target);
            expect(data['request_id'], requestId);
            expect(data['expected_photo_paths'], ['saved.jpg']);
            expect(data['photo_slots'], isEmpty);
            // The actual repository must durably record identity before HTTP write.
            expect(rows.length, 1);
          } else {
            expect(data, {'id': requestId});
          }
          result = {
            'version': 1,
            'id': requestId,
            'target_id': target,
            'requested_by': actor,
            'status': 'draft',
            'cancelled': false,
            'reason': null,
            'photo_paths': <String>[],
            'upload_paths': <String>[],
          };
        }
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode(result));
        await request.response.close();
      } catch (error) {
        serverFailure = error;
        request.response.statusCode = 500;
        await request.response.close();
      }
    });
    client = SupabaseClient(
      'http://127.0.0.1:${server.port}',
      'synthetic-public-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: _LoopbackOnlyClient(server.port),
    );
    originalToken = _token(1);
    await client.auth.setInitialSession(_session(originalToken));
  }

  QualificationPhotoMobileRuntime runtime() {
    final runtime = QualificationPhotoMobileRuntime.forTesting(
      client: client,
      scope: () => const AdminSavedQualificationPhotoSubmissionScope(
        actorId: actor, companyId: company, targetId: target, active: true,
      ),
      scopeChanges: contexts.stream,
      foreground: () => foreground,
      foregroundChanges: lifecycle.stream,
      supportDirectory: () async {
        paths++;
        expect(requests.length, greaterThanOrEqualTo(2));
        expect(requests[requests.length - 2].action, 'admin_saved_photo_capability');
        expect(requests.last.action, 'admin_saved_photo_prepare_readiness');
        return root;
      },
      enabled: true,
    );
    runtimes.add(runtime);
    return runtime;
  }

  Future<void> close() async {
    for (final runtime in runtimes) {
      await runtime.dispose();
    }
    await client.dispose();
    await server.close(force: true);
    await contexts.close();
    await lifecycle.close();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    await root.delete(recursive: true);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SqflitePlugin.registerWith();

  test('enabled SDK/private-root/native/repository composition retains and recovers pending', () async {
    final fixture = _Fixture();
    await fixture.start();
    addTearDown(fixture.close);
    // Sentinel verifies runtime cleanup does not delete or truncate the DB path.
    // Methodchannel emulation does not read/write these bytes.
    final sentinel = File('${fixture.root.path}/sko-qualification-photo-pending-v1.sqlite3');
    await sentinel.writeAsString('retained-fixture-file');
    final runtime = fixture.runtime();
    final repository = await runtime.open();
    expect(identical(await runtime.open(), repository), true);
    expect(fixture.paths, 2);
    expect(fixture.nativeCalls.where((c) => c.method == 'openDatabase').length, 1);
    expect(await repository.pendingRequestId(), isNull);
    final command = AdminSavedQualificationPhotoPrepare.fromDraft(
      draft: AdminSavedQualificationPhotoDraft(
        companyId: company, actorId: actor, targetId: target,
        savedPaths: ['saved.jpg'], selectedPaths: [],
      ),
      capability: AdminSavedQualificationPhotoCapability.parse(
        capability(), companyId: company, actorId: actor,
      ),
      readiness: AdminSavedQualificationPhotoPrepareReadiness.parse(
        readiness(), companyId: company, actorId: actor,
      ),
      requestId: requestId,
      scopeActive: true,
      currentCompanyId: company,
      currentActorId: actor,
      currentTargetId: target,
      currentSavedPaths: ['saved.jpg'],
    );
    final result = await repository.prepare(command: command, currentSavedPaths: ['saved.jpg']);
    expect(result.id, requestId);
    expect(result.targetId, target);
    expect(result.requestedBy, actor);
    expect(result.status, 'draft');
    expect(await repository.pendingRequestId(), requestId);
    final pending = fixture.rows.values.single;
    expect(pending.contains(fixture.originalToken), false);
    await runtime.dispose();
    expect(fixture.nativeCalls.where((c) => c.method == 'closeDatabase').length, 1);
    expect(fixture.rows.values.single, pending);
    expect(await sentinel.readAsString(), 'retained-fixture-file');

    final reopened = fixture.runtime();
    final recoveredRepository = await reopened.open();
    expect(await recoveredRepository.pendingRequestId(), requestId);
    final prepares = fixture.requests.where((r) => r.action == 'prepare_admin_saved_photos').length;
    final recovered = await recoveredRepository.recover(expectedRequestId: requestId);
    expect(recovered.status, 'draft');
    expect(fixture.requests.where((r) => r.action == 'prepare_admin_saved_photos').length, prepares);
    expect(fixture.nativeCalls.where((c) => c.method == 'openDatabase').length, 2);
    expect(fixture.requests.every((r) => r.bearer == 'Bearer ${fixture.originalToken}'), true);
    expect(fixture.serverFailure, isNull);

    fixture.foreground = false;
    fixture.lifecycle.add(false);
    await reopened.dispose();
    final requests = fixture.requests.length;
    final updates = fixture.nativeCalls.where((c) => c.method == 'update').length;
    await expectLater(recoveredRepository.submit(expectedRequestId: requestId), throwsStateError);
    await expectLater(repository.pendingRequestId(), throwsStateError);
    await expectLater(reopened.open(), throwsStateError);
    expect(fixture.requests.length, requests);
    expect(fixture.nativeCalls.where((c) => c.method == 'update').length, updates);
    expect(fixture.nativeCalls.where((c) => c.method == 'closeDatabase').length, 2);
    expect(fixture.rows.length, 1);
    expect(await sentinel.readAsString(), 'retained-fixture-file');
  });
}
