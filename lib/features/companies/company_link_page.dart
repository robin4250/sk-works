import 'package:flutter/material.dart';

import 'trade_company_repository.dart';

/// Both company directories share this approval-first entry point.
class CompanyLinkPage extends StatefulWidget {
  const CompanyLinkPage({
    super.key,
    required this.repository,
    required this.mode,
  });
  final TradeCompanyRepository repository;
  final TradeCompanyPageMode mode;

  @override
  State<CompanyLinkPage> createState() => _CompanyLinkPageState();
}

class _CompanyLinkPageState extends State<CompanyLinkPage> {
  final _query = TextEditingController();
  Map<String, dynamic>? _workspace;
  List<Map<String, dynamic>> _results = const [];
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _run(_reload);
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    final value = await widget.repository.linkWorkspace();
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
      await widget.repository.requestLink(
        companyId: company['company_id'].toString(),
        mode: widget.mode,
        startMonth: DateTime(selected.year, selected.month),
      );
      await _reload();
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('連携申請を送信しました')));
    });
  }

  Future<void> _respond(Map<String, dynamic> request, String action) async {
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
      await widget.repository.respondLink(request['id'].toString(), action);
      await _reload();
    });
  }

  @override
  Widget build(BuildContext context) {
    final enabled = _workspace?['enabled'] == true;
    final requests = (_workspace?['requests'] as List?) ?? const [];
    return Scaffold(
      appBar: AppBar(title: const Text('会社を検索・連携')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('会社名・法人番号で検索 → 申請 → 相手が承認 → 双方の一覧へ反映'),
          const Text('連携は会社間の関係登録です。社員情報や給与の公開にはなりません。'),
          if (_workspace != null)
            SwitchListTile(
              title: const Text('会社検索・連携申請を利用する'),
              value: enabled,
              onChanged: _busy
                  ? null
                  : (value) => _run(() async {
                      await widget.repository.setLinkEnabled(value);
                      await _reload();
                    }),
            ),
          if (_busy) const LinearProgressIndicator(),
          if (_error != null)
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
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
    final results = await widget.repository.searchLinkCompanies(_query.text);
    if (mounted) {
      setState(() => _results = results);
      if (results.isEmpty)
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('該当する会社はありません')));
    }
  });
}
