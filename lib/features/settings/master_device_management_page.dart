import 'dart:async';

import 'package:flutter/material.dart';

import '../notifications/notification_bell.dart';
import 'master_device_repository.dart';
import '../auth/operation_reauthentication_repository.dart';
import 'master_device_lock_proof_dialog.dart';

@visibleForTesting
bool removesLastUsableMasterDevice(List<MasterDeviceRecord> devices, MasterDeviceRecord target) =>
    !target.isRevoked && !target.isLocked &&
    !devices.any((d) => d.id != target.id && !d.isRevoked && !d.isLocked);

class MasterDeviceManagementPage extends StatefulWidget {
  const MasterDeviceManagementPage({super.key, this.repository, this.reauthentication});
  @visibleForTesting final MasterDeviceRepository? repository;
  @visibleForTesting final OperationReauthenticationRepository? reauthentication;

  @override
  State<MasterDeviceManagementPage> createState() =>
      _MasterDeviceManagementPageState();
}

class _MasterDeviceManagementPageState
    extends State<MasterDeviceManagementPage> {
  late final _repository = widget.repository ?? MasterDeviceRepository.maybeCreate();

  MasterDeviceSession? _session;
  int _loadGeneration = 0;

  bool get _current => mounted && _session?.isCurrent == true;
  void _invalidate() {
    if (!mounted) return;
    _loadGeneration++;
    setState(() {
      _devices = const []; _loading = false; _busyDeviceId = null;
      _error = 'ログイン状態が変わりました。画面を開き直してください。';
    });
  }

  List<MasterDeviceRecord> _devices = const [];
  bool _loading = true;
  String? _error;
  String? _busyDeviceId;
  bool _confirmingLoss = false;

  @override
  void initState() {
    super.initState();
    try { _session = _repository?.beginSession(onInvalidated: _invalidate); } catch (_) {
      _loading = false; _error = 'ログイン状態を確認してください。';
      return;
    }
    _load();
  }

  @override
  void dispose() {
    _loadGeneration++;
    final session = _session;
    if (session != null) unawaited(session.close());
    super.dispose();
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

    if (!mounted || !_current) return;
    final generation = ++_loadGeneration;
    final session = _session!;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      if (!await repository.isMasterAdmin(session: session)) {
        throw StateError('マスター管理者権限が必要です。');
      }
      await session.check();
      final devices = await repository.loadDevices(session: session);
      await session.check();
      if (!mounted || !_current || generation != _loadGeneration) return;
      setState(() {
        _devices = devices;
        _loading = false;
      });
    } catch (error) {
      if (!mounted || !_current || generation != _loadGeneration) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  Future<bool> _confirmLoss(MasterDeviceRecord device, String operation) async {
    if (!mounted || !_current || _confirmingLoss) return false;
    _confirmingLoss = true;
    try {
    if (removesLastUsableMasterDevice(_devices, device)) {
      await showDialog<void>(context: context, builder: (dialogContext) => AlertDialog(
        title: const Text('最後の信頼済み端末は停止できません'),
        content: const Text('この端末を停止するとマスター管理に入れなくなります。別の信頼済み端末を準備してください。復旧用メール2件の設定も確認してください。'),
        actions: [TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('閉じる'))],
      ));
      return false;
    }
    return await showDialog<bool>(context: context, builder: (dialogContext) => AlertDialog(
      title: Text('端末を$operationしますか？'),
      content: Text('「${device.deviceName}」はマスター管理に使えなくなります。通常の画面ロックとは異なります。別の信頼済み端末からの操作または登録済み復旧メール2件での復旧が必要です。'),
      actions: [TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('戻る')),
        FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: Text(operation))],
    )) == true;
    } finally { _confirmingLoss = false; }
  }

  Future<void> _setLocked(MasterDeviceRecord device, bool locked) async {
    final repository = _repository, session = _session;
    if (repository == null || session == null || !_current || device.isRevoked || _busyDeviceId != null) return;
    setState(() => _busyDeviceId = device.id);
    try {
      await session.check();
      if (locked && !await _confirmLoss(device, 'ロック')) return;
      await session.check();
      if (!mounted || !_current) return;
      final required = await repository.lockReauthenticationRequired(session: session);
      await session.check();
      if (!mounted || !_current) return;
      String? proof;
      if (required) {
        final verifier = widget.reauthentication ?? OperationReauthenticationRepository.maybeCreate();
        if (verifier == null) throw StateError('本人確認を利用できません。');
        proof = await showDialog<String>(context: context, barrierDismissible: false,
          builder: (_) => MasterDeviceLockProofDialog(expectedActor: session.actor,
            currentActor: () => repository.currentUserId, sessionCurrent: () => _current,
            deviceName: device.deviceName, locked: locked,
            requestProof: (password) async {
              await session.check();
              if (!mounted || !_current) throw StateError('ログイン状態が変わりました。');
              final proof = await verifier.requestProof(password: password,
                operation: 'master.device.lock', target: {'device_id': device.id, 'locked': locked});
              await session.check();
              return proof;
            }));
        if (proof == null) return;
      }
      await session.check();
      if (!mounted || !_current) return;
      await repository.setLocked(deviceId: device.id, locked: locked, proof: proof, session: session);
      await session.check();
      if (!mounted || !_current) return;
      await _load();
      if (!mounted || !_current) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(locked ? '端末をロックしました' : '端末のロックを解除しました')),
      );
    } catch (error) {
      if (!mounted || !_current) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('変更できませんでした: $error')),
      );
    } finally {
      if (_current) setState(() => _busyDeviceId = null);
    }
  }

  Future<void> _revoke(MasterDeviceRecord device) async {
    final repository = _repository, session = _session;
    if (repository == null || session == null || !_current || device.isRevoked || _busyDeviceId != null) return;
    setState(() => _busyDeviceId = device.id);
    try {
      await session.check();
      if (!await _confirmLoss(device, '登録解除')) return;
      await session.check();
      if (!mounted || !_current) return;
      await repository.revoke(device.id, session: session);
      await session.check();
      if (!mounted || !_current) return;
      await _load();
      if (!mounted || !_current) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('端末登録を解除しました')),
      );
    } catch (error) {
      if (!mounted || !_current) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('登録解除できませんでした: $error')),
      );
    } finally {
      if (_current) setState(() => _busyDeviceId = null);
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
            onPressed: _loading || _busyDeviceId != null ? null : _load,
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
                            final busy = _busyDeviceId != null;
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
            const Text('この端末かどうかは現在の情報だけでは判定できません。端末名を確認してください。'),
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


