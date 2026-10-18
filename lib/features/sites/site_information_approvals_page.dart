import 'package:flutter/material.dart';

import '../../international/language_controller.dart';
import '../notifications/notification_request_selection.dart';
import 'site_cloud_repository.dart';

class SiteInformationApprovalsPage extends StatefulWidget {
  const SiteInformationApprovalsPage({
    super.key,
    this.initialRequestId,
    this.loadRequests,
  });

  final String? initialRequestId;
  @visibleForTesting
  final Future<List<Map<String, dynamic>>> Function()? loadRequests;

  @override
  State<SiteInformationApprovalsPage> createState() =>
      _SiteInformationApprovalsPageState();
}

class _SiteInformationApprovalsPageState
    extends State<SiteInformationApprovalsPage> {
  final _repository = SiteCloudRepository.maybeCreate();

  List<Map<String, dynamic>> _items = const [];
  bool _loading = true;
  String? _error;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant SiteInformationApprovalsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialRequestId != widget.initialRequestId ||
        oldWidget.loadRequests != widget.loadRequests) {
      _load();
    }
  }

  @override
  void dispose() {
    _generation++;
    super.dispose();
  }

  Future<void> _load() async {
    final generation = ++_generation;
    final requestId = widget.initialRequestId;
    setState(() {
      _items = const [];
      _loading = true;
      _error = null;
    });
    try {
      final loader = widget.loadRequests ?? _repository?.loadInformationRequests;
      if (loader == null) {
        throw StateError('現場変更の承認画面を利用できません。');
      }
      final items = await loader();
      if (!mounted || generation != _generation) return;
      final visible = selectNotificationRequestRows<Map<String, dynamic>>(
        items,
        requestId: requestId,
        id: (item) => item['id']?.toString() ?? '',
        includeInInbox: (item) => item['status'] == 'pending',
      );
      setState(() {
        _items = List<Map<String, dynamic>>.unmodifiable(visible);
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

  Future<void> _review(Map<String, dynamic> item, bool approve) async {
    final repository = _repository;
    final generation = _generation;
    if (!_items.contains(item)) return;
    if (repository == null) return;
    final id = item['id']?.toString() ?? '';
    if (id.isEmpty) return;

    String reason = '';
    if (!approve) {
      final controller = TextEditingController();
      final value = await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('現場変更申請を差し戻しますか？'),
          content: TextField(
            controller: controller,
            autofocus: true,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: '差し戻し理由',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('戻る'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(
                dialogContext,
                controller.text.trim(),
              ),
              child: const Text('差し戻す'),
            ),
          ],
        ),
      );
      controller.dispose();
      if (value == null || value.isEmpty) return;
      reason = value;
    } else {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('現場変更申請を承認しますか？'),
          content: const Text('承認すると申請内容が現場データへ反映されます。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('戻る'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('承認する'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }

    if (!mounted || generation != _generation || !_items.contains(item)) return;

    try {
      await repository.reviewInformationRequest(
        requestId: id,
        approve: approve,
        reason: reason,
      );
      if (!mounted || generation != _generation) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(approve ? '現場変更を承認しました' : '現場変更を差し戻しました')),
      );
      await _load();
    } catch (error) {
      if (!mounted || generation != _generation) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('処理できませんでした: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          '現場データの承認待ち',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        actions: [
          IconButton(
            tooltip: '更新',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
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
                    ? Center(child: Text(widget.initialRequestId == null
                        ? '承認待ちの現場変更申請はありません'
                        : SkoLanguageController.tr('対象の申請は完了済み、または閲覧できません。')))
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: ListView.separated(
                          padding: const EdgeInsets.all(12),
                          itemCount: _items.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final item = _items[index];
                            final before = item['before_values'] is Map
                                ? Map<String, dynamic>.from(
                                    item['before_values'] as Map,
                                  )
                                : const <String, dynamic>{};
                            final proposed = item['proposed_values'] is Map
                                ? Map<String, dynamic>.from(
                                    item['proposed_values'] as Map,
                                  )
                                : const <String, dynamic>{};
                            final status = item['status']?.toString() ?? 'pending';
                            final canReview =
                                item['can_review'] == true && status == 'pending';
                            return Card(
                              child: Padding(
                                padding: const EdgeInsets.all(14),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Text(
                                      item['site_name']?.toString() ?? '現場',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w900,
                                        fontSize: 16,
                                      ),
                                    ),
                                    if (status != 'pending') ...[
                                      const SizedBox(height: 6),
                                      Align(
                                        alignment: Alignment.centerLeft,
                                        child: Chip(
                                          label: Text(
                                            status == 'approved'
                                                ? '承認済み'
                                                : status == 'rejected'
                                                    ? '差し戻し済み'
                                                    : status,
                                          ),
                                        ),
                                      ),
                                    ],
                                    const SizedBox(height: 8),
                                    for (final entry in proposed.entries)
                                      Padding(
                                        padding:
                                            const EdgeInsets.only(bottom: 6),
                                        child: Text(
                                          '${_label(entry.key)}：'
                                          '${_value(before[entry.key])} → ${_value(entry.value)}',
                                        ),
                                      ),
                                    if (canReview) ...[
                                      const SizedBox(height: 10),
                                      Row(
                                        children: [
                                          Expanded(
                                            child: OutlinedButton.icon(
                                              onPressed: () =>
                                                  _review(item, false),
                                              icon: const Icon(Icons.undo),
                                              label: const Text('差し戻し'),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: FilledButton.icon(
                                              onPressed: () =>
                                                  _review(item, true),
                                              icon: const Icon(
                                                Icons.check_circle_outline,
                                              ),
                                              label: const Text('承認'),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
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

  String _label(String key) => switch (key) {
        'name' => '現場名',
        'formal_name' => '現場正式名称',
        'address' => '住所',
        'nearest_station' => '最寄駅',
        'representative_name' => '現場責任者',
        'representative_phone' => '責任者電話番号',
        'notes' => '備考',
        'status' => '状態',
        _ => key,
      };

  String _value(Object? value) {
    final text = value?.toString().trim() ?? '';
    if (text.isEmpty) return '未設定';
    if (text == 'completed') return '完了';
    return text;
  }
}
