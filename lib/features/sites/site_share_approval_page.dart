import 'package:flutter/material.dart';

import '../../international/language_controller.dart';
import '../notifications/notification_request_selection.dart';
import 'site_cloud_repository.dart';

class SiteShareApprovalPage extends StatefulWidget {
  const SiteShareApprovalPage({
    super.key,
    this.initialRequestId,
    this.loadInbox,
    this.respond,
  });

  final String? initialRequestId;

  @visibleForTesting
  final Future<List<Map<String, dynamic>>> Function()? loadInbox;
  @visibleForTesting
  final Future<String?> Function({
    required String dataItemId,
    required bool accept,
  })?
  respond;

  @override
  State<SiteShareApprovalPage> createState() => _SiteShareApprovalPageState();
}

class _SiteShareApprovalPageState extends State<SiteShareApprovalPage> {
  final _repository = SiteCloudRepository.maybeCreate();

  List<Map<String, dynamic>> _items = const [];
  bool _loading = true;
  String? _error;
  int _generation = 0;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant SiteShareApprovalPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialRequestId != widget.initialRequestId) _load();
  }

  Future<void> _load() async {
    final generation = ++_generation;
    final load = widget.loadInbox ?? _repository?.loadSiteShareInbox;
    setState(() {
      _items = const [];
      _loading = true;
      _error = null;
    });
    if (load == null) {
      setState(() {
        _loading = false;
        _error = '現場共有の承認画面を利用できません。';
      });
      return;
    }
    try {
      final inbox = await load();
      if (!mounted || generation != _generation) return;
      final items = selectNotificationRequestRows<Map<String, dynamic>>(
        inbox,
        requestId: widget.initialRequestId,
        id: (item) => item['data_item_id']?.toString() ?? '',
      );
      setState(() {
        _items = items;
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _respond(Map<String, dynamic> item, bool accept) async {
    final respond = widget.respond ?? _repository?.respondSiteShare;
    final generation = _generation;
    if (_busy ||
        respond == null ||
        item['status'] != 'pending' ||
        !_items.contains(item)) {
      return;
    }
    final id = item['data_item_id']?.toString() ?? '';
    if (id.isEmpty) return;

    final payload = item['payload'] is Map
        ? Map<String, dynamic>.from(item['payload'] as Map)
        : const <String, dynamic>{};
    final name = payload['name']?.toString() ?? '現場';

    setState(() => _busy = true);
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(accept ? '現場データを承認しますか？' : '現場データを拒否しますか？'),
          content: Text(
            accept ? '「$name」を自社の現場データへ追加します。' : '「$name」は自社の現場データへ追加されません。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('戻る'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(accept ? '承認して追加' : '拒否する'),
            ),
          ],
        ),
      );
      if (confirmed != true ||
          !mounted ||
          generation != _generation ||
          !_items.contains(item)) {
        return;
      }

      await respond(dataItemId: id, accept: accept);
      if (!mounted || generation != _generation) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(accept ? '現場データを追加しました' : '現場データを拒否しました')),
      );
      await _load();
    } catch (error) {
      if (!mounted || generation != _generation) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('処理できませんでした: $error')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    SkoLanguageController.watch(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          '現場データ承認',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(_error!, textAlign: TextAlign.center),
                          const SizedBox(height: 12),
                          FilledButton(
                            onPressed: _load,
                            child: const Text('再読み込み'),
                          ),
                        ],
                      ),
                    ),
                  )
                : _items.isEmpty
                    ? Center(child: Text(SkoLanguageController.tr(
                        widget.initialRequestId == null
                          ? '承認待ちの現場データはありません'
                          : '対象の現場共有は完了済み、または閲覧できません。')))
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: ListView.separated(
                          padding: const EdgeInsets.all(12),
                          itemCount: _items.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final item = _items[index];
                            final payload = item['payload'] is Map
                                ? Map<String, dynamic>.from(
                                    item['payload'] as Map,
                                  )
                                : const <String, dynamic>{};
                            final sender =
                                item['sender_company_name']?.toString() ??
                                    '会社';
                            return Card(
                              child: Padding(
                                padding: const EdgeInsets.all(14),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Text(
                                      '$sender から現場データ',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      payload['name']?.toString() ?? '現場',
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium
                                          ?.copyWith(
                                            fontWeight: FontWeight.w900,
                                          ),
                                    ),
                                    if ((payload['customer_name']
                                                ?.toString()
                                                .trim()
                                                .isNotEmpty ??
                                            false))
                                      Text(
                                        '取引先: ${payload['customer_name']}',
                                      ),
                                    if ((payload['address']
                                                ?.toString()
                                                .trim()
                                                .isNotEmpty ??
                                            false))
                                      Text('住所: ${payload['address']}'),
                                    if ((payload['nearest_station']
                                                ?.toString()
                                                .trim()
                                                .isNotEmpty ??
                                            false))
                                      Text(
                                        '最寄駅: ${payload['nearest_station']}',
                                      ),
                                    const SizedBox(height: 12),
                                    if (item['status'] == 'pending') Row(
                                      children: [
                                        Expanded(
                                          child: OutlinedButton.icon(
                                            onPressed: _busy ? null : () =>
                                                _respond(item, false),
                                            icon: const Icon(Icons.close),
                                            label: const Text('拒否'),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: FilledButton.icon(
                                            onPressed: _busy ? null : () =>
                                                _respond(item, true),
                                            icon: const Icon(
                                              Icons.check_circle_outline,
                                            ),
                                            label: const Text('承認して追加'),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
      ),
    );
  }
}
