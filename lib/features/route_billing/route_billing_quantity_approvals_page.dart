import 'package:flutter/material.dart';

import '../notifications/notification_bell.dart';
import 'route_billing_quantity_approval_repository.dart';

class RouteBillingQuantityApprovalsPage extends StatefulWidget {
  const RouteBillingQuantityApprovalsPage({super.key, this.initialRequestId})
    : repositoryOverride = null;

  @visibleForTesting
  const RouteBillingQuantityApprovalsPage.forTesting({
    super.key,
    required this.repositoryOverride,
    this.initialRequestId,
  });
  final RouteBillingQuantityApprovalRepository? repositoryOverride;
  final String? initialRequestId;
  @override
  State<RouteBillingQuantityApprovalsPage> createState() =>
      _RouteBillingQuantityApprovalsPageState();
}

class _RouteBillingQuantityApprovalsPageState
    extends State<RouteBillingQuantityApprovalsPage> {
  late final _repository =
      widget.repositoryOverride ??
      RouteBillingQuantityApprovalRepository.maybeCreate();
  List<RouteBillingQuantityRequest> _items = [];
  bool _loading = true;
  bool _busy = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final repository = _repository;
      if (repository == null) {
        throw StateError('請求数量の承認を利用できません');
      }
      final rows = widget.initialRequestId == null
          ? await repository.pending()
          : [await repository.detail(widget.initialRequestId!)];
      if (mounted) {
        setState(() {
          _items = rows;
          _loading = false;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error.toString();
          _loading = false;
        });
      }
    }
  }

  Future<void> _open(RouteBillingQuantityRequest item) async {
    if (_busy || _repository == null) {
      return;
    }
    setState(() => _busy = true);
    try {
      final detail = await _repository.detail(item.id);
      if (!mounted) {
        return;
      }
      final changed = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) =>
              _QuantityDecisionPage(repository: _repository, request: detail),
        ),
      );
      if (changed == true && mounted) {
        await _load();
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$error')));
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('ルート請求数量の承認'),
      actions: const [SkoNotificationBell()],
    ),
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : _error != null
        ? Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_error!),
                TextButton(onPressed: _load, child: const Text('再読み込み')),
              ],
            ),
          )
        : _items.isEmpty
        ? const Center(child: Text('承認待ちはありません'))
        : RefreshIndicator(
            onRefresh: _load,
            child: ListView(
              children: [
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('取引会社ごとに請求数量を承認します。同じ会社の複数訪問はまとめて確認できます。'),
                ),
                for (final item in _items)
                  Card(
                    child: ListTile(
                      title: Text(item.customerName),
                      subtitle: Text(
                        '${item.workDate}  ${item.workerName}\n請求数量 ${item.quantity ?? "未設定"}',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: _busy ? null : () => _open(item),
                    ),
                  ),
              ],
            ),
          ),
  );
}

class _QuantityDecisionPage extends StatefulWidget {
  const _QuantityDecisionPage({
    required this.repository,
    required this.request,
  });
  final RouteBillingQuantityApprovalRepository repository;
  final RouteBillingQuantityRequest request;
  @override
  State<_QuantityDecisionPage> createState() => _QuantityDecisionPageState();
}

class _QuantityDecisionPageState extends State<_QuantityDecisionPage> {
  double? _quantity;
  String? _siteId;
  final _price = TextEditingController();
  final _note = TextEditingController();
  bool _busy = false;
  @override
  void initState() {
    super.initState();
    final value = widget.request.quantity;
    if (value == 1 || value == 0.5) {
      _quantity = value;
    }
    _siteId = widget.request.raw['representative_site_id']?.toString();
    final savedPrice = widget.request.raw['unit_price_yen'];
    if (savedPrice is num && savedPrice > 0) {
      _price.text = savedPrice.toInt().toString();
    }
  }

  @override
  void dispose() {
    _price.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _decide(bool approve) async {
    if (_busy || _quantity == null) {
      return;
    }
    setState(() => _busy = true);
    try {
      final selectedSite = widget.request.evidence
          .where((row) => row['site_id']?.toString() == _siteId)
          .firstOrNull;
      final selectedPrice = int.tryParse(_price.text.trim());
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(approve ? '請求数量を承認' : '請求数量を却下'),
          content: Text(
            '${widget.request.customerName}\n${widget.request.workDate}  ${widget.request.workerName}\n請求数量：${_quantity!}人工'
            '${approve ? '\n請求現場：${selectedSite?["site_name"] ?? _siteId}\n1人工の単価：${_price.text.trim()}円\n請求額：${(_quantity! * (selectedPrice ?? 0)).round()}円' : ''}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('戻る'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(approve ? '承認する' : '却下する'),
            ),
          ],
        ),
      );
      if (!mounted || confirmed != true) {
        return;
      }
      await widget.repository.decide(
        request: widget.request,
        approve: approve,
        quantity: _quantity!,
        siteId: _siteId,
        unitPriceYen: int.tryParse(_price.text.trim()),
        note: _note.text,
      );
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$error')));
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final request = widget.request;
    final sites = <String, Map<String, dynamic>>{};
    for (final evidence
        in request.status == 'pending'
            ? request.siteOptions
            : request.evidence) {
      final id = evidence['site_id']?.toString();
      if (id != null && id.isNotEmpty) {
        sites[id] = evidence;
      }
    }
    final editable = request.status == 'pending' && !_busy;
    final price = int.tryParse(_price.text.trim());
    return Scaffold(
      appBar: AppBar(title: Text(request.customerName)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            '${request.workDate}  ${request.workerName}',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          for (final evidence in request.evidence)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.location_on_outlined),
              title: Text(evidence['site_name']?.toString() ?? ''),
            ),
          const SizedBox(height: 12),
          const Text('請求数量'),
          SegmentedButton<double>(
            segments: const [
              ButtonSegment(value: 1, label: Text('1人工')),
              ButtonSegment(value: 0.5, label: Text('0.5人工')),
            ],
            selected: _quantity == null ? <double>{} : {_quantity!},
            emptySelectionAllowed: true,
            onSelectionChanged: editable
                ? (values) => setState(() => _quantity = values.firstOrNull)
                : null,
          ),
          const SizedBox(height: 20),
          const Text('請求に使用する現場と単価を選択してください。現場ごとに単価が異なる場合も、自動で決めません。'),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _siteId,
            decoration: const InputDecoration(labelText: '請求に使用する現場'),
            items: [
              for (final entry in sites.entries)
                DropdownMenuItem(
                  value: entry.key,
                  child: Text(
                    entry.value['site_name']?.toString() ?? entry.key,
                  ),
                ),
            ],
            onChanged: editable
                ? (id) => setState(() {
                    _siteId = id;
                    final registeredPrice = sites[id]?['unit_price_yen'];
                    _price.text = registeredPrice is num && registeredPrice > 0
                        ? registeredPrice.toInt().toString()
                        : '';
                  })
                : null,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _price,
            enabled: editable,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: '承認する1人工の単価（円）'),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _note,
            enabled: editable,
            decoration: const InputDecoration(labelText: '確認メモ'),
          ),
          const SizedBox(height: 24),
          if (request.status != 'pending') Text('処理済み：${request.status}'),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: editable && _quantity != null
                      ? () => _decide(false)
                      : null,
                  child: const Text('却下'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed:
                      editable &&
                          _quantity != null &&
                          _siteId != null &&
                          price != null &&
                          price > 0
                      ? () => _decide(true)
                      : null,
                  child: Text(_busy ? '処理中' : '承認'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
