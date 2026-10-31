import 'dart:async';

import 'package:flutter/material.dart';

import 'trade_company_repository.dart';

/// Both company directories share this approval-first entry point.
class CompanyLinkPage extends StatefulWidget {
  const CompanyLinkPage({
    super.key,
    required this.repository,
    required this.mode,
    this.initialRequestId,
  });
  final TradeCompanyRepository repository;
  final TradeCompanyPageMode mode;
  final String? initialRequestId;

  @override
  State<CompanyLinkPage> createState() => _CompanyLinkPageState();
}

class _CompanyLinkPageState extends State<CompanyLinkPage>
    with WidgetsBindingObserver {
  final _query = TextEditingController();
  Map<String, dynamic>? _workspace;
  List<Map<String, dynamic>> _results = const [];
  bool _busy = false;
  String? _error;
  CompanyLinkBoundContext? _bound;
  StreamSubscription<void>? _retirement;
  bool _routeRetired = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _run(_reload);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _retirement?.cancel();
    _bound?.dispose();
    _query.dispose();
    super.dispose();
  }

  void _invalidate() {
    _routeRetired = true;
    _bound?.retire();
    _query.clear();
    if (mounted) {
      setState(() {
        _workspace = null;
        _results = const [];
        _error = '表示条件が変わりました。画面を開き直してください';
      });
    }
  }

  @override
  void didUpdateWidget(covariant CompanyLinkPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.repository, widget.repository) ||
        oldWidget.mode != widget.mode ||
        oldWidget.initialRequestId != widget.initialRequestId) {
      _invalidate();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _invalidate();
  }

  Widget _guardedDialog(CompanyLinkBoundContext bound, Widget child) =>
      StreamBuilder<void>(
        stream: bound.retirements,
        builder: (context, _) => !_routeRetired && bound.isCurrent
            ? child
            : AlertDialog(
                title: const Text('表示条件が変わりました'),
                content: const Text('内容を非表示にしました。画面を開き直してください'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('閉じる'),
                  ),
                ],
              ),
      );

  Future<void> _reload() async {
    if (_routeRetired) return;
    if (_bound == null) {
      final bound = await widget.repository.openBoundLinkContext();
      if (!mounted || _routeRetired) {
        await bound.dispose();
        return;
      }
      _bound = bound;
      _retirement = bound.retirements.listen((_) {
        if (mounted) _invalidate();
      });
    }
    final value = await _bound!.workspace();
    if (mounted) setState(() => _workspace = value);
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is StateError
              ? error.message.toString()
              : '処理結果を確認できません。再送せず状態を確認してください',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _request(Map<String, dynamic> company) async {
    final bound = _bound;
    if (bound == null || !bound.isCurrent || bound.hasUnknownResult) return;
    final now = DateTime.now();
    final selected = await showDatePicker(
      context: context,
      helpText: '連携開始月を選択（日は1日に揃えます）',
      initialDate: DateTime(now.year, now.month),
      firstDate: DateTime(2000),
      lastDate: DateTime(now.year + 10, 12, 31),
    );
    if (selected == null || !mounted || !bound.isCurrent) return;
    final role = widget.mode == TradeCompanyPageMode.customer
        ? '相手を取引会社、自社を相手の協力会社として申請'
        : '相手を協力会社、自社を相手の取引会社として申請';
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => _guardedDialog(
        bound,
        AlertDialog(
          title: const Text('連携申請を送信しますか？'),
          content: Text(
            '${company['company_name']}\n$role\n${selected.year}年${selected.month}月から\n\n相手の承認後に双方の一覧へ追加します。給与・個人情報は自動共有しません。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('戻る'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('申請'),
            ),
          ],
        ),
      ),
    );
    if (confirm != true || !mounted || !bound.isCurrent) return;
    await _run(() async {
      await bound.mutate('request', {
        'target_company_id': company['company_id'],
        'local_role': widget.mode == TradeCompanyPageMode.customer
            ? 'customer'
            : 'subcontractor',
        'start_month':
            '${selected.year}-${selected.month.toString().padLeft(2, '0')}-01',
      });
      await _reload();
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('連携申請を送信しました')));
      }
    });
  }

  Future<void> _respond(Map<String, dynamic> request, String action) async {
    final bound = _bound;
    if (bound == null || !bound.isCurrent || bound.hasUnknownResult) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => _guardedDialog(
        bound,
        AlertDialog(
          title: Text(
            action == 'accept'
                ? '連携を承認しますか？'
                : action == 'cancel'
                ? '申請を取り消しますか？'
                : '申請を却下しますか？',
          ),
          content: Text(
            '${request['company_name']}\n開始月：${request['start_month']}\n自社側：${request['local_role'] == 'customer' ? '取引会社' : '協力会社'}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('戻る'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('確認'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted || !bound.isCurrent) return;
    await _run(() async {
      await bound.mutate('respond', {
        'request_id': request['id'],
        'action': action,
      });
      await _reload();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_routeRetired) {
      return Scaffold(
        appBar: AppBar(title: const Text('会社を検索・連携')),
        body: const Center(child: Text('表示条件が変わりました。画面を開き直してください')),
      );
    }
    final enabled = _workspace?['enabled'] == true;
    final blocked =
        _busy || _bound?.isCurrent != true || _bound?.hasUnknownResult == true;
    final allRequests = (_workspace?['requests'] as List?) ?? const [];
    final requests = widget.initialRequestId == null
        ? allRequests
        : allRequests
              .where(
                (row) => row is Map && row['id'] == widget.initialRequestId,
              )
              .toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('会社を検索・連携'),
        actions: [
          IconButton(
            tooltip: '使い方',
            icon: const Icon(Icons.help_outline),
            onPressed: () => showDialog<void>(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('会社検索・連携の使い方'),
                content: const Text(
                  '会社管理者は「設定」→「会社検索・連携設定」から利用を切り替えます。初期状態はOFFです。検索・申請・承認には自社と相手の両方をONにしてください。OFFでも履歴は削除しません。\n\n会社名・法人番号で検索し、開始月を選んで申請します。取引会社から申請すると自社は相手の協力会社、協力会社から申請すると自社は相手の取引会社になります。相手の管理者が承認した時だけ双方の一覧へ追加します。\n\n送信済み申請は承認前なら取り消せます。受信した申請は開始月・会社情報を確認して承認または却下してください。社員情報・給与・契約単価は自動共有しません。',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('閉じる'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('会社名・法人番号で検索 → 申請 → 相手が承認 → 双方の一覧へ反映'),
          const Text('連携は会社間の関係登録です。社員情報や給与の公開にはなりません。'),
          if (_workspace != null)
            SwitchListTile(
              title: const Text('会社検索・連携申請を利用する'),
              value: enabled,
              onChanged: blocked
                  ? null
                  : (value) => _run(() async {
                      await _bound!.mutate('set_enabled', {'enabled': value});
                      await _reload();
                    }),
            ),
          if (_busy) const LinearProgressIndicator(),
          if (_bound?.hasUnknownResult == true)
            OutlinedButton(
              onPressed: _busy
                  ? null
                  : () => _run(() async {
                      final result = await _bound!.inspectUnknownResult();
                      if (result['state'] == 'committed') {
                        await _reload();
                      } else if (mounted) {
                        setState(() => _error = 'まだ保存結果を確認できません。再送しないでください');
                      }
                    }),
              child: const Text('前の処理結果を確認（再送しません）'),
            ),
          if (_error != null)
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          if (widget.initialRequestId != null &&
              _workspace != null &&
              requests.isEmpty)
            const Text('対象の連携申請が見つかりません。所属会社や閲覧権限が変更された可能性があります。'),
          TextField(
            controller: _query,
            decoration: const InputDecoration(labelText: '会社名・法人番号（2文字以上）'),
            onSubmitted: enabled && !blocked ? (_) => _search() : null,
          ),
          FilledButton.icon(
            onPressed: enabled && !blocked ? _search : null,
            icon: const Icon(Icons.search),
            label: const Text('検索'),
          ),
          for (final company in _results)
            Card(
              child: ListTile(
                title: Text(company['company_name'].toString()),
                subtitle: Text(
                  '${company['address'] ?? ''}\n法人番号：${company['corporate_number'] ?? ''}',
                ),
                trailing: OutlinedButton(
                  onPressed: blocked || !enabled
                      ? null
                      : () => _request(company),
                  child: const Text('連携申請'),
                ),
              ),
            ),
          const Divider(),
          const Text('受信・送信履歴', style: TextStyle(fontWeight: FontWeight.bold)),
          for (final raw in requests)
            if (raw is Map)
              Builder(
                builder: (context) {
                  final request = Map<String, dynamic>.from(raw);
                  final incoming = request['incoming'] == true;
                  final pending = request['status'] == 'pending';
                  final status = switch (request['status']) {
                    'accepted' => '承認済み',
                    'rejected' => '却下',
                    'cancelled' => '取消',
                    _ => '承認待ち',
                  };
                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${incoming ? '受信' : '送信'}：${request['company_name']} / $status',
                          ),
                          Text(
                            '開始月：${request['start_month']}\n自社側：${request['local_role'] == 'customer' ? '取引会社' : '協力会社'}\n${request['created_at']}',
                          ),
                          if (pending && incoming && enabled)
                            Wrap(
                              spacing: 8,
                              children: [
                                FilledButton(
                                  onPressed: blocked
                                      ? null
                                      : () => _respond(request, 'accept'),
                                  child: const Text('承認'),
                                ),
                                OutlinedButton(
                                  onPressed: blocked
                                      ? null
                                      : () => _respond(request, 'reject'),
                                  child: const Text('却下'),
                                ),
                              ],
                            ),
                          if (pending && !incoming)
                            OutlinedButton(
                              onPressed: blocked
                                  ? null
                                  : () => _respond(request, 'cancel'),
                              child: const Text('申請取消'),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
        ],
      ),
    );
  }

  Future<void> _search() => _run(() async {
    final results = await _bound!.search(_query.text);
    if (mounted) {
      setState(() => _results = results);
      if (results.isEmpty) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('該当する会社はありません')));
      }
    }
  });
}
