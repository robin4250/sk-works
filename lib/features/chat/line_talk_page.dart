import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'chat_cloud_repository.dart';

/// Stage one is a read-only view of saved LINE posts. It does not create attendance.
class LineTalkPage extends StatefulWidget {
  const LineTalkPage({super.key, this.initialGroupId});
  final String? initialGroupId;

  @override
  State<LineTalkPage> createState() => _LineTalkPageState();
}

class _LineTalkPageState extends State<LineTalkPage> {
  final _repository = ChatCloudRepository.maybeCreate();
  StreamSubscription<List<Map<String, dynamic>>>? _subscription;
  List<Map<String, dynamic>> _groups = const [];
  List<Map<String, dynamic>> _linkable = const [];
  List<Map<String, dynamic>> _messages = const [];
  Map<String, dynamic>? _selected;
  bool _loading = true;
  bool _busy = false;
  bool _canManage = false;
  bool _initialOpened = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final repository = _repository;
    if (repository == null) {
      setState(() { _loading = false; _error = 'SKOへのログインが必要です。'; });
      return;
    }
    try {
      final data = await repository.loadLineTalkGroups();
      if (!mounted) return;
      setState(() {
        _groups = data.groups;
        _linkable = data.linkable;
        _canManage = data.canManage;
        _loading = false;
        _error = null;
      });
      final initial = widget.initialGroupId;
      if (initial != null && !_initialOpened && _selected == null) {
        final matching=data.groups.where((group)=>group['id']?.toString()==initial);
        if(matching.length==1) { _initialOpened=true; await _open(matching.single); }
      }
    } catch (_) {
      if (mounted) setState(() { _loading = false; _error = 'LINEトークを読み込めませんでした。再読み込みしてください。'; });
    }
  }

  Future<void> _open(Map<String, dynamic> group) async {
    await _subscription?.cancel();
    if (!mounted) return;
    final id = group['id'].toString();
    setState(() { _selected = group; _messages = const []; _loading = true; _error = null; });
    _subscription = _repository!.watchLineTalkMessages(id).listen((rows) {
      if (!mounted || _selected?['id']?.toString() != id) return;
      setState(() {
        _messages = rows.where((row) => row['origin'] == 'line').toList(growable: false);
        _loading = false;
        _error = null;
      });
    }, onError: (Object _) {
      if (mounted && _selected?['id']?.toString() == id) {
        setState(() { _loading = false; _error = '受信トークを読み込めませんでした。再読み込みしてください。'; });
      }
    });
  }

  Future<void> _back() async {
    await _subscription?.cancel();
    _subscription = null;
    if (!mounted) return;
    setState(() { _selected = null; _messages = const []; _loading = true; });
    await _load();
  }

  void _help() {
    showDialog<void>(context: context, builder: (context) => AlertDialog(
      title: const Text('LINEトークの使い方'),
      content: const SingleChildScrollView(child: Text(
        '連携後にLINEグループへ投稿されたテキストを、グループごとに閲覧します。受信した文章・投稿者・日時を表示します。\n\n'
        '管理者は「LINEグループを連携」からSKOのトークを選び、連携文をコピーしてください。SKOの公式アカウントが参加したLINEグループに、期限内に連携文を送信します。送信後は再読み込みし、続けて投稿したテキストが表示されるか確認してください。\n\n'
        '停止中や連携前の過去投稿は自動では取得されません。画像・動画・スタンプとLINEへの返信はこの画面では扱いません。出勤表・請求書への取込はまだ行いません。')),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('閉じる'))],
    ));
  }

  Future<void> _link() async {
    final group = await showDialog<Map<String, dynamic>>(context: context, builder: (context) => SimpleDialog(
      title: const Text('連携するSKOトーク'),
      children: [
        if (_linkable.isEmpty) const Padding(padding: EdgeInsets.all(20), child: Text('先にチャットでグループを作成してください。')),
        for (final group in _linkable) SimpleDialogOption(
          onPressed: () => Navigator.pop(context, group),
          child: Text(group['display_name']?.toString() ?? group['name']?.toString() ?? 'トーク'),
        ),
      ],
    ));
    if (group == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final claim = await _repository!.beginLineBindingClaim(group['id'].toString());
      final code = claim['claim_code']?.toString() ?? '';
      if (code.isEmpty) throw StateError('連携コードなし');
      final expires = DateTime.tryParse(claim['expires_at']?.toString() ?? '')?.toLocal();
      if (!mounted) return;
      await showDialog<void>(context: context, builder: (context) => AlertDialog(
        title: const Text('LINEグループで送信'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(group['display_name']?.toString() ?? group['name']?.toString() ?? 'トーク'),
          const SizedBox(height: 12),
          SelectableText('SKO連携 $code', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          Text(expires == null ? '有効期限は発行から15分です。' : '有効期限：${_date(expires)}'),
          const Text('SKOの公式アカウントが参加したLINEグループに送信してください。'),
        ]),
        actions: [TextButton(onPressed: () async {
          await Clipboard.setData(ClipboardData(text: 'SKO連携 $code'));
          if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('連携文をコピーしました。')));
        }, child: const Text('連携文をコピー')), TextButton(onPressed: () => Navigator.pop(context), child: const Text('閉じる'))],
      ));
      await _load();
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('連携コードを発行できませんでした。再読み込みしてお試しください。')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _disable() async {
    final group = _selected;
    final id = group?['line_binding_id']?.toString();
    if (id == null) return;
    final confirmed = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
      title: const Text('LINE連携を停止しますか？'),
      content: const Text('これからの受信を停止します。保存済みのトークは残ります。'),
      actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('戻る')),
        TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('停止する'))],
    ));
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await _repository!.disableLineBinding(id);
      await _back();
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('LINE連携を停止できませんでした。')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _date(DateTime date) => '${date.year}/${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final selected = _selected;
    return PopScope(canPop: selected == null, onPopInvokedWithResult: (didPop, result) {
      if (!didPop && selected != null) _back();
    }, child: Scaffold(
      appBar: AppBar(
        leading: selected == null ? null : IconButton(onPressed: _busy ? null : _back, icon: const Icon(Icons.arrow_back), tooltip: 'LINEトーク一覧に戻る'),
        title: Text(selected == null ? 'LINEトーク' : selected['display_name']?.toString() ?? selected['name']?.toString() ?? 'LINEトーク'),
        actions: [IconButton(onPressed: _help, icon: const Icon(Icons.help_outline), tooltip: '使い方'),
          IconButton(onPressed: _busy ? null : () => selected == null ? _load() : _open(selected), icon: const Icon(Icons.refresh), tooltip: '再読み込み'),
          if (_canManage && selected?['line_binding_enabled'] == true)
            IconButton(onPressed: _busy ? null : _disable, icon: const Icon(Icons.link_off), tooltip: 'LINE連携を停止')],
      ),
      body: Column(children: [
        if (selected == null && _canManage) Padding(padding: const EdgeInsets.all(12), child: OutlinedButton.icon(
          onPressed: _busy ? null : _link, icon: const Icon(Icons.link), label: const Text('LINEグループを連携'))),
        if (_busy) const LinearProgressIndicator(),
        Expanded(child: _loading ? const Center(child: CircularProgressIndicator())
          : _error != null ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!)))
          : selected == null ? _groupList() : _messageList()),
      ]),
    ));
  }

  Widget _groupList() {
    if (_groups.isEmpty) return const Center(child: Padding(padding: EdgeInsets.all(24), child: Text('受信したLINEトークはまだありません。\n連携後、LINEグループでテキストを投稿してください。', textAlign: TextAlign.center)));
    return ListView.separated(itemCount: _groups.length, separatorBuilder: (_, index) => const Divider(height: 1), itemBuilder: (context, index) {
      final group = _groups[index];
      return ListTile(leading: const Icon(Icons.chat_bubble_outline),
        title: Text(group['display_name']?.toString() ?? group['name']?.toString() ?? 'LINEトーク'),
        subtitle: Text(group['line_binding_enabled'] == true ? '受信中' : '保存済みトーク'),
        trailing: const Icon(Icons.chevron_right), onTap: () => _open(group));
    });
  }

  Widget _messageList() {
    if (_messages.isEmpty) return const Center(child: Padding(padding: EdgeInsets.all(24), child: Text('このグループの受信テキストはまだありません。\nLINEで投稿後、再読み込みしてください。', textAlign: TextAlign.center)));
    return ListView.separated(itemCount: _messages.length, padding: const EdgeInsets.all(16), separatorBuilder: (_, index) => const SizedBox(height: 12), itemBuilder: (context, index) {
      final message = _messages[index];
      final at = DateTime.tryParse(message['sent_at']?.toString() ?? '')?.toLocal();
      return Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('${message['sender_display_name'] ?? 'LINE'}${at == null ? '' : '  ${_date(at)}'}', style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(height: 8), SelectableText(message['body']?.toString() ?? ''),
      ])));
    });
  }
}

