import 'dart:convert';
import 'package:supabase_flutter/supabase_flutter.dart';

/// A UI lifetime key, never proof of authentication or authorization.
/// The SDK owns token validation; navigation must additionally separate sessions.
class AppleSessionNavigationBinding {
  const AppleSessionNavigationBinding._(this.actorId, this.sessionId);
  final String actorId;
  final String sessionId;
  static final _uuid = RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$');

  static AppleSessionNavigationBinding? fromSession(Session? session) {
    if (session == null) return null;
    try {
      final parts = session.accessToken.split('.');
      if (parts.length != 3) throw const FormatException();
      final claims = jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))));
      if (claims is! Map || claims['sub'] != session.user.id ||
          !_uuid.hasMatch(session.user.id) || claims['session_id'] is! String ||
          !_uuid.hasMatch(claims['session_id'] as String)) throw const FormatException();
      return AppleSessionNavigationBinding._(session.user.id, (claims['session_id'] as String).toLowerCase());
    } catch (_) { throw const FormatException('Invalid navigation session binding'); }
  }
  @override
  bool operator ==(Object other) => other is AppleSessionNavigationBinding &&
      actorId == other.actorId && sessionId == other.sessionId;
  @override
  int get hashCode => Object.hash(actorId, sessionId);
}
