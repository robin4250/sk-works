import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

/// Recognizes only the first queued SDK replay at subscription time.
///
/// Pinned GoTrue may restore the same serialized session into a new object
/// without replacing its cached initialSession event. Object identity alone
/// therefore cannot identify that startup replay. This never accepts a new
/// live transition, nor a current session object replaced after capture.
class SdkSessionReplayBaseline {
  SdkSessionReplayBaseline(this._captured)
      : _snapshot = _encode(_captured);

  Session? _captured;
  String? _snapshot;
  bool _first = true;
  bool _open = true;

  static String? _encode(Session? session) {
    if (session == null) return null;
    try {
      return jsonEncode(session.toJson());
    } catch (_) {
      return null;
    }
  }

  bool consume(AuthState event, Session? current) {
    final first = _first && _open;
    _first = false;
    if (!first || !identical(current, _captured)) return false;
    if (_captured != null && _snapshot == null) return false;
    if (identical(event.session, _captured)) {
      return event.event == AuthChangeEvent.initialSession ||
          (_captured != null && event.event != AuthChangeEvent.signedOut);
    }
    // Only initialSession can be the older object retained by cold restore.
    // Compare the complete SDK serialization, including credentials, absolute
    // expiry and user fields; equality of actor/SID alone is insufficient.
    return event.event == AuthChangeEvent.initialSession &&
        event.session != null &&
        _snapshot != null &&
        _encode(event.session) == _snapshot;
  }

  void close() {
    _open = false;
    // Do not retain the startup credential snapshot in the long-lived gateway.
    _captured = null;
    _snapshot = null;
  }
}
