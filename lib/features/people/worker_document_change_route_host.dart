import 'package:flutter/material.dart';

/// Keeps document routes and their dialogs below the document actor boundary.
/// It never pops or removes routes from the application's root navigator.
class WorkerDocumentChangeRouteHost extends StatefulWidget {
  const WorkerDocumentChangeRouteHost({
    super.key,
    required this.builder,
    required this.onClose,
  });
  final WidgetBuilder builder;
  final VoidCallback onClose;

  @override
  State<WorkerDocumentChangeRouteHost> createState() =>
      _WorkerDocumentChangeRouteHostState();
}

class _WorkerDocumentChangeRouteHostState
    extends State<WorkerDocumentChangeRouteHost> {
  final _navigator = GlobalKey<NavigatorState>();
  final _routes = _PreviewRoutes();
  bool _closing = false;

  void _close() {
    if (_closing) return;
    _closing = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onClose();
    });
  }

  Route<Object?> _route(RouteSettings settings) => _PreviewBaseRoute(
    settings: settings,
    builder: (context) => widget.builder(context),
    onClose: _close,
  );

  @override
  Widget build(BuildContext context) => NavigatorPopHandler<Object?>(
    onPopWithResult: (result) => _navigator.currentState?.maybePop(result),
    child: _PreviewNavigator(
      key: _navigator,
      observer: _routes,
      onGenerateRoute: _route,
    ),
  );
}

// Navigator disposal alone does not complete Route.popped. Only this host's
// still-active, uncompleted routes are completed; no outer navigator is touched.
class _PreviewRoutes extends NavigatorObserver {
  final _pending = <Route<dynamic>>{};

  void _track(Route<dynamic> route) {
    _pending.add(route);
    route.popped.then(
      (_) {
        _pending.remove(route);
      },
      onError: (Object error) {
        _pending.remove(route);
      },
    );
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _track(route);
  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _pending.remove(route);
  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _pending.remove(route);
  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    if (oldRoute != null) _pending.remove(oldRoute);
    if (newRoute != null) _track(newRoute);
  }

  void completeOwnedRoutes() {
    for (final route in _pending.toList(growable: false)) {
      if (_pending.remove(route) && route.isActive) {
        // Route.dispose does not resolve popped. The owning navigator is about
        // to be disposed without animation, matching didComplete's contract.
        // ignore: invalid_use_of_protected_member
        route.didComplete(null);
      }
    }
    _pending.clear();
  }
}

// Child elements unmount before their parents. Complete route futures inside
// the owned NavigatorState before its super.dispose clears the route history.
class _PreviewNavigator extends Navigator {
  _PreviewNavigator({
    super.key,
    required _PreviewRoutes observer,
    required RouteFactory onGenerateRoute,
  }) : _observer = observer,
       super(observers: [observer], onGenerateRoute: onGenerateRoute);
  final _PreviewRoutes _observer;
  @override
  NavigatorState createState() => _PreviewNavigatorState();
}

class _PreviewNavigatorState extends NavigatorState {
  @override
  void dispose() {
    (widget as _PreviewNavigator)._observer.completeOwnedRoutes();
    super.dispose();
  }
}

class _PreviewBaseRoute extends MaterialPageRoute<Object?> {
  _PreviewBaseRoute({
    required super.settings,
    required super.builder,
    required VoidCallback onClose,
  }) : _onClose = onClose;
  final VoidCallback _onClose;

  @override
  void install() {
    // ModalRoute's overlay entries (including _modalScope) must exist before
    // adding local history, which calls changedInternalState immediately.
    super.install();
    addLocalHistoryEntry(
      LocalHistoryEntry(impliesAppBarDismissal: true, onRemove: _onClose),
    );
  }
}
