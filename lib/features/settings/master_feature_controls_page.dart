import 'package:flutter/material.dart';

import '../notifications/notification_bell.dart';
import 'master_feature_controls_repository.dart';

class MasterFeatureControlsPage extends StatefulWidget {
  const MasterFeatureControlsPage({super.key});

  @override
  State<MasterFeatureControlsPage> createState() =>
      _MasterFeatureControlsPageState();
}

class _MasterFeatureControlsPageState extends State<MasterFeatureControlsPage> {
  final _repository = MasterFeatureControlsRepository.maybeCreate();

  MasterFeatureAvailability? _availability;
  bool _loading = true;
  String? _busyKey;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (_busyKey != null) return;
    final repository = _repository;
    if (repository == null) {
      setState(() {
        _loading = false;
        _error = 'マスター機能設定を利用できません。';
      });
      return;
    }

    final actor = repository.actorId;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final value = await repository.load();
      if (!mounted || actor == null || repository.actorId != actor) return;
      setState(() {
        _availability = value;
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

  Future<void> _toggle({
    required String featureKey,
    required String label,
    required bool current,
  }) async {
    final repository = _repository;
    if (repository == null || _busyKey != null || _loading) return;
    final actor = repository.actorId;
    if (actor == null) return;
    final next = !current;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(next ? '$labelを有効にする' : '$labelを一時停止する'),
        content: Text(
          next
              ? '$labelを再び利用できる状態にします。既存データや履歴はそのまま残ります。'
              : '$labelを新しく利用できない状態にします。既存データや履歴は削除しません。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('戻る'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(next ? '有効にする' : '一時停止する'),
          ),
        ],
      ),
    );
    if (confirmed != true || repository.actorId != actor) return;

    setState(() => _busyKey = featureKey);
    try {
      final updated = await repository.setEnabled(
        featureKey: featureKey,
        enabled: next,
      );
      if (!mounted || repository.actorId != actor) return;
      setState(() => _availability = updated);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('変更できませんでした: $error')),
      );
    } finally {
      if (mounted) setState(() => _busyKey = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final availability = _availability;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Master 機能設定'),
        actions: [
          const SkoNotificationBell(),
          IconButton(
            tooltip: '再読み込み',
            onPressed: _loading || _busyKey != null ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(child: Text(_error!, textAlign: TextAlign.center))
                : availability == null
                    ? const Center(child: Text('設定を読み込めませんでした'))
                    : ListView(
                        padding: const EdgeInsets.all(16),
                        children: [
                          const Card(
                            child: Padding(
                              padding: EdgeInsets.all(16),
                              child: Text(
                                '機能を一時停止してもデータは削除しません。出勤中の到着・移動・退勤は続行できます。'
                                '再びONにすると、保存済みの履歴をそのまま利用できます。',
                                style: TextStyle(fontWeight: FontWeight.w700),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          _featureTile(
                            featureKey: 'vehicle_management',
                            label: '車両管理',
                            description: '新しい車両の登録・変更・選択を停止。車両を使わない出勤は継続',
                            enabled: availability.vehicleManagement,
                          ),
                          const SizedBox(height: 10),
                          _featureTile(
                            featureKey: 'route_assignment',
                            label: 'ルート・配車',
                            description: '新しいルートの登録・選択・出勤を停止。出勤中のルートは継続',
                            enabled: availability.routeAssignment,
                          ),
                          const SizedBox(height: 10),
                          _featureTile(
                            featureKey: 'traffic_nearest_station',
                            label: '交通案内：最寄駅',
                            description: 'Googleマップの最寄駅検索への入口',
                            enabled: availability.trafficNearestStation,
                          ),
                          const SizedBox(height: 10),
                          _featureTile(
                            featureKey: 'traffic_train_transfer',
                            label: '交通案内：電車乗換',
                            description: 'Yahoo!乗換案内への入口',
                            enabled: availability.trafficTrainTransfer,
                          ),
                          const SizedBox(height: 10),
                          _featureTile(
                            featureKey: 'traffic_bus_stop',
                            label: '交通案内：バス停',
                            description: 'Googleマップの近くのバス停検索への入口',
                            enabled: availability.trafficBusStop,
                          ),
                        ],
                      ),
      ),
    );
  }

  Widget _featureTile({
    required String featureKey,
    required String label,
    required String description,
    required bool enabled,
  }) {
    final busy = _busyKey == featureKey;
    return Card(
      child: SwitchListTile(
        value: enabled,
        onChanged: _busyKey != null || _loading
            ? null
            : (_) => _toggle(
                  featureKey: featureKey,
                  label: label,
                  current: enabled,
                ),
        title: Text(
          label,
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        subtitle: Text(
          '$description\n現在: ${enabled ? '利用可能' : '一時停止中'}',
        ),
        secondary: busy
            ? const SizedBox.square(
                dimension: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Icon(enabled ? Icons.toggle_on_outlined : Icons.toggle_off_outlined),
      ),
    );
  }
}
