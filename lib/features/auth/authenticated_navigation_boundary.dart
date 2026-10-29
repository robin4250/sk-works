import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/supabase_backend.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'apple_session_navigation_binding.dart';

/// Recreate the entire Navigator after an identity transition. Removing it for
/// one frame disposes pushed private pages before a global Navigator key is reused.
class AuthenticatedNavigationBoundary extends StatefulWidget {
  const AuthenticatedNavigationBoundary({
    super.key,
    required this.child,
    @visibleForTesting this.initialSession,
    @visibleForTesting this.authChanges,
  });
  final Widget child;
  final Session? initialSession;
  final Stream<AuthState>? authChanges;

  @override
  State<AuthenticatedNavigationBoundary> createState() =>
      _AuthenticatedNavigationBoundaryState();
}

class _AuthenticatedNavigationBoundaryState
    extends State<AuthenticatedNavigationBoundary> {
  StreamSubscription<AuthState>? _subscription;
  AppleSessionNavigationBinding? _binding;
  int _epoch = 0;
  bool _resetting = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    if (!SupabaseBackend.isInitialized && widget.authChanges == null) return;
    try {
      _binding = AppleSessionNavigationBinding.fromSession(widget.initialSession ??
          (SupabaseBackend.isInitialized
              ? SupabaseBackend.client.auth.currentSession : null));
    } catch (_) { _failed = true; }
    final changes = widget.authChanges ??
        SupabaseBackend.client.auth.onAuthStateChange;
    _subscription = changes.listen((event) {
      if (!mounted) return;
      AppleSessionNavigationBinding? binding;
      try { binding = AppleSessionNavigationBinding.fromSession(event.session); }
      catch (_) { _fail(); return; }
      if (binding == _binding && !_failed) return;
      final previous = _binding;
      _binding = binding;
      // Only the first valid SDK sign-in belongs to the pending OTP callback.
      if (previous == null && binding != null &&
          event.event == AuthChangeEvent.signedIn && !_failed && !_resetting) return;
      _reset();
    }, onError: (Object error) => _fail(), onDone: _fail);
  }

  void _fail() {
    if (!mounted) return;
    setState(() {
      _failed = true;
      _epoch++;
    });
  }

  void _reset() {
    setState(() {
      _failed = false;
      _epoch++;
    });
    if (_resetting) return;
    setState(() => _resetting = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _resetting = false);
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _failed || _resetting
      ? Directionality(
          textDirection: TextDirection.ltr,
          child: ColoredBox(
            color: Colors.white,
            child: Center(child: Text(_failed
                ? 'ログイン状態を確認できません。アプリを開き直してください。'
                : 'ログイン状態を確認しています。')),
          ),
        )
      : KeyedSubtree(key: ValueKey(_epoch), child: widget.child);
}
