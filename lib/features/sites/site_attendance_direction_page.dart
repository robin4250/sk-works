import 'package:flutter/material.dart';

import '../shared/standalone_trade_document_page.dart';
import 'site_cloud_repository.dart';

class SiteAttendanceDirectionPage extends StatefulWidget {
  const SiteAttendanceDirectionPage({
    super.key,
    required this.siteId,
    required this.siteName,
    required this.siteAddress,
    required this.repository,
  });

  final String siteId;
  final String siteName;
  final String siteAddress;
  final SiteCloudRepository repository;

  @override
  State<SiteAttendanceDirectionPage> createState() =>
      _SiteAttendanceDirectionPageState();
}

class _SiteAttendanceDirectionPageState
    extends State<SiteAttendanceDirectionPage> {
  late final String? _sessionToken;
  List<Map<String, dynamic>> _rows = const [];
  final _selectedDirections = <String, String>{};
  bool _busy = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _sessionToken = widget.repository.attendanceDirectionSession;
    _refresh();
  }

  String _role(Object? direction) => switch (direction) {
    'send' => '取引会社（自社の出勤を送る）',
    'receive' => '協力会社（相手の出勤を受け取る）',
    _ => '未設定',
  };

  Future<void> _refresh({String? action, Map<String, dynamic>? row}) async {
    try {
      final token = _sessionToken;
      if (token == null) throw StateError('SKOへのログインが必要です。');
      final rows = await widget.repository.attendanceDirectionWorkspace(
        siteId: widget.siteId,
        sessionToken: token,
        itemId: row?['item_id'] as String?,
        action: action,
        requestId: row?['request_id'] as String?,
      );
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = '出勤共有の設定を確認できませんでした。\n$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submit(String action, Map<String, dynamic> row) async {
    if (_busy) return;
    setState(() => _busy = true);
    await _refresh(action: action, row: row);
  }

  Widget _companyCard(Map<String, dynamic> row) {
    final pending = row['request_id'] != null;
    final sitePending = row['site_share_status'] == 'pending';
    final outgoing = row['requested_by_us'] == true;
    final allowed = [
      if (row['can_send'] == true && row['direction'] != 'send') 'send',
      if (row['can_receive'] == true && row['direction'] != 'receive')
        'receive',
    ];
    final itemId = row['item_id'] as String;
    final defaultDirection = switch (row['default_role']) {
      'customer' => 'send',
      'subcontractor' => 'receive',
      _ => null,
    };
    final proposed =
        _selectedDirections[itemId] ??
        (row['direction'] == null ? defaultDirection : null);
    final selected = allowed.contains(proposed) ? proposed : null;
    final tradeCompanyId = row['trade_company_id'] as String?;
    final canOpenDocument =
        tradeCompanyId != null &&
        ((row['direction'] == 'send' && row['can_send'] == true) ||
            (row['direction'] == 'receive' && row['can_receive'] == true));

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              [
                row['company_name'],
                row['other_site'],
              ].whereType<String>().join(' · '),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text('承認済みの方向　${_role(row['direction'])}'),
            if (sitePending) const Text('現場共有の承認待ち'),
            if (pending) ...[
              Text(
                '${outgoing ? '相手の承認待ち' : '相手からの申請'}　'
                '${_role(row['requested_direction'])}',
              ),
              Wrap(
                spacing: 8,
                children: [
                  if (outgoing)
                    TextButton(
                      onPressed: _busy ? null : () => _submit('cancel', row),
                      child: const Text('申請を取り消す'),
                    )
                  else ...[
                    FilledButton(
                      onPressed: _busy ? null : () => _submit('approve', row),
                      child: const Text('承認'),
                    ),
                    TextButton(
                      onPressed: _busy ? null : () => _submit('reject', row),
                      child: const Text('却下'),
                    ),
                  ],
                ],
              ),
            ] else if (allowed.isNotEmpty) ...[
              DropdownButton<String>(
                value: selected,
                hint: const Text('現場での役割を選ぶ'),
                isExpanded: true,
                items: [
                  for (final direction in allowed)
                    DropdownMenuItem(
                      value: direction,
                      child: Text(_role(direction)),
                    ),
                ],
                onChanged: _busy
                    ? null
                    : (value) {
                        if (value != null) {
                          setState(() => _selectedDirections[itemId] = value);
                        }
                      },
              ),
              OutlinedButton(
                onPressed: _busy || selected == null
                    ? null
                    : () => _submit(selected, row),
                child: const Text('相手に申請する'),
              ),
            ],
            if (canOpenDocument)
              TextButton.icon(
                onPressed: _busy
                    ? null
                    : () {
                        if (widget.repository.attendanceDirectionSession !=
                            _sessionToken) {
                          return;
                        }
                        Navigator.of(context).push<void>(
                          MaterialPageRoute(
                            builder: (_) => StandaloneTradeDocumentPage(
                              tradeCompanyId: tradeCompanyId,
                              acceptance: row['direction'] == 'send',
                              site: (
                                id: widget.siteId,
                                name: widget.siteName,
                                address: widget.siteAddress,
                              ),
                              verifySite: () async {
                                final rows = await widget.repository
                                    .attendanceDirectionWorkspace(
                                      siteId: widget.siteId,
                                      sessionToken: _sessionToken!,
                                    );
                                final direction = row['direction'];
                                if (!rows.any(
                                  (current) =>
                                      current['item_id'] == itemId &&
                                      current['trade_company_id'] ==
                                          tradeCompanyId &&
                                      current['direction'] == direction &&
                                      current[direction == 'send'
                                              ? 'can_send'
                                              : 'can_receive'] ==
                                          true,
                                )) {
                                  throw StateError(
                                    '現場の役割が変わりました。現場詳細から開き直してください。',
                                  );
                                }
                              },
                            ),
                          ),
                        );
                      },
                icon: const Icon(Icons.description_outlined),
                label: Text(row['direction'] == 'send' ? '注文請書生成' : '注文書生成'),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('現場の出勤共有方向'),
        actions: [
          IconButton(
            tooltip: '再読み込み',
            onPressed: _busy
                ? null
                : () {
                    setState(() => _busy = true);
                    _refresh();
                  },
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_busy) const LinearProgressIndicator(),
          if (_error != null) Text(_error!),
          if (!_busy && _error == null && _rows.isEmpty)
            const Text('この現場の共有先がありません。'),
          for (final row in _rows) _companyCard(row),
        ],
      ),
    );
  }
}
