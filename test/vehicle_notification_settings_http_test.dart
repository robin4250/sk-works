import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sk_works/data/supabase_backend.dart';
import 'package:sk_works/features/operations/vehicle_notification_settings_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _url = 'https://vehicle-notice-fixture.invalid';
const _key = 'public_fixture';
const _actor = '20000000-0000-4000-8000-000000000001';
const _vehicle = '30000000-0000-4000-8000-000000000001';
const _candidates = ['recipient-1', 'recipient-2', 'recipient-3'];
final _calls = <http.Request>[];
final _readResponses = <Map<String, dynamic>>[];

Map<String, dynamic> _settings({bool enabled = true, bool canManage = true,
    String vehicle = _vehicle}) => {
  'vehicle_id': vehicle,
  'can_manage': canManage,
  'enabled': enabled,
  'configured': true,
  'user_ids': ['recipient-1'],
  'suggested_user_ids': [],
  'candidates': [for (final id in _candidates) {'user_id': id, 'name': id}],
};

String _session() {
  String part(Object value) => base64Url.encode(utf8.encode(jsonEncode(value)))
      .replaceAll('=', '');
  return jsonEncode({
    'access_token': '${part({'alg': 'HS256'})}.${part({'sub': _actor, 'exp': 4102444800})}.synthetic',
    'refresh_token': 'fixture-only-refresh', 'token_type': 'bearer',
    'expires_in': 3600,
    'user': {'id': _actor, 'aud': 'authenticated',
      'created_at': '2026-10-18T00:00:00Z'},
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  if (!const bool.fromEnvironment('SKO_VEHICLE_NOTICE_FIXTURE')) {
    test('vehicle notice HTTP requires dedicated synthetic configuration', () {},
      skip: 'Use fixed synthetic dart-defines; no production credentials.');
    return;
  }

  setUpAll(() async {
    // Refuse real configuration before the SDK or any transport is initialized.
    expect(SupabaseBackendConfig.url, _url);
    expect(SupabaseBackendConfig.publishableKey, _key);
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: _url, publishableKey: _key, debug: false,
      authOptions: const FlutterAuthClientOptions(
        autoRefreshToken: false, detectSessionInUri: false),
      httpClient: MockClient((request) async {
        expect(request.url.origin, _url);
        _calls.add(request);
        expect(request.method, 'POST'); // Real PostgREST RPC transport.
        final parameters = jsonDecode(request.body);
        Object? response;
        switch (request.url.path) {
          case '/rest/v1/rpc/get_vehicle_notification_settings':
            expect(parameters, {'p_vehicle_id': _vehicle});
            expect(_readResponses, isNotEmpty,
              reason: 'Every actual read must have an explicit fixture response');
            response = _readResponses.removeAt(0);
          case '/rest/v1/rpc/set_vehicle_notification_assignees':
            response = null;
          default:
            throw StateError('Unexpected endpoint; Auth mutation/mail are forbidden');
        }
        return http.Response(jsonEncode(response), 200,
          headers: {'content-type': 'application/json'}, request: request);
      }),
    );
    final original = Supabase.instance.client;
    await SupabaseBackend.initializeIfConfigured();
    expect(identical(SupabaseBackend.client, original), true);
    await original.auth.setInitialSession(_session());
    expect(original.auth.currentUser?.id, _actor);
  });
  tearDownAll(() async => Supabase.instance.dispose());
  setUp(() { _calls.clear(); _readResponses.clear(); });

  Future<VehicleNotificationSettingsRepository> observedOn() async {
    final repository = VehicleNotificationSettingsRepository.maybeCreate()!;
    _readResponses.add(_settings());
    final shown = await repository.load(_vehicle);
    expect(shown.canSave(['recipient-1']), true);
    return repository;
  }

  for (final scenario in [
    (name: 'rollout becomes OFF', response: _settings(enabled: false)),
    (name: 'management permission is withdrawn', response: _settings(canManage: false)),
    (name: 'server returns a different vehicle', response: _settings(vehicle: 'other-vehicle')),
  ]) {
    test('save rereads exact scope and sends no setter when ${scenario.name}', () async {
      final repository = await observedOn();
      _readResponses.add(scenario.response);
      await expectLater(repository.save(_vehicle, ['recipient-1']), throwsStateError);
      expect(_calls.map((request) => request.url.path), [
        '/rest/v1/rpc/get_vehicle_notification_settings',
        '/rest/v1/rpc/get_vehicle_notification_settings',
      ]);
      expect(_calls.where((request) => request.url.path.endsWith(
        '/set_vehicle_notification_assignees')), isEmpty);
      expect(_readResponses, isEmpty);
      expect(SupabaseBackend.client.auth.currentUser?.id, _actor);
    });
  }

  for (final selected in [
    ['recipient-3'],
    ['recipient-3', 'recipient-1'],
    ['recipient-3', 'recipient-1', 'recipient-2'],
  ]) {
    test('save rereads then sends exactly one setter preserving ${selected.length} IDs', () async {
      final repository = await observedOn();
      final token = SupabaseBackend.client.auth.currentSession!.accessToken;
      _readResponses.add(_settings());
      await repository.save(_vehicle, selected);
      expect(_calls.map((request) => request.url.path), [
        '/rest/v1/rpc/get_vehicle_notification_settings',
        '/rest/v1/rpc/get_vehicle_notification_settings',
        '/rest/v1/rpc/set_vehicle_notification_assignees',
      ]);
      expect(jsonDecode(_calls.last.body), {
        'p_vehicle_id': _vehicle, 'p_user_ids': selected,
      });
      expect(_calls.every((request) => request.headers['authorization'] == 'Bearer $token'), true);
      expect(_readResponses, isEmpty);
      expect(SupabaseBackend.client.auth.currentUser?.id, _actor);
    });
  }
}
