import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/supabase_backend.dart';

/// Recreate the entire Navigator after an identity transition. Removing it for
/// one frame disposes pushed private pages before a global Navigator key is reused.
class AuthenticatedNavigationBoundary extends StatefulWidget {
  const AuthenticatedNavigationBoundary({
    super.key,
    required this.child,
    @visibleForTesting this.initialActor,
    @visibleForTesting this.actorChanges,
  });
  final Widget child;
  final String? initialActor;
  final Stream<String?>? actorChanges;

  @override
  State<AuthenticatedNavigationBoundary> createState() =>
      _AuthenticatedNavigationBoundaryState();
}

class _AuthenticatedNavigationBoundaryState
    extends State<AuthenticatedNavigationBoundary> {
  StreamSubscription<String?>? _subscription;
  String? _actor;
  int _epoch = 0;
  bool _resetting = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    if (!SupabaseBackend.isInitialized && widget.actorChanges == null) return;
    _actor = widget.initialActor ??
        (SupabaseBackend.isInitialized
            ? SupabaseBackend.client.auth.currentUser?.id : null);
    final changes = widget.actorChanges ??
        SupabaseBackend.client.auth.onAuthStateChange
            .map((event) => event.session?.user.id);
    _subscription = changes.listen((actor) {
      if (!mounted || (actor == _actor && !_failed)) return;
      _actor = actor;
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
