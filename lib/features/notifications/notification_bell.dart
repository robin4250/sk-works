import 'dart:async';

import 'package:flutter/material.dart';

import 'app_notification_repository.dart';
import '../../data/supabase_backend.dart';
import 'attention_center_repository.dart';
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
    _refreshTimer = Timer.periodic(const Duration(seconds: 60), (_) => _refresh());
  }

  @override
  void dispose() {
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
    if (repository == null || _refreshing || !SupabaseBackend.isInitialized) return;
    final client = SupabaseBackend.client;
    final actor = client.auth.currentUser?.id;
    if (actor == null) return;
    _refreshing = true;
    try {
      final count = await repository.unreadCount();
      var pendingCount = 0;
      try {
        pendingCount = mapRouteBillingQuantityAttention(
          await client.rpc('pending_route_billing_quantity_rows'),
        ).length;
      } catch (_) {
        // Keep the existing unread badge usable when this source is unavailable.
      }
      if (!mounted || client.auth.currentUser?.id != actor) return;
      setState(() => _unread = count + pendingCount);
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
