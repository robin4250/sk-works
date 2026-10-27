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
  final _badge = NotificationBadgeRefresh();
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
    _refreshTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
        _refresh();
      }
    });
  }

  @override
  void dispose() {
    _badge.invalidate();
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
    await _badge.refresh(
      currentActor: () => client.auth.currentUser?.id,
      loadUnread: repository.unreadTargets,
      loadPending: () async {
        Future<List<AttentionCenterItem>> route() async =>
            mapRouteBillingQuantityAttention(
              await client.rpc('pending_route_billing_quantity_rows'));
        Future<List<AttentionCenterItem>> photos() async =>
            mapQualificationPhotoAttention(
              await client.rpc('personal_qualification_submission',
                params: {'p_action': 'list', 'p_data': <String, dynamic>{}}));
        final sources = await Future.wait([route(), photos()]);
        return sources.expand((items) => items).toList();
      },
    );
    if (mounted) setState(() {});
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
      tooltip: SkoLanguageController.tr(_badge.uncertain ? 'お知らせを確認できません' : 'お知らせ'),
      onPressed: _open,
      icon: Badge(
        isLabelVisible: _badge.uncertain || _badge.count > 0,
        label: Text(_badge.uncertain ? '!' : _badge.count > 99 ? '99+' : '${_badge.count}'),
        child: const Icon(Icons.notifications_outlined, color: Color(0xFFFBC02D)),
      ),
    );
  }
}

int routeAwareNotificationBadgeCount(
  List<AppNotificationRecord> unread, List<AttentionCenterItem> pending,
) {
  final targets = {for (final notice in unread)
    if (!notice.read &&
        const {'route_billing_quantity_request', 'qualification_photo_request'}.contains(notice.actionKey) &&
        notice.actionId != null) '${notice.actionKey}:${notice.actionId}'};
  final extra = {for (final task in pending)
    if (task.actionable && task.needsAction && !targets.contains('${task.actionKey}:${task.actionId}'))
      '${task.actionKey}:${task.actionId}'};
  return unread.where((notice) => !notice.read).length + extra.length;
}

/// Account-bound, overlap-safe badge refresh. Old account responses are discarded.
class NotificationBadgeRefresh {
  int count = 0;
  bool uncertain = false;
  String? _actor;
  int _generation = 0;
  bool _busy = false;

  void invalidate() { ++_generation; count = 0; uncertain = false; _actor = null; }

  Future<void> refresh({
    required String? Function() currentActor,
    required Future<List<AppNotificationRecord>> Function() loadUnread,
    required Future<List<AttentionCenterItem>> Function() loadPending,
  }) async {
    final actor = currentActor();
    if (_actor != actor) { invalidate(); _actor = actor; }
    if (actor == null || _busy) return;
    _busy = true;
    uncertain = true;
    final generation = ++_generation;
    try {
      final unread = await loadUnread();
      if (generation != _generation || currentActor() != actor) {
        invalidate(); return;
      }
      var pending = const <AttentionCenterItem>[];
      var pendingFailed = false;
      try { pending = await loadPending(); } catch (_) {
        pendingFailed = true;
      }
      if (generation != _generation || currentActor() != actor) {
        invalidate(); return;
      }
      count = routeAwareNotificationBadgeCount(unread, pending);
      uncertain = pendingFailed;
    } catch (_) {
      if (currentActor() != actor) { invalidate(); } else { uncertain = true; }
      // Keep the last count, but mark it as unverified.
    } finally { _busy = false; }
  }
}
