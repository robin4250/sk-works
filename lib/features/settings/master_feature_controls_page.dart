import 'package:flutter/material.dart';

import '../notifications/notification_bell.dart';
import '../referrals/app_referral_master_entry.dart';
import '../referrals/app_referral_repository.dart';
import '../chat/line_import_feature_settings_panel.dart';
import '../../international/language_controller.dart';
import '../../data/supabase_backend.dart';
import '../home/weather_provider_settings_panel.dart';
import 'master_feature_controls_repository.dart';
import '../auth/operation_reauthentication_repository.dart';
import 'master_feature_proof_dialog.dart';

class MasterFeatureControlsPage extends StatefulWidget {
  const MasterFeatureControlsPage({super.key, this.repository, this.reauthentication});

  @visibleForTesting final MasterFeatureControlsRepository? repository;
  @visibleForTesting final OperationReauthenticationRepository? reauthentication;

  @override
  State<MasterFeatureControlsPage> createState() =>
      _MasterFeatureControlsPageState();
}

class _MasterFeatureControlsPageState extends State<MasterFeatureControlsPage>
    with WidgetsBindingObserver {
  late final _repository = widget.repository ?? MasterFeatureControlsRepository.maybeCreate();
  AppLifecycleState _lifecycle = AppLifecycleState.resumed;
  int _generation = 0;
  Route<dynamic>? _operationDialog;
  final _weatherProviderRepository = SupabaseBackend.isInitialized
      ? WeatherProviderSettingsRepository(SupabaseBackend.client) : null;

  final _referralRepository = SupabaseBackend.isInitialized
      ? AppReferralRepository(SupabaseBackend.client) : null;

  MasterFeatureAvailability? _availability;
  bool _loading = true;
  String? _busyKey;
  String? _error;

  @override
  void initState() {
    super.initState();
    _lifecycle = WidgetsBinding.instance.lifecycleState ?? AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final wasResumed = _lifecycle == AppLifecycleState.resumed;
    _lifecycle = state;
    if (state != AppLifecycleState.resumed) {
      _generation++;
      final dialog = _operationDialog;
      if (dialog != null && dialog.isActive) {
        dialog.navigator?.removeRoute(dialog);
      }
      setState(() { _busyKey = null; _loading = false; });
    } else if (!wasResumed) {
      _load();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _generation++;
    super.dispose();
  }

  Future<T?> _showOperationDialog<T>({
    required WidgetBuilder builder,
    bool barrierDismissible = true,
  }) async {
    final route = DialogRoute<T>(context: context, builder: builder,
      barrierDismissible: barrierDismissible);
    _operationDialog = route;
    try {
      return await Navigator.of(context, rootNavigator: true).push<T>(route);
    } finally {
      if (identical(_operationDialog, route)) _operationDialog = null;
    }
  }

  Future<void> _load() async {
    if (_busyKey != null || _lifecycle != AppLifecycleState.resumed) return;
    final repository = _repository;
    if (repository == null) {
      setState(() {
        _loading = false;
        _error = 'マスター機能設定を利用できません。';
      });
      return;
    }

    final actor = repository.actorId;
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final value = await repository.load();
      if (!mounted || actor == null || repository.actorId != actor ||
          generation != _generation || _lifecycle != AppLifecycleState.resumed) {
        return;
      }
      setState(() {
        _availability = value;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || generation != _generation || repository.actorId != actor ||
          _lifecycle != AppLifecycleState.resumed) {
        return;
      }
      setState(() {
        _loading = false;
        _error = 'マスター機能設定を読み込めません。権限・接続を確認して再読み込みしてください。';
      });
    }
  }

  Future<void> _toggle({
    required String featureKey,
    required String label,
    required bool current,
  }) async {
    final repository = _repository;
    if (repository == null || _busyKey != null || _loading ||
        _lifecycle != AppLifecycleState.resumed ||
        !MasterFeatureControlsRepository.supportedFeatures.contains(featureKey)) {
      return;
    }
    final actor = repository.actorId;
    if (actor == null) return;
    final next = !current;
    final generation = ++_generation;
    bool currentOperation() => mounted && generation == _generation &&
        repository.actorId == actor && _lifecycle == AppLifecycleState.resumed;
    setState(() => _busyKey = featureKey);
    try {
      final confirmed = await _showOperationDialog<bool>(
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
      if (confirmed != true || !currentOperation()) return;
      final required = await repository.reauthenticationRequired();
      if (!currentOperation()) return;
      if (featureKey == 'site_order_documents' && !required) {
        throw StateError('注文・請書の本人確認機能を確認できません。');
      }
      String? proof;
      if (required) {
        final verifier = widget.reauthentication ?? OperationReauthenticationRepository.maybeCreate();
        if (verifier == null) throw StateError('本人確認を利用できません。');
        proof = await _showOperationDialog<String>(barrierDismissible: false,
          builder: (_) => MasterFeatureProofDialog(expectedActor: actor,
            currentActor: () => repository.actorId, label: label, enabled: next,
            requestProof: (password) => verifier.requestProof(password: password,
              operation: 'master.feature.set', target: {'feature_key': featureKey, 'enabled': next})));
        if (proof == null) return;
      }
      if (!currentOperation()) return;
      final updated = await repository.setEnabled(
        featureKey: featureKey,
        enabled: next,
        proof: proof,
        expectedActor: actor,
      );
      if (!currentOperation()) return;
      setState(() => _availability = updated);
    } catch (_) {
      if (!mounted || !currentOperation()) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('変更できませんでした。本人確認・権限・接続を確認してください。')),
      );
    } finally {
      if (currentOperation()) setState(() => _busyKey = null);
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
            onPressed: _loading || _busyKey != null || _lifecycle != AppLifecycleState.resumed ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: _loading && availability == null
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(child: Text(_error!, textAlign: TextAlign.center))
                : availability == null
                    ? const Center(child: Text('設定を読み込めませんでした'))
                    : ListView(
                        padding: const EdgeInsets.all(16),
                        children: [
                          if (_referralRepository != null)
                            AppReferralMasterEntry(repository: _referralRepository),
                          const LineImportFeatureSettingsPanel(),
                          if (_weatherProviderRepository != null)
                            WeatherProviderSettingsPanel(
                              isMaster: true,
                              repository: _weatherProviderRepository,
                            ),
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
                          Card(child: SwitchListTile(
                            key: const Key('master-trade-documents-toggle'),
                            value: availability.tradeDocuments,
                            onChanged: !availability.tradeDocumentsSupported || _busyKey != null ||
                                _loading || _lifecycle != AppLifecycleState.resumed ? null
                              : (_) => _toggle(featureKey: 'site_order_documents',
                                  label: '注文・請書', current: availability.tradeDocuments),
                            title: const Text('注文・請書', style: TextStyle(fontWeight: FontWeight.w900)),
                            subtitle: Text(availability.tradeDocumentsSupported
                              ? '単独作成を制御。現場送信は対応確認後に利用可能。保存済み書類は保持\n現在: ${availability.tradeDocuments ? 'ON' : 'OFF'}'
                              : '初期OFF。サーバー側の接続が完了するまで変更できません。'),
                          )),
                          const SizedBox(height: 10),
                          if (availability.companySealImageToolsSupported) ...[
                            _featureTile(
                              featureKey: 'company_seal_image_tools',
                              label: '角印画像ツール',
                              description: '角印画像の新規作成・加工・登録を制御。保存済みの角印・帳票は保持',
                              enabled: availability.companySealImageTools,
                            ),
                            const SizedBox(height: 10),
                          ],
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
        onChanged: _busyKey != null || _loading || _lifecycle != AppLifecycleState.resumed
            ? null
            : (_) => _toggle(
                  featureKey: featureKey,
                  label: label,
                  current: enabled,
                ),
        title: Text(
          SkoLanguageController.tr(label),
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        subtitle: Text(
          '${SkoLanguageController.tr(description)}\n現在: ${enabled ? '利用可能' : '一時停止中'}',
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

