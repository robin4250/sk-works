import 'dart:async';
import 'package:flutter/material.dart';
import 'company_link_scope.dart';

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

class _CompanyLinkPageState extends State<CompanyLinkPage> {
  late final CompanyLinkScope _scope;
  final _query = TextEditingController();
  Map<String, dynamic>? _workspace;
  List<Map<String, dynamic>> _results = const [];
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _scope = widget.repository.createLinkScope();
    _run(() async {
      await _scope.loadContexts();
      if (_scope.company != null) await _reload();
    });
  }

  @override
  void dispose() {
    unawaited(_scope.close());
    _query.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    final value = await _scope.workspace();
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
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _request(Map<String, dynamic> company) async {
    final generation = _scope.generation;
    final now = DateTime.now();
    final selected = await showDatePicker(
      context: context,
      helpText: '連携開始月を選択（日は1日に揃えます）',
      initialDate: DateTime(now.year, now.month),
      firstDate: DateTime(2000),
      lastDate: DateTime(now.year + 10, 12, 31),
    );
    if (selected == null || !mounted) return;
    final role = widget.mode == TradeCompanyPageMode.customer
        ? '相手を取引会社、自社を相手の協力会社として申請'
        : '相手を協力会社、自社を相手の取引会社として申請';
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
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
    );
    if (confirm != true) return;
    await _run(() async {
      _scope.requireGeneration(generation);
      await _scope.request(
        target: company['company_id'].toString(),
        role: widget.mode == TradeCompanyPageMode.customer ? 'customer' : 'subcontractor',
        month: DateTime(selected.year, selected.month),
      );
      await _reload();
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('連携申請を送信しました')));
      }
    });
  }

  Future<void> _respond(Map<String, dynamic> request, String action) async {
    final generation = _scope.generation;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
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
    );
    if (confirmed != true) return;
    await _run(() async {
      _scope.requireGeneration(generation);
      await _scope.respond(request['id'].toString(), action);
      await _reload();
    });
  }

  @override
  Widget build(BuildContext context) {
    final enabled = _workspace?['enabled'] == true;
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
          DropdownButtonFormField<String>(
            key: ValueKey('company-link-${_scope.generation}'),
            initialValue: _scope.company,
            decoration: const InputDecoration(labelText: '操作する自社'),
            items: [for (final company in _scope.contexts)
              DropdownMenuItem(value: company.id, child: Text(company.name))],
            onChanged: _busy ? null : (company) {
              if (company == null) return;
              setState(() { _scope.select(company); _workspace = null; _results = []; _query.clear(); });
              _run(_reload);
            },
          ),
          if (!_busy && _scope.contexts.isEmpty) const Text('会社の管理権限がありません。所属と権限を確認してください。'),
          if (_scope.contexts.length > 1 && _scope.company == null) const Text('操作する自社を選択してください。'),
          const Text('会社名・法人番号で検索 → 申請 → 相手が承認 → 双方の一覧へ反映'),
          const Text('連携は会社間の関係登録です。社員情報や給与の公開にはなりません。'),
          if (_workspace != null)
            SwitchListTile(
              title: const Text('会社検索・連携申請を利用する'),
              value: enabled,
              onChanged: _busy
                  ? null
                  : (value) => _run(() async {
                      await _scope.setEnabled(value);
                      await _reload();
                    }),
            ),
          if (_busy) const LinearProgressIndicator(),
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
            onSubmitted: enabled && !_busy ? (_) => _search() : null,
          ),
          FilledButton.icon(
            onPressed: enabled && !_busy ? _search : null,
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
                  onPressed: _busy || !enabled ? null : () => _request(company),
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
                                  onPressed: _busy
                                      ? null
                                      : () => _respond(request, 'accept'),
                                  child: const Text('承認'),
                                ),
                                OutlinedButton(
                                  onPressed: _busy
                                      ? null
                                      : () => _respond(request, 'reject'),
                                  child: const Text('却下'),
                                ),
                              ],
                            ),
                          if (pending && !incoming)
                            OutlinedButton(
                              onPressed: _busy
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
    final results = await _scope.search(_query.text);
    if (mounted) {
      setState(() => _results = results);
      if (results.isEmpty) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('該当する会社はありません')));
      }
    }
  });
}
