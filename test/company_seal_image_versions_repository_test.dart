import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sk_works/domain/company_uploaded_seal_png.dart';
import 'package:sk_works/features/settings/company_seal_image_versions_repository.dart';

const _company = (companyId: '00000000-0000-0000-0000-000000000001', name: '検証株式会社');
const _actorA = '00000000-0000-0000-0000-000000000002';
const _actorB = '00000000-0000-0000-0000-000000000004';
const _version = '00000000-0000-0000-0000-000000000003';
const _encoded = 'iVBORw0KGgoAAAANSUhEUgAAACAAAAAgCAYAAABzenr0AAAALUlEQVR4nO3OIQEAAAwEoetf+hdjBoWlVat9mYCAgICAgICAgICAgICAwHfgAIP/+kx2iamjAAAAAElFTkSuQmCC';
const _hash = '30ca1a5ef40b92ff14e0d5f9b4a2a9930ae2013a6cd9d7c4b636e3e70daa58fc';

Map<String, dynamic> _session(String actor, {String marker = 'initial'}) {
  String part(Object value) => base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  return {'access_token': '${part({'alg': 'HS256'})}.${part({'sub': actor, 'marker': marker, 'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600})}.synthetic',
    'refresh_token': 'synthetic', 'token_type': 'bearer', 'expires_in': 3600,
    'user': {'id': actor, 'aud': 'authenticated', 'role': 'authenticated', 'created_at': '2026-01-01T00:00:00Z'}};
}

class _Wire {
  _Wire() {
    client = SupabaseClient('https://seal-versions.invalid', 'synthetic',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((request) async {
        calls.add(request);
        final name = request.url.path.split('/').last;
        if (name == 'current_master_feature_flags') {
          if (switchDuringCapability) { await switchTo(_actorB); }
          if (rotateTokenDuringCapability) {
            await client.auth.setInitialSession(jsonEncode(_session(_actorA, marker: 'rotated')));
          }
          return respond(request, {'vehicle_management': true, 'route_assignment': true, 'company_seal_image_tools': true});
        }
        expect(jsonDecode(request.body)['p_company_id'], _company.companyId);
        expect(jsonDecode(request.body)['p_expected_name'], _company.name);
        // This is the identity presented to the actual HTTP write/read boundary.
        expect(request.headers['Authorization'], 'Bearer $initialToken');
        targetCalls++;
        if (switchDuringTarget) { await switchTo(_actorB); }
        switch (name) {
          case 'register_company_seal_png_version':
            expect(jsonDecode(request.body)['p_png_sha256'], _hash);
            expect(jsonDecode(request.body)['p_png_base64'], _encoded);
            return respond(request, metadata());
          case 'company_seal_png_versions':
            return respond(request, [metadata()]);
          case 'company_seal_png_version':
            expect(jsonDecode(request.body)['p_version_id'], _version);
            return respond(request, {...metadata(), 'png_base64': _encoded});
          default:
            throw StateError('Unexpected fixture request: $name');
        }
      }));
    repository = CompanySealImageVersionsRepository(client);
  }
  late final SupabaseClient client;
  late final CompanySealImageVersionsRepository repository;
  late String initialToken;
  final calls = <http.Request>[];
  int targetCalls = 0;
  bool switchDuringTarget = false, switchDuringCapability = false, rotateTokenDuringCapability = false;
  Map<String, dynamic> metadata() => {'company_id': _company.companyId, 'company_name': _company.name,
    'version_id': _version, 'sha256': _hash, 'created_at': '2026-10-20T00:00:00Z', 'width': 32, 'height': 32};
  http.Response respond(http.Request request, Object body) => http.Response(jsonEncode(body), 200,
    headers: {'content-type': 'application/json'}, request: request);
  Future<void> switchTo(String actor) async {
    await client.auth.setInitialSession(jsonEncode(_session(actor)));
  }
  Future<void> start() async {
    await switchTo(_actorA);
    initialToken = client.auth.currentSession!.accessToken;
  }
  CompanySealImageVersion get version => CompanySealImageVersion.parse(metadata(), _company);
  Future<Object> run(String operation) async {
    switch (operation) {
      case 'register': return repository.register(_company, CompanyUploadedSealPng.fromBase64(_encoded));
      case 'list': return repository.list(_company);
      case 'read': return repository.read(version);
      default: throw ArgumentError(operation);
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final operation in ['register', 'list', 'read']) {
    test('$operation uses operation-start token even after same-actor SDK token rotation', () async {
      final wire = _Wire();
      addTearDown(wire.client.dispose);
      await wire.start();
      wire.rotateTokenDuringCapability = true;
      await wire.run(operation);
      expect(wire.targetCalls, 1);
      expect(wire.client.auth.currentUser!.id, _actorA);
      expect(wire.client.auth.currentSession!.accessToken, isNot(wire.initialToken));
    });
    test('$operation pins captured bearer and rejects successful receipt after actor change', () async {
      final wire = _Wire();
      addTearDown(wire.client.dispose);
      await wire.start();
      wire.switchDuringTarget = true;
      var published = false;
      await expectLater(wire.run(operation).then((result) { published = true; return result; }), throwsStateError);
      expect(wire.targetCalls, 1);
      expect(wire.client.auth.currentUser!.id, _actorB);
      expect(wire.client.auth.currentSession!.accessToken, isNot(wire.initialToken));
      expect(published, isFalse);
      expect(wire.calls.where((request) => request.url.path.endsWith('/current_master_feature_flags')), hasLength(1));
    });
  }
  test('actor change during preflight sends no register request', () async {
    final wire = _Wire();
    addTearDown(wire.client.dispose);
    await wire.start();
    wire.switchDuringCapability = true;
    await expectLater(wire.run('register'), throwsStateError);
    expect(wire.targetCalls, 0);
  });
  test('same actor receives validated register list and read results', () async {
    final wire = _Wire();
    addTearDown(wire.client.dispose);
    await wire.start();
    final saved = await wire.run('register') as CompanySealImageVersion;
    expect(saved.id, _version);
    expect((await wire.run('list') as List<CompanySealImageVersion>).single.id, _version);
    expect((await wire.run('read') as CompanyUploadedSealPng).sha256, _hash);
    expect(wire.targetCalls, 3);
    expect(wire.calls.where((request) => request.url.path.endsWith('/current_master_feature_flags')), hasLength(6));
  });
}
