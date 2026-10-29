import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/supabase_backend.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'apple_session_navigation_binding.dart';
import 'app_auth_mutation_gateway.dart';

/// Recreate the entire Navigator after an identity transition. Removing it for
/// one frame disposes pushed private pages before a global Navigator key is reused.
class AuthenticatedNavigationBoundary extends StatefulWidget {
  const AuthenticatedNavigationBoundary({
    super.key,
    required this.child,
    @visibleForTesting this.initialSession,
    @visibleForTesting this.authChanges,
    @visibleForTesting this.mutationGateway,
  });
  final Widget child;
  final Session? initialSession;
  final Stream<AuthState>? authChanges;
  final AppAuthMutationGateway? mutationGateway;

  @override
  State<AuthenticatedNavigationBoundary> createState() =>
      _AuthenticatedNavigationBoundaryState();
}

class _AuthenticatedNavigationBoundaryState
    extends State<AuthenticatedNavigationBoundary> {
  StreamSubscription<AuthState>? _subscription;
  StreamSubscription<AppLogoutQuarantineState>? _logoutSubscription;
  AppAuthMutationGateway? _gateway;
  AppLogoutQuarantineState _logoutState = AppLogoutQuarantineState.clear;
  AppleSessionNavigationBinding? _binding;
  int _epoch = 0;
  bool _resetting = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _gateway = widget.mutationGateway ?? (SupabaseBackend.isInitialized
        ? AppAuthMutationGateway.forClient(SupabaseBackend.client) : null);
    final signal = _gateway?.logoutQuarantine;
    if (signal != null) {
      _logoutState = signal.state;
      _logoutSubscription = signal.changes.listen(_logoutChanged,
          onError: (Object _) => _logoutChanged(AppLogoutQuarantineState.failed),
          onDone: () => _logoutChanged(AppLogoutQuarantineState.failed));
    }
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
      try {
        binding = event.event == AuthChangeEvent.signedOut
            ? null : AppleSessionNavigationBinding.fromSession(event.session);
      }
      catch (_) { _fail(); return; }
      if (binding == _binding && !_failed) return;
      final previous = _binding;
      _binding = binding;
      // Only the first valid SDK sign-in belongs to the pending OTP callback.
      if (previous == null && binding != null &&
          event.event == AuthChangeEvent.signedIn && !_failed && !_resetting) {
        return;
      }
      _reset();
    }, onError: (Object error) => _fail(), onDone: _fail);
  }

  void _logoutChanged(AppLogoutQuarantineState state) {
    if (!mounted) return;
    setState(() { _logoutState = state; _epoch++; });
    if (state == AppLogoutQuarantineState.clear) {
      // Keep the old Navigator absent for a frame before reusing its global key.
      setState(() => _resetting = true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _resetting = false);
      });
    }
  }

  Future<void> _retryLogout() async {
    try { await _gateway?.signOut(); }
    catch (_) { /* The signal keeps the safe retry screen blocked. */ }
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
    _logoutSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _logoutState != AppLogoutQuarantineState.clear
      ? Directionality(
          textDirection: TextDirection.ltr,
          child: Material(color: Colors.white, child: Center(child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_logoutState == AppLogoutQuarantineState.failed
                  ? 'ログアウト状態を確認できません。'
                  : 'ログアウト状態を確認しています。'),
              if (_logoutState == AppLogoutQuarantineState.failed)
                TextButton(onPressed: _retryLogout, child: const Text('ログアウトを再試行')),
            ],
          ))),
        )
      : _failed || _resetting
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
