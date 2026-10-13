import 'package:flutter/material.dart';
import '../../international/language_controller.dart';

import '../../data/supabase_backend.dart';
import 'chat_cloud_repository.dart';
import 'line_import_page.dart';
import 'line_master_workspace_page.dart';
import 'line_import_repository.dart';
import 'line_talk_page.dart';
import 'line_joined_groups_page.dart';

class LineTalkHubPage extends StatefulWidget {
  const LineTalkHubPage({super.key});
  @override
  State<LineTalkHubPage> createState() => _LineTalkHubPageState();
}

class _LineTalkHubPageState extends State<LineTalkHubPage> {
  final _repository = LineImportRepository.maybeCreate();
  LineImportFeatures _features = const LineImportFeatures();
  bool _canViewInvoice = false;
  bool _isMaster = false;
  String? _error;
  @override
  void initState() { super.initState(); _load(); }
  Future<void> _load() async {
    final repository = _repository;
    final chat = ChatCloudRepository.maybeCreate();
    if (repository == null || chat == null) return;
    try {
      final actor = repository.actor;
      final master = await SupabaseBackend.client.rpc('is_current_user_master_admin');
      final features = await repository.features();
      final member = await chat.membership();
      final permissions = await SupabaseBackend.client.rpc('current_feature_permissions');
      if (!mounted || repository.actor != actor) return;
      setState(() {
        _features = features;
        _isMaster = master == true;
        _canViewInvoice = ['owner','admin','manager'].contains(member.role) && permissions is Map && permissions['can_view_invoices'] == true;
        _error = null;
      });
    } catch (_) {
      if (mounted) setState(() => _error = '追加機能の設定を読み込めませんでした。トークは利用できます。');
    }
  }
  Future<void> _open(Widget page) async {
    await Navigator.of(context).push<void>(MaterialPageRoute(builder: (_) => page));
    if (mounted) await _load();
  }
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('LINEトーク'), actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh), tooltip: '再読み込み')]),
    body: ListView(padding: const EdgeInsets.all(16), children: [
      OutlinedButton.icon(onPressed: () => _open(const LineJoinedGroupsPage()), icon: const Icon(Icons.groups_outlined), label: Text(SkoLanguageController.tr('参加済みグループ一覧'))),
      const SizedBox(height: 12),
      FilledButton.icon(onPressed: () => _open(const LineTalkPage()), icon: const Icon(Icons.chat_bubble_outline), label: const Text('トーク')),
      if (_features.attendance) ...[const SizedBox(height: 12), OutlinedButton.icon(onPressed: () => _open(const LineImportPage(target: 'attendance')), icon: const Icon(Icons.calendar_month), label: const Text('出勤表'))],
      if (_features.invoice && _canViewInvoice) ...[const SizedBox(height: 12), OutlinedButton.icon(onPressed: () => _open(const LineImportPage(target: 'invoice')), icon: const Icon(Icons.receipt_long_outlined), label: const Text('請求書'))],
      if (_isMaster) ...[const SizedBox(height: 12), OutlinedButton.icon(onPressed: () => _open(const LineMasterWorkspacePage()), icon: const Icon(Icons.admin_panel_settings_outlined), label: Text(SkoLanguageController.tr('マスター権限')))],
      const SizedBox(height: 16), const Text('トークは標準機能です。出勤表・請求書の追加機能はマスター設定に応じて表示します。'),
      if (_error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_error!)),
    ]),
  );
}


