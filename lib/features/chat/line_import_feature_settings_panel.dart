import 'package:flutter/material.dart';
import 'line_import_repository.dart';

class LineImportFeatureSettingsPanel extends StatefulWidget {
  const LineImportFeatureSettingsPanel({super.key});
  @override
  State<LineImportFeatureSettingsPanel> createState() => _LineImportFeatureSettingsPanelState();
}
class _LineImportFeatureSettingsPanelState extends State<LineImportFeatureSettingsPanel> {
  final _repository = LineImportRepository.maybeCreate();
  LineImportFeatures? _features;
  bool _busy = false;
  String? _error;
  @override
  void initState() { super.initState(); _load(); }
  Future<void> _load() async {
    if (_repository == null) return;
    try {
      final features = await _repository.features();
      if (mounted) setState(() { _features = features; _error = null; });
    } catch (_) { if (mounted) setState(() => _error = 'LINE追加機能の設定を読み込めませんでした。'); }
  }
  Future<void> _set(String target, bool enabled) async {
    setState(() => _busy = true);
    try {
      final features = await _repository!.setEnabled(target, enabled);
      if (mounted) setState(() { _features = features; _error = null; });
    } catch (_) { if (mounted) setState(() => _error = '設定を変更できませんでした。マスター権限と接続を確認してください。'); }
    finally { if (mounted) setState(() => _busy = false); }
  }
  @override
  Widget build(BuildContext context) => Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text('LINE追加機能', style: Theme.of(context).textTheme.titleMedium),
    const Text('トーク・受信は常時利用できます。出勤表・請求書は初期OFFです。OFFでも保存データは残り、再ONで継続できます。'),
    SwitchListTile(title: const Text('LINE出勤表'), value: _features?.attendance ?? false, onChanged: _busy || _features == null ? null : (value) => _set('attendance', value)),
    SwitchListTile(title: const Text('LINE請求書'), value: _features?.invoice ?? false, onChanged: _busy || _features == null ? null : (value) => _set('invoice', value)),
    if (_busy) const LinearProgressIndicator(),
    if (_error != null) Text(_error!),
    TextButton(onPressed: _busy ? null : _load, child: const Text('再読み込み')),
  ])));
}
