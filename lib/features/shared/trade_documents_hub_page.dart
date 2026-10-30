import 'dart:async';
import 'package:flutter/material.dart';
import 'standalone_trade_document_operation_gate.dart';
import 'standalone_trade_document_page.dart';
import 'trade_documents_hub_contract.dart';
import 'trade_documents_hub_repository.dart';

class TradeDocumentsHubPage extends StatefulWidget {
  const TradeDocumentsHubPage({super.key});
  @override State<TradeDocumentsHubPage> createState() => _TradeDocumentsHubPageState();
}

class _TradeDocumentsHubPageState extends State<TradeDocumentsHubPage> {
  TradeDocumentsHubRepository? _repository;
  TradeDocumentsHubSnapshot? _value;
  bool _loading = true, _opening = false;
  String? _error;
  @override void initState() {
    super.initState();
    _repository = TradeDocumentsHubRepository.maybeCreate();
    _repository?.addListener(_scopeChanged);
    _load();
  }
  void _scopeChanged() {
    try {
      _repository?.requireCurrent();
      if (mounted) { setState(() => _value = _repository?.snapshot); }
    }
    catch (_) {
      if (mounted) { setState(() { _value = null; _error = '注文・請書を開き直してください。'; }); }
    }
  }
  Future<void> _load() async {
    final repository = _repository;
    if (repository == null) {
      setState(() { _loading = false; _error = 'ログイン状態を確認してください。'; }); return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      final value = await repository.load();
      if (mounted) { setState(() { _value = value; _loading = false; }); }
    } catch (_) {
      if (mounted) { setState(() { _value = null; _loading = false;
        _error = '注文・請書の権限・機能設定を確認できません。再読み込みしてください。'; }); }
    }
  }
  Future<void> _open(bool acceptance) async {
    if (_opening || _loading) { return; }
    final repository = _repository;
    if (repository == null) { return; }
    setState(() => _opening = true);
    TradeDocumentsOperationLease? lease;
    try {
      final value = await repository.load();
      if (!mounted) { return; }
      if (!value.availability.enabled) { throw StateError('機能はOFFです。'); }
      final parties = value.parties.where((p) => p.permits(acceptance)).toList();
      if (parties.isEmpty) { throw StateError('対象の登録会社がありません。'); }
      final party = await showDialog<TradeDocumentsHubParty>(context: context,
        builder: (context) => SimpleDialog(title: Text(acceptance ? '取引会社を選択' : '協力会社を選択'),
          children: [for (final party in parties) SimpleDialogOption(
            onPressed: () => Navigator.pop(context, party), child: Text(party.name)),
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('戻る'))]));
      if (!mounted || party == null) { return; }
      final activeLease = TradeDocumentsOperationLease(repository: repository,
        companyId: value.companyId, tradeCompanyId: party.id, acceptance: acceptance);
      lease = activeLease;
      await activeLease.refresh();
      if (!mounted) { return; }
      await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) =>
        StandaloneTradeDocumentPage(tradeCompanyId: party.id,
          acceptance: acceptance, operationGate: activeLease)));
      if (mounted) { await _load(); }
    } catch (_) {
      if (mounted) { setState(() => _error = '生成を開始できません。機能設定・権限・登録会社を確認してください。'); }
    } finally {
      lease?.dispose();
      if (mounted) { setState(() => _opening = false); }
    }
  }
  @override void dispose() {
    _repository?.removeListener(_scopeChanged); _repository?.dispose(); super.dispose();
  }
  @override Widget build(BuildContext context) {
    final value = _value;
    final enabled = value?.availability.enabled == true;
    return Scaffold(appBar: AppBar(title: const Text('注文・請書'), actions: [
      IconButton(onPressed: _loading || _opening ? null : _load,
        tooltip: '再読み込み', icon: const Icon(Icons.refresh))]),
      body: SafeArea(child: _loading ? const Center(child: CircularProgressIndicator())
        : ListView(padding: const EdgeInsets.all(16), children: [
          Text(value?.availability.enabled == true ? 'マスター設定：ON' : 'マスター設定：OFF',
            style: Theme.of(context).textTheme.titleMedium),
          if (value?.availability.supported != true)
            const Text('注文・請書の接続を準備中です。保存済み書類は既存の一覧から確認できます。'),
          if (_error != null) Text(_error!),
          const SizedBox(height: 16),
          FilledButton.icon(key: const Key('trade-hub-order'),
            onPressed: enabled && !_opening ? () => _open(false) : null,
            icon: const Icon(Icons.description_outlined), label: const Text('注文書生成')),
          const SizedBox(height: 12),
          FilledButton.icon(key: const Key('trade-hub-acceptance'),
            onPressed: enabled && !_opening ? () => _open(true) : null,
            icon: const Icon(Icons.task_alt), label: const Text('請書生成')),
        ])));
  }
}

/// A failed refresh or expiry retires this operation permanently. It cannot be
/// re-enabled by navigating back or switching a local boolean.
class TradeDocumentsOperationLease extends ChangeNotifier
    implements StandaloneTradeDocumentOperationGate {
  TradeDocumentsOperationLease({required this.repository, required this.companyId,
    required this.tradeCompanyId, required this.acceptance}) {
    repository.addListener(_changed);
  }
  final TradeDocumentsHubRepository repository;
  @override final String companyId, tradeCompanyId;
  @override final bool acceptance;
  bool _retired = false, _disposed = false;
  DateTime? _expires;
  Timer? _timer;
  Future<void>? _refreshing;
  void _retire() {
    if (!_retired && !_disposed) { _retired = true; notifyListeners(); }
  }
  void _changed() {
    try { repository.requireOperation(companyId, tradeCompanyId, acceptance); }
    catch (_) { _retire(); }
  }
  @override void requireCurrent() {
    if (_retired || _disposed || _expires == null || !DateTime.now().isBefore(_expires!)) {
      _retire(); throw StateError('注文・請書の確認期限が切れました。開き直してください。');
    }
    repository.requireOperation(companyId, tradeCompanyId, acceptance);
  }
  @override Future<void> refresh() => _refreshing ??= _refresh().whenComplete(() => _refreshing = null);
  Future<void> _refresh() async {
    if (_retired || _disposed) { throw StateError('注文・請書を開き直してください。'); }
    try {
      await repository.refreshOperation(companyId, tradeCompanyId, acceptance);
      if (_retired || _disposed) { throw StateError('注文・請書を開き直してください。'); }
      _expires = DateTime.now().add(const Duration(seconds: 15));
      _timer ??= Timer.periodic(const Duration(seconds: 5), (_) {
        unawaited(refresh().catchError((Object _) { _retire(); }));
      });
      requireCurrent();
    } catch (_) { _retire(); rethrow; }
  }
  @override void dispose() {
    if (_disposed) { return; }
    _disposed = true; _retired = true; _timer?.cancel();
    repository.removeListener(_changed); super.dispose();
  }
}
