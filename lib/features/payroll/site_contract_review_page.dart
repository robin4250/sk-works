import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/supabase_backend.dart';
import 'site_contract_status.dart';
import 'site_contract_action_coordinator.dart';
import 'site_contract_action_review_page.dart';

/// Reads the existing sealed workspace; this page has no mutation or signing API.
class SiteContractReviewPage extends StatefulWidget {
  const SiteContractReviewPage({
    super.key,
    required this.sharedItemId,
    required this.companyId,
  });

  final String sharedItemId;
  final String companyId;

  @override
  State<SiteContractReviewPage> createState() => _SiteContractReviewPageState();
}

class _SiteContractReviewPageState extends State<SiteContractReviewPage> {
  Map<String, dynamic>? _workspace;
  String? _error;
  bool _loading = true;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final generation = ++_generation;
    setState(() { _loading = true; _workspace = null; _error = null; });
    if (!SupabaseBackend.isInitialized ||
        SupabaseBackend.client.auth.currentUser == null) {
      setState(() { _loading = false; _error = 'ログインが必要です。'; });
      return;
    }
    final actor = SupabaseBackend.client.auth.currentUser!.id;
    try {
      final raw = await SupabaseBackend.client.rpc('site_contract_workspace',
        params: {'p_item': widget.sharedItemId, 'p_company': widget.companyId});
      if (!mounted || generation != _generation) {
        return;
      }
      if (SupabaseBackend.client.auth.currentUser?.id != actor) {
        throw StateError('ログイン情報が変わりました。画面を開き直してください。');
      }
      if (raw is! Map) {
        throw const FormatException('契約内容を確認できません。');
      }
      setState(() => _workspace = Map<String, dynamic>.from(raw));
    } on PostgrestException catch (error) {
      if (mounted && generation == _generation) {
        setState(() => _error = const {'42883', 'PGRST202', '55000'}.contains(error.code)
          ? '双方押印の契約確認はまだ利用できません。利用設定または提供開始を確認してください。'
          : 'この契約を開けません。会社・共有現場・利用権限を確認してください。');
      }
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() => _error = '契約内容を確認できません。ログイン情報を確認して再読み込みしてください。');
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('契約候補を確認'), actions: [
      PopupMenuButton<SiteContractAction>(tooltip: '送信・承認の確認',
        onSelected: (action) => Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => SiteContractActionReviewPage(action: action,
            sharedItemId: widget.sharedItemId, companyId: widget.companyId))),
        itemBuilder: (_) => const [
          PopupMenuItem(value: SiteContractAction.send, child: Text('送信内容を確認')),
          PopupMenuItem(value: SiteContractAction.approve, child: Text('承認内容を確認')),
        ],
      ),
      IconButton(tooltip: '使い方', icon: const Icon(Icons.help_outline),
        onPressed: () => showDialog<void>(context: context, builder: (context) => AlertDialog(
          title: const Text('契約候補の確認'),
          content: const Text('現在の合意と変更候補を分けて表示します。相手の押印承認が揃うまで現行条件は変わりません。双方承認済みでも適用開始日前なら次回の合意として表示します。押印日時・担当者は保存済み記録だけを表示し、従来の確認操作を押印済みとは扱いません。この画面を見るだけでは送信・押印・承認・金額変更は行いません。右上のメニューから操作前の確認へ進めます。実会社印と最新版が確認できない場合や提供前は準備中のまま操作できません。利用設定がOFFまたは提供前の場合は契約内容を表示しません。'),
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('閉じる'))],
        )),
      ),
    ]),
    body: _loading ? const Center(child: CircularProgressIndicator())
      : _error != null ? Padding(padding: const EdgeInsets.all(16), child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [Text(_error!), TextButton(onPressed: _load, child: const Text('再読み込み'))]))
      : SiteContractReviewContent(workspace: _workspace!, companyId: widget.companyId,
          today: DateTime.now()),
  );
}

class SiteContractReviewContent extends StatelessWidget {
  const SiteContractReviewContent({super.key, required this.workspace,
    required this.companyId, required this.today});
  final Map<String, dynamic> workspace;
  final String companyId;
  final DateTime today;

  List<Map<String, dynamic>> _seals(Map<String, dynamic> proposal, Set<String> parties) => [
    if (proposal['seals'] is List)
      for (final raw in proposal['seals'] as List)
        if (raw is Map && parties.contains(raw['company_id']) &&
            const {'sent', 'approved'}.contains(raw['action']) &&
            raw['actor_id'] is String && (raw['actor_id'] as String).isNotEmpty &&
            DateTime.tryParse('${raw['recorded_at']}') != null && raw['seal_snapshot'] is Map)
          Map<String, dynamic>.from(raw),
  ];

  String _value(Object? value) => value == null || value.toString().isEmpty
      ? '未設定' : value.toString();
  String _money(Object? value) => value is num && value.isFinite && value >= 0
      ? '${value.toString()}円' : '金額未確認';

  @override
  Widget build(BuildContext context) {
    final parent = workspace['parent_company_id'];
    final child = workspace['child_company_id'];
    if (parent is! String || child is! String || parent.isEmpty || child.isEmpty ||
        parent == child || !{parent, child}.contains(companyId)) {
      return const Padding(padding: EdgeInsets.all(16), child: Text('契約当事者を確認できません。'));
    }
    final parties = {parent, child};
    final proposals = <Map<String, dynamic>>[
      if (workspace['proposals'] is List)
        for (final raw in workspace['proposals'] as List)
          if (raw is Map && raw['revision'] is int && raw['terms'] is Map)
            Map<String, dynamic>.from(raw),
    ];
    // A legacy confirmation without an immutable seal is never shown as signed.
    final projected = [for (final proposal in proposals) <String, dynamic>{
      ...proposal, 'confirmations': [for (final seal in _seals(proposal, parties))
        {'company_id': seal['company_id']}],
    }];
    final status = SiteContractStatus.fromProposals(projected,
      parentCompanyId: parent, childCompanyId: child, today: today);
    Widget summary(String title, Map<String, dynamic>? proposal) => Card(
      child: Padding(padding: const EdgeInsets.all(12), child: Column(
        crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          if (proposal == null) const Text('双方の押印記録が揃った現行の合意はありません。')
          else ...[
            Text('第${proposal['revision']}版・${_money((proposal['terms'] as Map)['final_amount_yen'])}'),
            Text('適用開始：${_value((proposal['terms'] as Map)['effective_from'] ?? (proposal['terms'] as Map)['period_start'])}'),
          ],
        ],
      )),
    );
    return ListView(padding: const EdgeInsets.all(16), children: [
      Text(status.label, style: Theme.of(context).textTheme.titleLarge),
      const Text('変更候補は相手の押印承認まで現行条件に置き換えません。'),
      summary('現在の合意', status.active),
      if (status.pending != null) summary('契約候補・承認待ち', status.pending),
      if (status.scheduled != null) summary('次回の合意・適用開始待ち', status.scheduled),
      if (proposals.isEmpty) const Text('契約候補はありません。'),
      for (final proposal in proposals) Card(child: Padding(
        padding: const EdgeInsets.all(12), child: Column(
          crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('第${proposal['revision']}版の内訳'),
            Text('候補総額：${_money((proposal['terms'] as Map)['final_amount_yen'])}'),
            Text('対象期間：${_value((proposal['terms'] as Map)['period_start'])} ～ ${_value((proposal['terms'] as Map)['period_end'])}'),
            Text('基本額：${_money((proposal['terms'] as Map)['base_amount_yen'])}'),
            Text('消費税：${_money((proposal['terms'] as Map)['tax_amount_yen'])}'),
            for (final party in parties)
              Text(_seals(proposal, parties).any((seal) => seal['company_id'] == party)
                ? '${party == companyId ? '自社' : '相手会社'}：押印記録あり'
                : '${party == companyId ? '自社' : '相手会社'}：押印記録未確認'),
            if (_seals(proposal, parties).isNotEmpty)
              ExpansionTile(title: const Text('押印記録を確認'), children: [
                for (final seal in _seals(proposal, parties))
                  ListTile(title: Text('${seal['company_id'] == companyId ? '自社' : '相手会社'} ${seal['action'] == 'sent' ? '送信時押印' : '承認時押印'}'),
                    subtitle: Text('担当ID：${seal['actor_id']}\n記録日時：${seal['recorded_at']}')),
              ]),
          ],
        ),
      )),
    ]);
  }
}
