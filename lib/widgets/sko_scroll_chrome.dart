import 'package:flutter/material.dart';

class SkoScrollChromeController {
  SkoScrollChromeController._();

  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();
  static final ValueNotifier<bool> visible = ValueNotifier<bool>(true);

  static double _dragDistance = 0;

  static bool handle(ScrollNotification notification) {
    if (notification.metrics.axis != Axis.vertical) return false;

    if (notification is ScrollStartNotification ||
        notification is ScrollEndNotification) {
      _dragDistance = 0;
    }

    if (notification is ScrollUpdateNotification) {
      if (notification.metrics.pixels <= 2) {
        _dragDistance = 0;
        if (!visible.value) visible.value = true;
      } else if (notification.dragDetails != null) {
        // Ignore inertial rebound and require a deliberate direction change.
        // Tiny finger oscillations otherwise rebuild the entire app shell.
        final delta = notification.scrollDelta ?? 0;
        if (delta != 0) {
          if (_dragDistance.sign != delta.sign) _dragDistance = 0;
          _dragDistance += delta;
          if (_dragDistance.abs() >= 24) {
            final next = _dragDistance < 0;
            _dragDistance = 0;
            if (visible.value != next) visible.value = next;
          }
        }
      }
    }

    if (notification is ScrollEndNotification &&
        notification.metrics.pixels <= 2 &&
        !visible.value) {
      visible.value = true;
    }

    return false;
  }
}

class SkoGlobalScrollChrome extends StatefulWidget {
  const SkoGlobalScrollChrome({
    super.key,
    required this.child,
  });

  final Widget child;

  @override
  State<SkoGlobalScrollChrome> createState() => _SkoGlobalScrollChromeState();
}

class _SkoGlobalScrollChromeState extends State<SkoGlobalScrollChrome> {
  int? _edgePointer;
  Offset? _edgeStart;
  bool _edgeTriggered = false;

  void _pointerDown(PointerDownEvent event) {
    if (event.position.dx > 24) return;
    _edgePointer = event.pointer;
    _edgeStart = event.position;
    _edgeTriggered = false;
  }

  void _pointerMove(PointerMoveEvent event) {
    if (_edgePointer != event.pointer || _edgeTriggered) return;
    final start = _edgeStart;
    if (start == null) return;
    final dx = event.position.dx - start.dx;
    final dy = (event.position.dy - start.dy).abs();
    if (dx >= 72 && dx > dy * 1.4) {
      _edgeTriggered = true;
      SkoScrollChromeController.navigatorKey.currentState?.maybePop();
    }
  }

  void _pointerEnd(PointerEvent event) {
    if (_edgePointer != event.pointer) return;
    _edgePointer = null;
    _edgeStart = null;
    _edgeTriggered = false;
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _pointerDown,
      onPointerMove: _pointerMove,
      onPointerUp: _pointerEnd,
      onPointerCancel: _pointerEnd,
      child: NotificationListener<ScrollNotification>(
        onNotification: SkoScrollChromeController.handle,
        child: ValueListenableBuilder<bool>(
          valueListenable: SkoScrollChromeController.visible,
          builder: (context, visible, _) {
            final theme = Theme.of(context);
            return Theme(
              data: theme.copyWith(
                appBarTheme: theme.appBarTheme.copyWith(
                  toolbarHeight: visible ? kToolbarHeight : 0,
                ),
              ),
              child: widget.child,
            );
          },
        ),
      ),
    );
  }
}
