// UI-unit fixture only: explicit synthetic auth scope, no SDK transport/server
// authentication. Faked auxiliary repositories must use this same actor.
import 'dart:convert';
import 'package:supabase_flutter/supabase_flutter.dart';

const qualificationUiActorId = '11111111-1111-4111-8111-111111111111';
const qualificationUiSessionId = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
mixin QualificationUiSessionFixture {
  String? get currentUserId => qualificationUiActorId;
  late final Session _qualificationUiSession = _session();
  Session? get currentSession => _qualificationUiSession;
  Stream<AuthState> get attachmentAuthChanges =>
      const Stream<AuthState>.empty();
}
Session _session() {
  String part(Object value) =>
      base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  final payload = {
    'sub': qualificationUiActorId,
    'session_id': qualificationUiSessionId,
    'role': 'authenticated',
    'exp': 4102444800,
  };
  return Session.fromJson({
    'access_token': '${part({'alg': 'HS256'})}.${part(payload)}.fixture',
    'refresh_token': 'synthetic-refresh',
    'token_type': 'bearer',
    'expires_at': 4102444800,
    'user': {
      'id': qualificationUiActorId,
      'aud': 'authenticated',
      'role': 'authenticated',
      'app_metadata': <String, dynamic>{},
      'user_metadata': <String, dynamic>{},
      'created_at': '2026-01-01T00:00:00Z',
    },
  })!;
}
