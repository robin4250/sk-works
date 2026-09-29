import 'package:flutter/material.dart';

import '../notifications/notification_bell.dart';
import 'master_device_repository.dart';

class MasterDeviceManagementPage extends StatefulWidget {
  const MasterDeviceManagementPage({super.key});

  @override
  State<MasterDeviceManagementPage> createState() =>
      _MasterDeviceManagementPageState();
}

class _MasterDeviceManagementPageState
    extends State<MasterDeviceManagementPage> {
  final _repository = MasterDeviceRepository.maybeCreate();

  List<MasterDeviceRecord> _devices = const [];
  bool _loading = true;
  String? _error;
  String? _busyDeviceId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final repository = _repository;
    if (repository == null) {
      setState(() {
        _loading = false;
        _error = 'マスターデバイス管理を利用できません。';
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      if (!await repository.isMasterAdmin()) {
        throw StateError('マスター管理者権限が必要です。');
      }
      final devices = await repository.loadDevices();
      if (!mounted) return;
      setState(() {
        _devices = devices;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _setLocked(MasterDeviceRecord device, bool locked) async {
    final repository = _repository;
    if (repository == null || device.isRevoked) return;

    setState(() => _busyDeviceId = device.id);
    try {
      await repository.setLocked(deviceId: device.id, locked: locked);
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(locked ? '端末をロックしました' : '端末のロックを解除しました')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('変更できませんでした: $error')),
      );
    } finally {
      if (mounted) setState(() => _busyDeviceId = null);
    }
  }

  Future<void> _revoke(MasterDeviceRecord device) async {
    final repository = _repository;
    if (repository == null || device.isRevoked) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('端末登録を解除'),
        content: Text(
          '「${device.deviceName}」のマスターデバイス登録を解除します。'
          '解除後はこの端末を信頼済み端末として利用できません。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('登録解除'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _busyDeviceId = device.id);
    try {
      await repository.revoke(device.id);
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('端末登録を解除しました')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('登録解除できませんでした: $error')),
      );
    } finally {
      if (mounted) setState(() => _busyDeviceId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('マスターデバイス管理'),
        actions: [
          const SkoNotificationBell(),
          IconButton(
            tooltip: '再読み込み',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? _ErrorState(message: _error!, onRetry: _load)
                : _devices.isEmpty
                    ? const _EmptyState()
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: ListView.separated(
                          padding: const EdgeInsets.all(16),
                          itemCount: _devices.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 10),
                          itemBuilder: (context, index) {
                            final device = _devices[index];
                            final busy = _busyDeviceId == device.id;
                            return _DeviceCard(
                              device: device,
                              busy: busy,
                              onToggleLock: () => _setLocked(
                                device,
                                !device.isLocked,
                              ),
                              onRevoke: () => _revoke(device),
                            );
                          },
                        ),
                      ),
      ),
    );
  }
}

class _DeviceCard extends StatelessWidget {
  const _DeviceCard({
    required this.device,
    required this.busy,
    required this.onToggleLock,
    required this.onRevoke,
  });

  final MasterDeviceRecord device;
  final bool busy;
  final VoidCallback onToggleLock;
  final VoidCallback onRevoke;

  @override
  Widget build(BuildContext context) {
    final status = device.isRevoked
        ? '登録解除済み'
        : device.isLocked
            ? 'ロック中'
            : '有効';

    final platformSuffix =
        device.platform?.trim().isNotEmpty == true ? ' / ${device.platform}' : '';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(_iconFor(device.deviceType), size: 30),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        device.deviceName,
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                      Text('${device.typeLabel}$platformSuffix'),
                    ],
                  ),
                ),
                Chip(label: Text(status)),
              ],
            ),
            const SizedBox(height: 12),
            Text('登録日時: ${_dateTime(device.registeredAt)}'),
            Text(
              '最終利用: ${device.lastUsedAt == null ? '未記録' : _dateTime(device.lastUsedAt!)}',
            ),
            const SizedBox(height: 12),
            if (!device.isRevoked)
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: busy ? null : onToggleLock,
                    icon: Icon(
                      device.isLocked
                          ? Icons.lock_open_outlined
                          : Icons.lock_outline,
                    ),
                    label: Text(device.isLocked ? 'ロック解除' : 'ロック'),
                  ),
                  OutlinedButton.icon(
                    onPressed: busy ? null : onRevoke,
                    icon: const Icon(Icons.phonelink_erase_outlined),
                    label: const Text('登録解除'),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  static IconData _iconFor(String type) => switch (type) {
        'iphone' => Icons.phone_iphone,
        'ipad' => Icons.tablet_mac,
        'mac' => Icons.laptop_mac,
        _ => Icons.devices_other,
      };

  static String _dateTime(DateTime value) =>
      '${value.year}/${value.month.toString().padLeft(2, '0')}/${value.day.toString().padLeft(2, '0')} '
      '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.devices_other, size: 56),
            SizedBox(height: 12),
            Text(
              '信頼済みマスターデバイスはまだありません',
              textAlign: TextAlign.center,
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
            SizedBox(height: 8),
            Text(
              '新端末の登録フローは次の実装で追加します。',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({
    required this.message,
    required this.onRetry,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('再読み込み'),
            ),
          ],
        ),
      ),
    );
  }
}
