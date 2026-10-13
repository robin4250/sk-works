import 'package:flutter/material.dart';

import '../../data/supabase_backend.dart';
import '../../international/language_controller.dart';
import 'line_historical_invoice_page.dart';
import 'line_talk_page.dart';

/// Three entries over existing LINE data; this screen grants no permissions.
class LineMasterWorkspacePage extends StatefulWidget {
  const LineMasterWorkspacePage({
    super.key,
    this.masterCheck,
    this.talkBuilder,
    this.invoiceBuilder,
    this.ratesBuilder,
  });

  @visibleForTesting
  final Future<bool> Function()? masterCheck;
  @visibleForTesting
  final WidgetBuilder? talkBuilder, invoiceBuilder, ratesBuilder;

  @override
  State<LineMasterWorkspacePage> createState() =>
      _LineMasterWorkspacePageState();
}

class _LineMasterWorkspacePageState extends State<LineMasterWorkspacePage> {
  bool _loading = true, _master = false;
  String? _error;

  String _tr(String text) => SkoLanguageController.tr(text);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<bool> _check() async {
    if (widget.masterCheck != null) return widget.masterCheck!();
    if (!SupabaseBackend.isInitialized) return false;
    final client = SupabaseBackend.client;
    final actor = client.auth.currentUser?.id;
    if (actor == null) return false;
    final master = await client.rpc('is_current_user_master_admin');
    return client.auth.currentUser?.id == actor && master == true;
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _master = false;
      _error = null;
    });
    try {
      final master = await _check();
      if (!mounted) return;
      setState(() {
        _master = master;
        _error = master ? null : 'マスター権限でログインしてください。';
      });
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'マスター権限と接続を確認してください。');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _open(WidgetBuilder builder) async {
    setState(() => _loading = true);
    try {
      if (!await _check()) {
        if (mounted) {
          setState(() {
            _master = false;
            _error = 'マスター権限でログインしてください。';
          });
        }
        return;
      }
      if (!mounted) return;
      await Navigator.of(context).push<void>(
        MaterialPageRoute(builder: builder),
      );
      if (mounted) await _load();
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'マスター権限と接続を確認してください。');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _help() => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(_tr('LINEマスター権限')),
      content: SingleChildScrollView(child: Text(_tr(
        'チャットは連携済みLINEグループの受信データを表示します。未連携のグループを作成済みとして表示しません。請求書は対象月の確認済み候補と保存履歴を確認します。単価設定は過去月の人工・残業・早出・手当の単価を入力し、履歴小計として保存します。実人数と延べ人工は別です。保存は通常請求書の発行と別で、正式下書きは取引先と税・福利費を確認して作成します。現在の現場単価や給与は変更しません。',
      ))),
      actions: [TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(_tr('閉じる')),
      )],
    ),
  );

  Widget _entry(String key, IconData icon, String title, String subtitle,
      WidgetBuilder builder) => Card(
    margin: const EdgeInsets.only(bottom: 12),
    child: ListTile(
      key: ValueKey(key),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      leading: Icon(icon),
      title: Text(_tr(title)),
      subtitle: Text(_tr(subtitle)),
      trailing: const Icon(Icons.chevron_right),
      onTap: _loading ? null : () => _open(builder),
    ),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(_tr('LINEマスター権限')),
      actions: [
        IconButton(onPressed: _help, icon: const Icon(Icons.help_outline),
          tooltip: _tr('使い方')),
        IconButton(onPressed: _loading ? null : _load,
          icon: const Icon(Icons.refresh), tooltip: _tr('再読み込み')),
      ],
    ),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (_loading) const LinearProgressIndicator(),
        if (_error != null) Text(_tr(_error!)),
        if (_master) ...[
          _entry('line-master-chat', Icons.chat_bubble_outline, 'チャット',
            '連携済みLINEグループの投稿者・日時・本文',
            widget.talkBuilder ?? (_) => const LineTalkPage()),
          _entry('line-master-invoices', Icons.receipt_long_outlined, '請求書',
            '月別の確認済み候補・保存履歴・正式下書き',
            widget.invoiceBuilder ?? (_) => const LineHistoricalInvoicePage()),
          _entry('line-master-rates', Icons.price_change_outlined, '単価設定',
            '対象月の人工・残業・早出・手当の履歴単価',
            widget.ratesBuilder ?? (_) => const LineHistoricalInvoicePage.rates()),
        ],
      ],
    ),
  );
}
