import 'dart:async';
import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

/// A client verification belongs to one live SDK session, including its history.
/// This does not issue or replace a server-side reauthentication proof.
class SecondaryResetSessionGuard {
  SecondaryResetSessionGuard({
    required this.currentSession,
    required Stream<AuthState> changes,
    this.onInvalidated,
  }) {
    _identity = identityOf(currentSession());
    if (_identity == null) {
      throw StateError('ログイン状態を確認してください。');
    }
    _subscription = changes.listen((event) {
      if (event.event == AuthChangeEvent.signedOut ||
          identityOf(event.session) != _identity ||
          identityOf(currentSession()) != _identity) {
        _invalidate();
      }
    }, onError: (Object _) => _invalidate());
  }

  final Session? Function() currentSession;
  final void Function()? onInvalidated;
  late final String? _identity;
  StreamSubscription<AuthState>? _subscription;
  bool _invalidated = false;
  bool _closed = false;

  static String? identityOf(Session? session) {
    if (session == null || session.isExpired ||
        session.user.toJson()['is_anonymous'] == true) {
      return null;
    }
    try {
      final parts = session.accessToken.split('.');
      if (parts.length != 3) return null;
      final claims = jsonDecode(utf8.decode(base64Url.decode(
        base64Url.normalize(parts[1]))));
      final sid = claims is Map ? claims['session_id'] : null;
      if (claims is! Map || claims['sub'] != session.user.id ||
          claims['role'] != 'authenticated' || sid is! String || sid.isEmpty) {
        return null;
      }
      return '${session.user.id}/$sid';
    } catch (_) { return null; }
  }

  bool get isCurrent => !_closed && !_invalidated &&
      _identity != null && identityOf(currentSession()) == _identity;

  void _invalidate() {
    if (_closed || _invalidated) return;
    _invalidated = true;
    onInvalidated?.call();
  }

  Future<void> checkAfterQueuedEvents() async {
    if (!isCurrent) {
      _invalidate();
      throw StateError('ログイン状態が変わりました。本人確認をやり直してください。');
    }
    // Auth broadcasts are asynchronous; currentSession may already be back at A.
    await Future<void>.delayed(Duration.zero);
    if (!isCurrent) {
      _invalidate();
      throw StateError('ログイン状態が変わりました。本人確認をやり直してください。');
    }
  }

  Future<void> close() async {
    _closed = true;
    final subscription = _subscription;
    _subscription = null;
    await subscription?.cancel();
  }
}
