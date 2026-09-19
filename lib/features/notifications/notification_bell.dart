import 'package:flutter/material.dart';

import 'app_notification_repository.dart';
import 'notifications_page.dart';

class SkoNotificationBell extends StatefulWidget {
  const SkoNotificationBell({super.key});

  @override
  State<SkoNotificationBell> createState() => _SkoNotificationBellState();
}

class _SkoNotificationBellState extends State<SkoNotificationBell> {
  final _repository = AppNotificationRepository.maybeCreate();
  int _unread = 0;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final repository = _repository;
    if (repository == null) return;
    try {
      final count = await repository.unreadCount();
      if (!mounted) return;
      setState(() => _unread = count);
    } catch (_) {
      // A bell without a badge remains usable if notifications are unavailable.
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
      tooltip: 'お知らせ',
      onPressed: _open,
      icon: Badge(
        isLabelVisible: _unread > 0,
        label: Text(_unread > 99 ? '99+' : '$_unread'),
        child: const Icon(Icons.notifications_outlined),
      ),
    );
  }
}
