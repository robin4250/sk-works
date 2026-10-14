import 'dart:convert';
import 'dart:typed_data';

import 'package:share_plus/share_plus.dart';
import 'package:flutter/material.dart';

import '../../international/language_controller.dart';
import '../settings/master_protected_page.dart';
import 'security_actor_boundary.dart';
import 'security_export_guard.dart';
import 'master_self_audit_repository.dart';
import 'master_self_operation_audit.dart';

/// Open only inside MasterProtectedPage and SecurityActorBoundary.
class MasterSelfAuditPage extends StatefulWidget {
  const MasterSelfAuditPage({super.key, this.loadRecords});
  final Future<MasterSelfAuditSnapshot> Function()? loadRecords;
  @override
  State<MasterSelfAuditPage> createState() => _MasterSelfAuditPageState();
}

/// This route owns its payload even when Face ID locks the source page.
class _MasterSelfAuditExportAction extends StatefulWidget {
  const _MasterSelfAuditExportAction({
    required this.snapshot,
    required this.actor,
  });
  final MasterSelfAuditSnapshot snapshot;
  final String? actor;
  @override
  State<_MasterSelfAuditExportAction> createState() =>
      _MasterSelfAuditExportActionState();
}

class _MasterSelfAuditExportActionState
    extends State<_MasterSelfAuditExportAction> {
  bool _failed = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  Future<void> _run() async {
    try {
      final repository = MasterSelfAuditRepository.maybeCreate();
      if (repository == null) {
        throw StateError('Unavailable');
      }
      await authorizeSecurityExport(
        actor: widget.actor,
        currentActor: () => repository.currentActor,
        isActive: () => mounted,
        // The action is mounted only after its new MasterProtectedPage unlocks.
        reauthenticate: () async => true,
        authorizeSnapshot: () =>
            repository.authorizeExport(widget.snapshot, widget.actor),
      );
      if (!mounted) {
        return;
      }
      final name =
          'SKO-self-audit-${widget.snapshot.cutoff.millisecondsSinceEpoch}.json';
      final box = context.findRenderObject() as RenderBox?;
      await SharePlus.instance.share(
        ShareParams(
          files: [
            XFile.fromData(
              Uint8List.fromList(utf8.encode(widget.snapshot.json)),
              mimeType: 'application/json',
              name: name,
            ),
          ],
          fileNameOverrides: [name],
          sharePositionOrigin: box == null
              ? null
              : box.localToGlobal(Offset.zero) & box.size,
        ),
      );
      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (_) {
      if (mounted) {
        setState(() => _failed = true);
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        SkoLanguageController.isEnglish ? 'Export audit' : '実監査ログの出力',
      ),
    ),
    body: Center(
      child: _failed
          ? Text(
              SkoLanguageController.isEnglish
                  ? 'Export unavailable. Refresh records and retry.'
                  : '出力できません。記録を更新して開き直してください。',
            )
          : const CircularProgressIndicator(),
    ),
  );
}

class _MasterSelfAuditPageState extends State<MasterSelfAuditPage> {
  MasterSelfAuditSnapshot? _snapshot;
  bool _loading = true, _failed = false;
  int _generation = 0;
  String? _recordActor;
  bool _exporting = false;
  bool get _english => SkoLanguageController.isEnglish;
  String _text(String ja, String en) => _english ? en : ja;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final generation = ++_generation;
    setState(() {
      _snapshot = null;
      _loading = true;
      _failed = false;
    });
    try {
      final repository = MasterSelfAuditRepository.maybeCreate();
      final actor = repository?.currentActor;
      final loader = widget.loadRecords ?? repository?.load;
      if (loader == null) {
        throw StateError('Unavailable');
      }
      final snapshot = await loader();
      if (!mounted || generation != _generation) {
        return;
      }
      setState(() {
        _snapshot = snapshot;
        _recordActor = actor;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || generation != _generation) {
        return;
      }
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  Future<void> _beginExport() async {
    final snapshot = _snapshot;
    if (_exporting || snapshot == null || _recordActor == null) {
      return;
    }
    final actor = _recordActor;
    setState(() => _exporting = true);
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => MasterProtectedPage(
          title: _text('実監査ログの保存・共有', 'Save or share audit'),
          child: SecurityActorBoundary(
            initialActor: actor,
            child: _MasterSelfAuditExportAction(
              snapshot: snapshot,
              actor: actor,
            ),
          ),
        ),
      ),
    );
    if (mounted) {
      setState(() => _exporting = false);
    }
  }

  void _help() => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(_text('本人の実監査ログ', 'Your audit logs')),
      content: SingleChildScrollView(
        child: Text(
          _text(
            'サーバーに保存された本人の記録だけを表示します。マスター操作と認証は別の記録元です。各最新100件を表示します。操作ログには本文・連絡先・IP・端末名・IDを含めません。認証ログはSupabaseのデータベース保存分のみです。0件でも安全・保存設定OFFとは判断できません。DB保存が無効な場合はSupabaseのAuthentication → Audit Logs → Write audit logs to the databaseを確認してください。本人と結びつかない接続、認証失敗、全アクセスを網羅する監視ではありません。現在の記録だけで不正アクセスと断定しません。',
            'Only your server-saved records are shown, with separate sources for master operations and authentication, up to the latest 100 each. Message bodies, contacts, IP addresses, device names and IDs are excluded. Auth records come only from Supabase database audit storage. An empty list proves neither safety nor disabled storage. Check Authentication → Audit Logs → Write audit logs to the database in Supabase if needed. Unattributed connections, failed sign-ins and all requests are not fully covered. These records alone do not confirm an attack.',
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(_text('閉じる', 'Close')),
        ),
      ],
    ),
  );

  Widget _section(
    String title,
    String source,
    List<MasterSelfOperationAuditEvent> events,
  ) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          Text(source),
          const Divider(),
          if (events.isEmpty)
            Text(
              _text(
                '表示できる保存記録はありません。安全・未発生を意味しません。',
                'No saved records available. This does not prove safety or absence of events.',
              ),
            ),
          for (final event in events)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(event.label(_english)),
              subtitle: Text('${event.at.toLocal()}'),
            ),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(_text('本人の実監査ログ', 'Your audit logs')),
      actions: [
        IconButton(
          onPressed: _help,
          icon: const Icon(Icons.help_outline),
          tooltip: _text('ヘルプ', 'Help'),
        ),
        IconButton(
          onPressed: _loading ? null : _load,
          icon: const Icon(Icons.refresh),
          tooltip: _text('更新', 'Refresh'),
        ),
      ],
    ),
    body: SafeArea(
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : _failed
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _text(
                      '記録を取得できません。権限・接続を確認してください。',
                      'Audit unavailable. Check connection and access.',
                    ),
                  ),
                  TextButton(
                    onPressed: _load,
                    child: Text(_text('再読み込み', 'Retry')),
                  ),
                ],
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  _text(
                    '本人にひも付いた実記録です。不正アクセスの検知結果とは異なります。',
                    'Actual records linked to your account; these are not intrusion detections.',
                  ),
                ),
                _section(
                  _text('マスター操作', 'Master operations'),
                  _text('記録元：アプリのサーバー操作監査', 'Source: server operation audit'),
                  _snapshot!.operations,
                ),
                _section(
                  _text('本人の認証', 'Your authentication'),
                  _text(
                    '記録元：Supabase AuthのDB保存分',
                    'Source: Supabase Auth database audit',
                  ),
                  _snapshot!.authentication,
                ),
                Text(
                  _text('取得基準：', 'Cutoff: ') +
                      _snapshot!.cutoff.toLocal().toString(),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _exporting ? null : _beginExport,
                  icon: const Icon(Icons.save_alt),
                  label: Text(_text('JSONを保存・共有', 'Save or share JSON')),
                ),
                Text(
                  _text(
                    '保存・共有前に再度本人確認します。OSへ渡した後は取り消せません。',
                    'Fresh verification is required. OS handoff cannot be revoked.',
                  ),
                ),
              ],
            ),
    ),
  );
}
