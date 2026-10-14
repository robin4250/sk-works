import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/supabase_backend.dart';

/// Server capability only. Company/group permissions still apply separately.
class LineReleaseRepository {
  LineReleaseRepository(this.client);
  final SupabaseClient client;
  String? get actor => client.auth.currentUser?.id;
  Stream<String?> get actorChanges => client.auth.onAuthStateChange
      .map((state) => state.session?.user.id).distinct();

  Future<bool> available() async {
    final expected = actor;
    if (expected == null) return false;
    try {
      final value = await client.rpc('line_release_capability');
      return actor == expected && value is Map &&
          value['version'] == 1 && value['available'] == true;
    } catch (_) {
      return false;
    }
  }
}

/// An actor-bound, fail-closed capability shared by every visible LINE surface.
class LineReleaseAccess extends ChangeNotifier with WidgetsBindingObserver {
  LineReleaseAccess({required this.read, required this.currentActor,
    required Stream<String?> actorChanges, this.pollInterval = const Duration(seconds: 30),
    bool observeLifecycle = true}) : _observeLifecycle = observeLifecycle {
    _actor = currentActor();
    _actors = actorChanges.listen(_actorChanged, onError: (Object _) => _revoke());
    if (_observeLifecycle) WidgetsBinding.instance.addObserver(this);
    _timer = Timer.periodic(pollInterval, (_) => refresh());
    unawaited(refresh());
  }
  final Future<bool> Function() read;
  final String? Function() currentActor;
  final Duration pollInterval;
  final bool _observeLifecycle;
  StreamSubscription<String?>? _actors;
  Timer? _timer;
  String? _actor;
  int _generation = 0;
  bool _disposed = false, _allowed = false, _foreground = true, _checking = true;
  bool get available => !_disposed && _allowed && _actor != null && currentActor() == _actor;
  bool get visible => available && _foreground && !_checking;

  static LineReleaseAccess? _shared;
  static LineReleaseAccess? maybeCreate() {
    if (!SupabaseBackend.isInitialized) return null;
    return _shared ??= () {
      final repository = LineReleaseRepository(SupabaseBackend.client);
      return LineReleaseAccess(read: repository.available,
        currentActor: () => repository.actor, actorChanges: repository.actorChanges);
    }();
  }
  void _revoke() {
    _generation++;
    _allowed = false;
    _checking = false;
    if (!_disposed) notifyListeners();
  }
  void _actorChanged(String? actor) {
    if (_disposed || actor == _actor) return;
    _actor = actor;
    _revoke();
    unawaited(refresh());
  }
  Future<void> refresh() async {
    if (_disposed || !_foreground) return;
    final expected = currentActor();
    if (expected != _actor) {
      _actor = expected;
      _revoke();
    }
    final generation = ++_generation;
    if (expected == null) { _revoke(); return; }
    bool result;
    try { result = await read(); } catch (_) { result = false; }
    if (_disposed || generation != _generation || currentActor() != expected) return;
    _allowed = result;
    _checking = false;
    notifyListeners();
  }
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _generation++;
    _checking = true;
    notifyListeners();
    if (_foreground) unawaited(refresh());
  }
  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _timer?.cancel();
    _actors?.cancel();
    if (_observeLifecycle) WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}

/// Allows tests to inject the same real state machine without a client bypass.
class LineReleaseScope extends InheritedWidget {
  const LineReleaseScope({super.key, required this.access, required super.child});
  final LineReleaseAccess access;
  static LineReleaseAccess? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<LineReleaseScope>()?.access;
  @override
  bool updateShouldNotify(LineReleaseScope oldWidget) => oldWidget.access != access;
}

/// The protected child is created only after confirmation; revocation disposes
/// its entire state, including cached text, previews, drafts and async readers.
class LineReleaseBoundary extends StatelessWidget {
  const LineReleaseBoundary({super.key, required this.builder});
  final WidgetBuilder builder;
  @override
  Widget build(BuildContext context) {
    final access = LineReleaseScope.of(context) ?? LineReleaseAccess.maybeCreate();
    if (access == null) return const _UnavailableLine();
    return AnimatedBuilder(animation: access, builder: (context, _) {
      if (!access.available) return const _UnavailableLine();
      return Stack(children: [
        Offstage(offstage: !access.visible, child: builder(context)),
        if (!access.visible) const _UnavailableLine(),
      ]);
    });
  }
}

class _UnavailableLine extends StatelessWidget {
  const _UnavailableLine();
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('LINEトーク')),
    body: const Center(child: Padding(padding: EdgeInsets.all(24),
      child: Text('LINEトークは現在利用できません。'))),
  );
}
