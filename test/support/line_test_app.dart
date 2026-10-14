import 'dart:async';
import 'package:flutter/material.dart';
import 'package:sk_works/features/chat/line_release_access.dart';

/// Existing feature tests explicitly model an authenticated, released server.
/// Production missing/error/actor-change behavior is tested separately.
class LineTestApp extends StatefulWidget {
  const LineTestApp({super.key, required this.home, this.builder});
  final Widget home;
  final TransitionBuilder? builder;
  @override
  State<LineTestApp> createState() => _LineTestAppState();
}
class _LineTestAppState extends State<LineTestApp> {
  late final access = LineReleaseAccess(read: () async => true,
    currentActor: () => 'fixture-actor', actorChanges: const Stream.empty(),
    observeLifecycle: false, pollInterval: Duration.zero);
  @override
  void dispose() { access.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => LineReleaseScope(access: access,
    child: MaterialApp(home: widget.home, builder: widget.builder));
}
