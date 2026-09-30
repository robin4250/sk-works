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
    final repository = _repository;
    if (repository == null) {
      setState(() {
        _loading = false;
        _error = 'マスター機能設定を利用できません。';
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final value = await repository.load();
      if (!mounted) return;
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
    if (repository == null) return;
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
    if (confirmed != true) return;

    setState(() => _busyKey = featureKey);
    try {
      final updated = await repository.setEnabled(
        featureKey: featureKey,
        enabled: next,
      );
      if (!mounted) return;
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
            onPressed: _loading ? null : _load,
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
                                '機能を一時停止してもデータは削除しません。'
                                '再びONにすると、保存済みの履歴をそのまま利用できます。',
                                style: TextStyle(fontWeight: FontWeight.w700),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          _featureTile(
                            featureKey: 'vehicle_management',
                            label: '車両管理',
                            description: '車両の閲覧・登録・変更・休止',
                            enabled: availability.vehicleManagement,
                          ),
                          const SizedBox(height: 10),
                          _featureTile(
                            featureKey: 'route_assignment',
                            label: 'ルート・配車',
                            description: '運行日・車両・現場・運転者のルート共有',
                            enabled: availability.routeAssignment,
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
        onChanged: busy
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
