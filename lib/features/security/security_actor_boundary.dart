import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../data/supabase_backend.dart';

/// Revocation is sticky: returning to the original account must open a new route.
class SecurityActorBoundary extends StatefulWidget {
  const SecurityActorBoundary({
    super.key,
    required this.child,
    this.initialActor,
    @visibleForTesting this.actorChanges,
  });

  final Widget child;
  final String? initialActor;
  final Stream<String?>? actorChanges;

  @override
  State<SecurityActorBoundary> createState() => _SecurityActorBoundaryState();
}

class _SecurityActorBoundaryState extends State<SecurityActorBoundary> {
  StreamSubscription<String?>? _subscription;
  late final String? _actor;
  bool _revoked = false;

  @override
  void initState() {
    super.initState();
    final initialized = SupabaseBackend.isInitialized;
    _actor = widget.initialActor ??
        (initialized ? SupabaseBackend.client.auth.currentUser?.id : null);
    _revoked = _actor == null ||
        (initialized && SupabaseBackend.client.auth.currentUser?.id != _actor);
    final changes = widget.actorChanges ??
        (initialized
            ? SupabaseBackend.client.auth.onAuthStateChange
                .map((event) => event.session?.user.id)
            : const Stream<String?>.empty());
    _subscription = changes.listen((actor) {
      if (mounted && !_revoked && actor != _actor) {
        setState(() => _revoked = true);
      }
    }, onError: (Object error) {
      if (mounted) {
        setState(() => _revoked = true);
      }
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _revoked
      ? Scaffold(
          appBar: AppBar(title: const Text('セキュリティ記録')),
          body: const Center(child: Text('本人確認が失効しました。画面を閉じて開き直してください。')),
        )
      : widget.child;
}
