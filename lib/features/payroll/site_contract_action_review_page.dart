import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../data/supabase_backend.dart';
import '../../domain/company_seal_snapshot.dart';
import 'site_contract_action_coordinator.dart';
import 'site_contract_action_repository.dart';
import 'site_contract_seal_preview.dart';
import 'site_payment_terms_comparison.dart';

class SiteContractActionReviewPage extends StatefulWidget {
  const SiteContractActionReviewPage({super.key, required this.action,
    required this.sharedItemId, required this.companyId, this.gateway, this.renderSeal});
  final SiteContractAction action;
  final String sharedItemId;
  final String companyId;
  final SiteContractActionGateway? gateway;
  final Future<Uint8List> Function(CompanySealSnapshot seal, String companyId)? renderSeal;
  @override
  State<SiteContractActionReviewPage> createState() => _SiteContractActionReviewPageState();
}

class _SiteContractActionReviewPageState extends State<SiteContractActionReviewPage> {
  late final SiteContractActionGateway? _gateway = widget.gateway ??
      (SupabaseBackend.isInitialized ? SiteContractActionRepository(SupabaseBackend.client) : null);
  SiteContractActionDraft? _draft;
  Uint8List? _sealBytes;
  String? _error;
  bool _loading = true;
  bool _executing = false;
  bool _conditionsConfirmed = false;
  bool _sealViewed = false;
  bool _sealConfirmed = false;
  bool _mustReload = false;
  int _generation = 0;
  SiteContractActionOutcome? _outcome;
  final _effective = TextEditingController();

  @override
  void initState() { super.initState(); _load(); }
  @override
  void dispose() { _effective.dispose(); super.dispose(); }

  Future<void> _load() async {
    final generation = ++_generation;
    setState(() {
      _loading = true; _draft = null; _sealBytes = null; _error = null;
      _conditionsConfirmed = false; _sealViewed = false; _sealConfirmed = false;
      _mustReload = false; _outcome = null;
    });
    try {
      final gateway = _gateway;
      if (gateway == null) {
        throw StateError('login required');
      }
      final draft = await SiteContractActionCoordinator(gateway).prepare(
        widget.action, widget.sharedItemId, widget.companyId);
      final bytes = await (widget.renderSeal ?? renderSiteContractSeal)(draft.companySeal, draft.companyId);
      // A failed image decode must not count as a human-viewable company seal.
      final codec = await ui.instantiateImageCodec(bytes);
      try {
        final frame = await codec.getNextFrame();
        frame.image.dispose();
      } finally { codec.dispose(); }
      if (!mounted || generation != _generation) {
        return;
      }
      if (gateway.actorId != draft.actorId) {
        throw StateError('actor changed');
      }
      setState(() {
        _draft = draft; _sealBytes = bytes;
        _effective.text = draft.terms['effective_from']?.toString() ?? '';
      });
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() => _error = '操作確認は準備中です。対象の最新版・実会社印・利用設定を確認できません。');
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _viewSeal() async {
    final bytes = _sealBytes;
    if (bytes == null || _executing) {
      return;
    }
    final viewed = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
      title: Text(_draft!.companySeal.name),
      content: SizedBox(width: 240, height: 240, child: InteractiveViewer(child: Image.memory(bytes))),
      actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('戻る')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('この会社印を確認'))],
    ));
    if (mounted && viewed == true) {
      setState(() => _sealViewed = true);
    }
  }

  Future<void> _confirm() async {
    final draft = _draft;
    final gateway = _gateway;
    if (_executing || _mustReload || draft == null || gateway == null) {
      return;
    }
    setState(() => _executing = true);
    final outcome = await SiteContractActionCoordinator(gateway).confirm(draft,
      conditionsConfirmed: _conditionsConfirmed, sealViewed: _sealViewed,
      sealConfirmed: _sealConfirmed,
      effectiveFrom: widget.action == SiteContractAction.send ? _effective.text : null);
    if (mounted) {
      setState(() {
        _outcome = outcome; _executing = false;
        _mustReload = const {SiteContractActionOutcome.success,
          SiteContractActionOutcome.unknown, SiteContractActionOutcome.stale}.contains(outcome);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final draft = _draft;
    final comparison = SitePaymentTermsComparison(parent: null, child: null);
    final allowed = _gateway?.mutationsEnabled == true && !_executing && !_mustReload &&
      _conditionsConfirmed && _sealViewed && _sealConfirmed;
    return Scaffold(
      appBar: AppBar(title: Text(widget.action == SiteContractAction.send ? '送信内容を確認' : '承認内容を確認'),
        actions: [IconButton(tooltip: '使い方', icon: const Icon(Icons.help_outline),
          onPressed: () => showDialog<void>(context: context, builder: (context) => AlertDialog(
            title: const Text('押印前の確認'),
            content: const Text('最新版の条件と登録済みの会社印を確認してチェックしてください。金額は現在の候補をそのまま使います。送信時に適用開始日が未登録の場合は、対象期間内の日付を入力してください。実行直前に条件と会社印を再確認します。変更があれば処理を止めるので、再読み込みして確認し直してください。結果が確認できない場合は、保存記録を確認してから操作してください。相手の承認は自動では行われません。双方の承認と適用日までは現在の合意を保持します。この画面の承認だけでは請求金額は変わりません。'),
            actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('閉じる'))],
          )))],
      ),
      body: _loading ? const Center(child: CircularProgressIndicator()) : ListView(
        padding: const EdgeInsets.all(16), children: [
          if (_error != null) Text(_error!),
          if (_gateway?.mutationsEnabled != true) const Text('押印操作は準備中です。現在は確認だけで、送信・承認は実行できません。'),
          if (draft != null) ...[
            Text(widget.action == SiteContractAction.send
              ? '送信候補：第${draft.revision + 1}版（元の条件：第${draft.revision}版）'
              : '承認対象：第${draft.revision}版', style: Theme.of(context).textTheme.titleLarge),
            Text('会社印：${draft.companySeal.name}'),
            const Text('相手の承認・適用日までは現行条件を変更しません。'),
            for (final field in SitePaymentTermsComparison.fields.entries)
              ListTile(contentPadding: EdgeInsets.zero, title: Text(field.value),
                subtitle: Text(comparison.display({'terms': draft.terms}, field.key))),
            if (widget.action == SiteContractAction.send)
              TextField(controller: _effective, enabled: !_executing && !_mustReload,
                decoration: const InputDecoration(labelText: '適用開始日（YYYY-MM-DD・必須）'),
                onChanged: (_) => setState(() => _conditionsConfirmed = false)),
            OutlinedButton(onPressed: _executing ? null : _viewSeal, child: const Text('会社印を拡大して確認')),
            CheckboxListTile(value: _conditionsConfirmed, title: const Text('対象版・条件・適用日を確認しました'),
              onChanged: _executing || _mustReload ? null : (v) => setState(() => _conditionsConfirmed = v == true)),
            CheckboxListTile(value: _sealConfirmed, title: const Text('この登録会社印で操作します'),
              onChanged: !_sealViewed || _executing || _mustReload ? null : (v) => setState(() => _sealConfirmed = v == true)),
            FilledButton(onPressed: allowed ? _confirm : null,
              child: Text(widget.action == SiteContractAction.send ? '確認した会社印で送信' : '確認した会社印で承認')),
          ],
          if (_outcome != null) Text(switch (_outcome!) {
            SiteContractActionOutcome.success => '保存済みの押印記録との一致を確認しました。相手承認・適用日まで現行条件を保持します。',
            SiteContractActionOutcome.stale => '対象版・条件・会社印または利用者が変わりました。再読み込みして確認し直してください。',
            SiteContractActionOutcome.unknown => '実行結果を確認できません。自動再送せず、再読み込みで保存記録を確認してください。',
            _ => '操作を実行できません。確認項目・適用開始日・利用状態を見直してください。',
          }),
          TextButton(onPressed: _executing ? null : _load, child: const Text('再読み込み')),
        ],
      ),
    );
  }
}
