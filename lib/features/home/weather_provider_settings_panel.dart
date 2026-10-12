import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../international/language_controller.dart';

/// Isolated from existing master feature flags. Authorization is enforced by RPC.
class WeatherProviderSettingsRepository {
  const WeatherProviderSettingsRepository(this.client);
  final SupabaseClient client;
  Future<String> load() async => _provider(await client.rpc('current_weather_provider'));
  Future<String> save(String provider) async {
    _provider(provider);
    return _provider(await client.rpc('set_weather_provider', params: {'p_provider': provider}));
  }
  String _provider(dynamic value) {
    if (value != 'openweather' && value != 'weatherkit') {
      throw const FormatException('Weather provider unavailable');
    }
    return value as String;
  }
}

class WeatherProviderSettingsPanel extends StatefulWidget {
  const WeatherProviderSettingsPanel({super.key, required this.isMaster,
    required this.repository, this.onChanged});
  final bool isMaster;
  final WeatherProviderSettingsRepository repository;
  final VoidCallback? onChanged;
  @override
  State<WeatherProviderSettingsPanel> createState() => _WeatherProviderSettingsPanelState();
}
class _WeatherProviderSettingsPanelState extends State<WeatherProviderSettingsPanel> {
  String? provider;
  bool loading = true, saving = false, failed = false;
  int generation = 0;
  @override
  void initState() { super.initState(); _load(); }
  @override
  void didUpdateWidget(WeatherProviderSettingsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.repository != widget.repository || oldWidget.isMaster != widget.isMaster) {
      provider = null; _load();
    }
  }
  Future<void> _load() async {
    final request = ++generation;
    setState(() { loading = true; failed = false; saving = false; });
    try {
      final result = await widget.repository.load();
      if (mounted && request == generation) { setState(() { provider = result; loading = false; }); }
    } catch (_) {
      if (mounted && request == generation) { setState(() { failed = true; loading = false; }); }
    }
  }
  Future<void> _save(String next) async {
    if (!widget.isMaster || saving || loading) { return; }
    final request = ++generation;
    setState(() { saving = true; failed = false; });
    try {
      final result = await widget.repository.save(next);
      if (mounted && request == generation) { setState(() { provider = result; saving = false; }); widget.onChanged?.call(); }
    } catch (_) {
      if (mounted && request == generation) { setState(() { failed = true; saving = false; }); }
    }
  }
  @override
  Widget build(BuildContext context) {
    String tr(String value) => SkoLanguageController.tr(value);
    return Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(tr('天気予報の提供元'), style: Theme.of(context).textTheme.titleMedium),
        Text(tr('切り替えはマスター管理者のみ。接続・認証設定が必要です。')),
        if (loading || saving) const LinearProgressIndicator(),
        if (failed) Row(children: [Expanded(child: Text(tr('天気設定を取得・保存できませんでした。'))),
          TextButton(onPressed: loading || saving ? null : _load, child: Text(tr('再取得')))]),
        for (final entry in const {'openweather': 'OpenWeather', 'weatherkit': 'Apple Weather (WeatherKit)'}.entries)
          ListTile(title: Text(entry.value),
            leading: Icon(provider == entry.key ? Icons.radio_button_checked : Icons.radio_button_unchecked),
            enabled: widget.isMaster && !loading && !saving && provider != null,
            onTap: widget.isMaster && !loading && !saving && provider != null
                ? () { if (entry.key != provider) { _save(entry.key); } } : null),
      ],
    )));
  }
}
