import 'package:flutter/material.dart';

import '../../data/supabase_backend.dart';
import 'chat_cloud_repository.dart';
import 'line_historical_monthly_import_page.dart';
import 'line_release_access.dart';

/// Explicitly choose the destination before reading any historical file.
class LineSourceUploadPage extends StatelessWidget {
  const LineSourceUploadPage({super.key});

  @override
  Widget build(BuildContext context) => LineReleaseBoundary(
    builder: (_) => const _UploadDestination());
}

class _UploadDestination extends StatefulWidget {
  const _UploadDestination();

  @override
  State<_UploadDestination> createState() => _UploadDestinationState();
}

class _UploadDestinationState extends State<_UploadDestination> {
  List<Map<String, dynamic>> _groups = [];
  String? _selected, _error;
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    try {
      if (!SupabaseBackend.isInitialized) throw StateError('Login required');
      final client = SupabaseBackend.client;
      final actor = client.auth.currentUser?.id;
      if (actor == null || await client.rpc('is_current_user_master_admin') != true) {
        throw StateError('Master required');
      }
      final groups = await ChatCloudRepository.maybeCreate()!.loadGroups();
      if (!mounted || client.auth.currentUser?.id != actor) return;
      setState(() => _groups = groups.where((g) => g['group_type'] != 'direct').toList());
    } catch (_) {
      if (mounted) setState(() => _error = 'マスター権限と接続を確認してください。');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('元データ取込')),
    body: ListView(padding: const EdgeInsets.all(16), children: [
      const Text('取り込む履歴の保存先グループを選んでください。ファイルのグループ名と保存先を確認してからアップロードします。'),
      const SizedBox(height: 16),
      if (_loading) const LinearProgressIndicator(),
      if (_error != null) Text(_error!),
      DropdownButtonFormField<String>(
        initialValue: _selected,
        isExpanded: true,
        decoration: const InputDecoration(labelText: '保存先グループ'),
        items: [for (final g in _groups) DropdownMenuItem(
          value: g['id'].toString(),
          child: Text(g['display_name']?.toString() ?? g['name'].toString()))],
        onChanged: _loading ? null : (value) => setState(() => _selected = value)),
      const SizedBox(height: 16),
      FilledButton.icon(
        onPressed: _loading || _selected == null ? null : () => Navigator.of(context).push<void>(
          MaterialPageRoute(builder: (_) => LineHistoricalMonthlyImportPage(groupId: _selected!))),
        icon: const Icon(Icons.upload_file),
        label: const Text('このグループへ元データを取り込む')),
    ]));
}
