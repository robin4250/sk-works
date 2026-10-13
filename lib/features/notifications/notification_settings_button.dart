import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// This status is the device permission, never an app sound preference or a
/// promise that an attendance event has been delivered.
enum OsNotificationPermission { enabled, disabled, notRequested, unknown }

class OsNotificationSettings {
  const OsNotificationSettings({
    this.channel = const MethodChannel('sko.notification_settings'),
  });
  final MethodChannel channel;

  Future<OsNotificationPermission> permission() async {
    final value = await channel.invokeMethod<String>('authorizationStatus');
    return switch (value) {
      'authorized' ||
      'provisional' ||
      'ephemeral' => OsNotificationPermission.enabled,
      'denied' => OsNotificationPermission.disabled,
      'notDetermined' => OsNotificationPermission.notRequested,
      _ => OsNotificationPermission.unknown,
    };
  }

  Future<bool> openSettings() async =>
      await channel.invokeMethod<bool>('openSettings') == true;
}

class NotificationSettingsButton extends StatefulWidget {
  const NotificationSettingsButton({
    super.key,
    this.settings = const OsNotificationSettings(),
  });
  final OsNotificationSettings settings;

  @override
  State<NotificationSettingsButton> createState() =>
      _NotificationSettingsButtonState();
}

class _NotificationSettingsButtonState extends State<NotificationSettingsButton>
    with WidgetsBindingObserver {
  OsNotificationPermission _permission = OsNotificationPermission.unknown;
  bool _loading = true;
  bool _opening = false;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _generation++;
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    final generation = ++_generation;
    setState(() => _loading = true);
    OsNotificationPermission permission;
    try {
      permission = await widget.settings.permission();
    } catch (_) {
      permission = OsNotificationPermission.unknown;
    }
    if (!mounted || generation != _generation) return;
    setState(() {
      _permission = permission;
      _loading = false;
    });
  }

  Future<void> _open() async {
    if (_opening) return;
    setState(() => _opening = true);
    try {
      if (!await widget.settings.openSettings()) {
        throw StateError('notification settings unavailable');
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('通知設定を開けませんでした。iPhoneの「設定」からSKOの通知許可を確認してください。'),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _opening = false);
        await _refresh();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final enabled =
        !_loading && _permission == OsNotificationPermission.enabled;
    final label = _loading
        ? '通知 確認中'
        : switch (_permission) {
            OsNotificationPermission.enabled => '通知 ON',
            OsNotificationPermission.disabled => '通知 OFF',
            OsNotificationPermission.notRequested => '通知 未許可',
            OsNotificationPermission.unknown => '通知 確認不可',
          };
    return Tooltip(
      message: '端末の通知許可を確認し、SKOのOS通知設定を開きます。アプリの通知音設定とは別です。',
      child: OutlinedButton.icon(
        onPressed: _opening ? null : _open,
        style: OutlinedButton.styleFrom(
          foregroundColor: enabled ? colors.primary : colors.onSurfaceVariant,
          backgroundColor: enabled
              ? colors.primaryContainer
              : colors.surfaceContainerHighest,
          side: BorderSide(color: enabled ? colors.primary : colors.outline),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          minimumSize: const Size(0, 36),
        ),
        icon: Icon(
          enabled
              ? Icons.notifications_active_outlined
              : Icons.notifications_off_outlined,
          size: 18,
        ),
        label: Text(label),
      ),
    );
  }
}
