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

  static bool responseAvailable(Object? value) => value is Map &&
      value['version'] is int && value['version'] == 1 && value['available'] == true;

  Future<bool> available() async {
    final expected = actor;
    if (expected == null) return false;
    try {
      final value = await client.rpc('line_release_capability');
      return actor == expected && responseAvailable(value);
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
    if (pollInterval > Duration.zero) {
      _timer = Timer.periodic(pollInterval, (_) => refresh());
    }
    unawaited(refresh());
  }
  final Future<bool> Function() read;
  final String? Function() currentActor;
  final Duration pollInterval;
  final bool _observeLifecycle;
  StreamSubscription<String?>? _actors;
  Timer? _timer;
  String? _actor;
  int _generation = 0, _revision = 0;
  int get revision => _revision;
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
    _revision++;
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
    if (_allowed && !result) _revision++;
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
class LineReleaseBoundary extends StatefulWidget {
  const LineReleaseBoundary({super.key, required this.builder});
  final WidgetBuilder builder;
  @override
  State<LineReleaseBoundary> createState() => _LineReleaseBoundaryState();
}
class _LineReleaseBoundaryState extends State<LineReleaseBoundary> {
  LineReleaseAccess? _access;
  ModalRoute<dynamic>? _route;
  NavigatorState? _navigator;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _route = ModalRoute.of(context);
    _navigator = Navigator.maybeOf(context);
    final next = LineReleaseScope.of(context) ?? LineReleaseAccess.maybeCreate();
    if (!identical(next, _access)) {
      _access?.removeListener(_changed);
      _access = next;
      _access?.addListener(_changed);
    }
  }
  void _changed() {
    // Dialogs/pickers opened from a LINE page are separate Navigator routes.
    // Remove those routes too so a revoked parent's old data cannot remain above it.
    final route = _route;
    if (mounted && _access?.available != true && route?.isActive == true) {
      _navigator?.popUntil((candidate) => identical(candidate, route));
    }
  }
  @override
  void dispose() { _access?.removeListener(_changed); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    final access = _access;
    if (access == null) return const _UnavailableLine();
    return AnimatedBuilder(animation: access, builder: (context, _) {
      if (!access.available) return const _UnavailableLine();
      return Stack(children: [
        Offstage(offstage: !access.visible, child: KeyedSubtree(
          key: ValueKey(access.revision), child: widget.builder(context))),
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

/// Modal routes are siblings of the protected page, so protect their contents
/// explicitly too. Ordinary SKO-only dialogs can opt out of this LINE boundary.
class LineReleaseOverlay extends StatelessWidget {
  const LineReleaseOverlay({super.key, required this.child, this.guardLine = true});
  final Widget child;
  final bool guardLine;
  @override
  Widget build(BuildContext context) {
    if (!guardLine) return child;
    final access = LineReleaseScope.of(context) ?? LineReleaseAccess.maybeCreate();
    if (access == null) return const SizedBox.shrink();
    return AnimatedBuilder(animation: access, builder: (context, _) {
      if (!access.available) return const SizedBox.shrink();
      return Offstage(offstage: !access.visible, child: child);
    });
  }
}
