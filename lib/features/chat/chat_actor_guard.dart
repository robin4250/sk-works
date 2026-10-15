import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Invalidates permanently on the first session epoch change, including A→B→A.
class ChatActorGuard extends StatefulWidget {
  const ChatActorGuard({super.key, required this.epoch, required this.initialEpoch, required this.child});
  final ValueListenable<int> epoch;
  final int initialEpoch;
  final Widget child;

  @override
  State<ChatActorGuard> createState() => _ChatActorGuardState();
}

class _ChatActorGuardState extends State<ChatActorGuard> {
  late final int _initialEpoch;
  bool _invalidated = false;

  @override
  void initState() {
    super.initState();
    _initialEpoch = widget.initialEpoch;
    widget.epoch.addListener(_changed);
    _changed();
  }

  void _changed() {
    if (_invalidated || widget.epoch.value == _initialEpoch) {
      return;
    }
    setState(() => _invalidated = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && ModalRoute.of(context)?.isCurrent == true && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
    });
  }

  @override
  void dispose() {
    widget.epoch.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _invalidated
      ? const SizedBox.shrink()
      : widget.child;
}
