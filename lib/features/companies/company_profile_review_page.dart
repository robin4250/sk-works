import 'package:flutter/material.dart';

import '../../data/supabase_backend.dart';

class CompanyProfileReviewPage extends StatefulWidget {
  const CompanyProfileReviewPage({super.key, this.initialReviewId});
  final String? initialReviewId;
  @override
  State<CompanyProfileReviewPage> createState() =>
      _CompanyProfileReviewPageState();
}

class _CompanyProfileReviewPageState extends State<CompanyProfileReviewPage> {
  Map<String, dynamic>? _data;
  bool _busy = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _run(_reload);
  }

  Future<void> _reload() async {
    final raw = await SupabaseBackend.client.rpc(
      'company_profile_review_workspace',
    );
    if (mounted) setState(() => _data = Map<String, dynamic>.from(raw as Map));
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _respond(Map row, bool accept) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(accept ? '会社情報を更新しますか？' : '今回は更新しませんか？'),
        content: const Text(
          '情報が更新されたみたいなので、更新しますか？旧登録情報はそのまま記録に残ります。契約単価や過去の帳票は変更しません。',
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
      await SupabaseBackend.client.rpc(
        'respond_company_profile_review',
        params: {'p_review_id': row['id'], 'p_accept': accept},
      );
      await _reload();
    });
  }

  @override
  Widget build(BuildContext context) {
    final enabled = _data?['enabled'] == true;
    final rows = ((_data?['reviews'] as List?) ?? const [])
        .where(
          (r) =>
              r is Map &&
              (widget.initialReviewId == null ||
                  r['id'] == widget.initialReviewId),
        )
        .toList();
    const labels = {
      'name': '会社名',
      'address': '住所',
      'phone': '電話番号',
      'email': 'メール',
      'corporate_number': '法人番号',
    };
    return Scaffold(
      appBar: AppBar(title: const Text('連携会社情報の更新確認')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('このページは右上のベルマークから何度も見れます！'),
          if (_busy) const LinearProgressIndicator(),
          if (_error != null) Text(_error!),
          if (_data != null)
            SwitchListTile(
              title: const Text('会社情報の変更通知・更新確認'),
              value: enabled,
              onChanged: _busy
                  ? null
                  : (v) => _run(() async {
                      await SupabaseBackend.client.rpc(
                        'set_company_profile_review_enabled',
                        params: {'p_enabled': v},
                      );
                      await _reload();
                    }),
            ),
          if (widget.initialReviewId != null && _data != null && rows.isEmpty)
            const Text('対象の更新情報が見つかりません。権限・所属会社を確認してください。'),
          for (final r in rows)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${(r['proposed'] as Map)['name']} / ${r['status'] == 'pending'
                          ? '確認待ち'
                          : r['status'] == 'accepted'
                          ? '更新済み'
                          : '見送り'}',
                    ),
                    Text('更新日時：${r['created_at']}'),
                    for (final key in labels.keys)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Text(
                          '${labels[key]}\n旧：${(r['old'] as Map)[key] ?? ''}\n更新候補：${(r['proposed'] as Map)[key] ?? ''}',
                        ),
                      ),
                    if (enabled && r['status'] == 'pending')
                      Wrap(
                        spacing: 8,
                        children: [
                          FilledButton(
                            onPressed: _busy ? null : () => _respond(r, true),
                            child: const Text('更新する'),
                          ),
                          OutlinedButton(
                            onPressed: _busy ? null : () => _respond(r, false),
                            child: const Text('今回は更新しない'),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
