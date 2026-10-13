import 'dart:async';

import 'package:flutter/material.dart';

import 'app_notification_repository.dart';
import '../../data/supabase_backend.dart';
import 'attention_center_repository.dart';
import 'attention_center_item.dart';
import '../../international/language_controller.dart';
import 'notifications_page.dart';

class SkoNotificationBell extends StatefulWidget {
  const SkoNotificationBell({super.key});

  @override
  State<SkoNotificationBell> createState() => _SkoNotificationBellState();
}

class _SkoNotificationBellState extends State<SkoNotificationBell> with WidgetsBindingObserver {
  final _repository = AppNotificationRepository.maybeCreate();
  int _unread = 0;
  Timer? _refreshTimer;
  bool _refreshing = false;
  int _generation = 0;
  String? _badgeActor;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
    _refreshTimer = Timer.periodic(const Duration(seconds: 60), (_) => _refresh());
  }

  @override
  void dispose() {
    ++_generation;
    _refreshTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    final repository = _repository;
    if (repository == null || !SupabaseBackend.isInitialized) return;
    final client = SupabaseBackend.client;
    final actor = client.auth.currentUser?.id;
    if (actor == null) {
      ++_generation;
      if (mounted) setState(() { _unread = 0; _badgeActor = null; });
      return;
    }
    if (_refreshing) return;
    final generation = ++_generation;
    if (_badgeActor != actor && mounted) {
      setState(() { _unread = 0; _badgeActor = actor; });
    }
    _refreshing = true;
    try {
      final unread = await repository.unreadTargets();
      var pending = const <AttentionCenterItem>[];
      try {
        pending = mapRouteBillingQuantityAttention(
          await client.rpc('pending_route_billing_quantity_rows'),
        );
      } catch (_) {
        // Keep the existing unread badge usable when this source is unavailable.
      }
      if (!mounted || generation != _generation) return;
      if (client.auth.currentUser?.id != actor) {
        setState(() { _unread = 0; _badgeActor = null; });
        return;
      }
      setState(() => _unread = routeAwareNotificationBadgeCount(unread, pending));
    } catch (_) {
      // A bell without a badge remains usable if notifications are unavailable.
    } finally {
      _refreshing = false;
    }
  }

  Future<void> _open() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const NotificationsPage()),
    );
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: SkoLanguageController.tr('お知らせ'),
      onPressed: _open,
      icon: Badge(
        isLabelVisible: _unread > 0,
        label: Text(_unread > 99 ? '99+' : '$_unread'),
        child: const Icon(Icons.notifications_outlined),
      ),
    );
  }
}

int routeAwareNotificationBadgeCount(
  List<AppNotificationRecord> unread, List<AttentionCenterItem> pending,
) {
  final targets = {for (final notice in unread)
    if (!notice.read && notice.actionKey == 'route_billing_quantity_request' &&
        notice.actionId != null) notice.actionId};
  final extra = {for (final task in pending)
    if (task.actionable && task.needsAction && !targets.contains(task.actionId))
      task.actionId};
  return unread.where((notice) => !notice.read).length + extra.length;
}
