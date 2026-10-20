import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'admin_saved_qualification_photo_submission_repository.dart';
import 'qualification_photo_session_rpc.dart';

/// Unconnected SDK adapter. It does not own a session, refresh it, or install a
/// product route. The page must supply its selected scope and foreground stream.
class QualificationPhotoSessionRpcSupabase {
  QualificationPhotoSessionRpcSupabase({
    required SupabaseClient client,
    required AdminSavedQualificationPhotoSubmissionScope Function() scope,
    required Stream<AdminSavedQualificationPhotoSubmissionScope> scopeChanges,
    required bool Function() foreground,
    required Stream<bool> foregroundChanges,
    bool enabled = false,
  }) : _client = client,
       _scope = scope,
       _foreground = foreground {
    _guard = QualificationPhotoSessionRpc(
      current: _capture,
      transport: (function, params, headers) {
        if (function != QualificationPhotoSessionRpc.functionName ||
            headers.length != 1 ||
            !headers.containsKey('Authorization')) {
          throw StateError('資格写真の送信先を確認できません。');
        }
        return client
            .rpc(function, params: params)
            .setHeader('Authorization', headers['Authorization']!);
      },
      enabled: enabled,
    );
    if (!enabled) return;
    _auth = client.auth.onAuthStateChange.listen(
      (state) {
        if (state.event == AuthChangeEvent.signedOut) {
          _guard.invalidate();
          return;
        }
        _guard.observe(
          _capture(eventSession: state.session, useEventSession: true),
        );
      },
      onError: (Object _) => _guard.invalidate(),
      onDone: _guard.invalidate,
    );
    _context = scopeChanges.listen(
      (value) {
        _guard.observe(_capture(eventScope: value));
      },
      onError: (Object _) => _guard.invalidate(),
      onDone: _guard.invalidate,
    );
    _lifecycle = foregroundChanges.listen(
      (value) {
        _guard.observe(_capture(eventForeground: value));
      },
      onError: (Object _) => _guard.invalidate(),
      onDone: _guard.invalidate,
    );
  }

  final SupabaseClient _client;
  final AdminSavedQualificationPhotoSubmissionScope Function() _scope;
  final bool Function() _foreground;
  late final QualificationPhotoSessionRpc _guard;
  StreamSubscription<AuthState>? _auth;
  StreamSubscription<AdminSavedQualificationPhotoSubmissionScope>? _context;
  StreamSubscription<bool>? _lifecycle;

  QualificationPhotoRpcSession _capture({
    AdminSavedQualificationPhotoSubmissionScope? eventScope,
    Session? eventSession,
    bool useEventSession = false,
    bool? eventForeground,
  }) {
    final context = eventScope ?? _scope();
    final session = useEventSession
        ? eventSession
        : _client.auth.currentSession;
    return QualificationPhotoRpcSession(
      actorId: session?.user.id,
      companyId: context.companyId,
      targetId: context.targetId,
      accessToken: session?.accessToken,
      active:
          context.active &&
          (eventForeground ?? _foreground()) &&
          session != null &&
          !session.isExpired &&
          context.actorId == session.user.id,
    );
  }

  AdminSavedQualificationPhotoSubmissionScope scope() => _guard.scope();
  Stream<AdminSavedQualificationPhotoSubmissionScope> get scopeChanges =>
      _guard.scopeChanges;
  Future<AdminSavedQualificationPhotoAuthorization> authorization() =>
      _guard.authorization();
  Future<Object?> rpc(String action, Map<String, dynamic> data) =>
      _guard.rpc(action, data);
  void invalidate() => _guard.invalidate();

  Future<void> dispose() async {
    _guard.invalidate();
    await Future.wait([
      if (_auth != null) _auth!.cancel(),
      if (_context != null) _context!.cancel(),
      if (_lifecycle != null) _lifecycle!.cancel(),
    ]);
    await _guard.dispose();
  }
}
