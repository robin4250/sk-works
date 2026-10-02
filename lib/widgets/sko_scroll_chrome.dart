import 'package:flutter/material.dart';

class SkoScrollChromeController {
  SkoScrollChromeController._();

  static final ValueNotifier<bool> visible = ValueNotifier<bool>(true);

  static bool handle(ScrollNotification notification) {
    if (notification.metrics.axis != Axis.vertical) return false;

    if (notification is ScrollUpdateNotification) {
      final delta = notification.scrollDelta ?? 0;
      if (notification.metrics.pixels <= 2) {
        if (!visible.value) visible.value = true;
      } else if (delta > 2 && visible.value) {
        visible.value = false;
      } else if (delta < -2 && !visible.value) {
        visible.value = true;
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

class SkoGlobalScrollChrome extends StatelessWidget {
  const SkoGlobalScrollChrome({
    super.key,
    required this.child,
  });

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollNotification>(
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
            child: child,
          );
        },
      ),
    );
  }
}
