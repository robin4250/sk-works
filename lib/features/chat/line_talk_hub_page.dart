import 'line_release_access.dart';
import 'dart:async';
import '../settings/master_owner_access.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../international/language_controller.dart';

import 'line_import_page.dart';
import 'line_master_workspace_page.dart';
import 'line_import_repository.dart';
import 'line_talk_page.dart';
import 'line_shared_groups_page.dart';
import 'chat_cloud_page.dart';
import 'line_joined_groups_page.dart';

class LineTalkHubAccess {
  const LineTalkHubAccess({this.isMaster = false, this.canViewInvoice = false,
    this.features = const LineImportFeatures(), this.settingsUnavailable = false});
  final bool isMaster, canViewInvoice, settingsUnavailable;
  final LineImportFeatures features;
}

class LineTalkHubPage extends StatelessWidget {
  const LineTalkHubPage({super.key, this.accessLoader, this.client});
  final SupabaseClient? client;
  @visibleForTesting
  final Future<LineTalkHubAccess> Function()? accessLoader;
  @override
  Widget build(BuildContext context) => LineReleaseBoundary(builder: (_) => _LineTalkHubPageContent(accessLoader: accessLoader, client: client));
}

class _LineTalkHubPageContent extends StatefulWidget {
  const _LineTalkHubPageContent({this.accessLoader, this.client});
  final SupabaseClient? client;
  @visibleForTesting
  final Future<LineTalkHubAccess> Function()? accessLoader;
  @override
  State<_LineTalkHubPageContent> createState() => _LineTalkHubPageState();
}

class _LineTalkHubPageState extends State<_LineTalkHubPageContent> {
  late final SupabaseClient? _client = widget.client ?? MasterOwnerAccess.defaultClient;
  late final _repository = _client == null ? null : LineImportRepository(_client);
  LineImportFeatures _features = const LineImportFeatures();
  bool _isMaster = false;
  StreamSubscription<dynamic>? _masterChanges;
  String? _error;
  @override
  void initState() {
    super.initState();
    if (_client != null) { _masterChanges = _client.auth.onAuthStateChange.listen((_) {
      if (!mounted) { return; }
      setState(() => _isMaster = false);
      _load();
    }, onError: (Object _) { _loadGeneration++; if (mounted) { setState(() => _isMaster = false); } }); }
    _load();
  }
  @override
  void dispose() { _masterChanges?.cancel(); super.dispose(); }
  int _loadGeneration = 0;
  Future<LineTalkHubAccess> _readAccess() async {
    final repository = _repository;
    if (repository == null) return const LineTalkHubAccess();
    final actor = repository.actor;
    final captured = _client?.auth.currentSession;
    var master = false, unavailable = false;
    var features = const LineImportFeatures();
    try {
      master = await MasterOwnerAccess.check(_client!);
    } catch (_) { unavailable = true; }
    try { features = await repository.features(); }
    catch (_) { unavailable = true; }
    if (repository.actor != actor || !identical(captured, _client?.auth.currentSession)) { throw StateError('Session changed'); }
    return LineTalkHubAccess(isMaster: master,
      features: features, settingsUnavailable: unavailable);
  }
  Future<void> _load() async {
    final generation = ++_loadGeneration;
    setState(() { _isMaster = false; });
    try {
      final access = await (widget.accessLoader?.call() ?? _readAccess());
      final master = access.isMaster && (widget.accessLoader == null ||
          (_client != null && await MasterOwnerAccess.check(_client)));
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _features = access.features; _isMaster = master;
        _error = access.settingsUnavailable
          ? '追加機能の設定を読み込めませんでした。トークと確認できた権限の機能は利用できます。'
          : null;
      });
    } catch (_) {
      if (mounted && generation == _loadGeneration) {
        setState(() {
          _features = const LineImportFeatures(); _isMaster = false;
          _error = 'ログイン状態と追加機能の設定を確認してください。';
        });
      }
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
      FilledButton.icon(onPressed: () => _open(LineSharedGroupsPage(
        onOpenGroup: (id) => _open(ChatCloudPage(initialGroupId: id)),
        onOpenSavedTalks: () => _open(const LineTalkPage()),
      )), icon: const Icon(Icons.chat_bubble_outline), label: const Text('トーク')),
      if (_features.attendance) ...[const SizedBox(height: 12), OutlinedButton.icon(onPressed: () => _open(const LineImportPage(target: 'attendance')), icon: const Icon(Icons.calendar_month), label: const Text('出勤表'))],
      if (_isMaster && MasterOwnerAccess.currentFor(_client)) ...[const SizedBox(height: 12), OutlinedButton.icon(onPressed: () => _open(LineMasterWorkspacePage(client: _client)), icon: const Icon(Icons.admin_panel_settings_outlined), label: Text(SkoLanguageController.tr('マスター権限')))],
      const SizedBox(height: 16), const Text('トークは利用が許可されている場合に開けます。請求書・単価設定・チャット・月別の表は「マスター権限」から開きます。出勤表はマスター設定に応じて表示します。'),
      if (_error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_error!)),
    ]),
  );
}




