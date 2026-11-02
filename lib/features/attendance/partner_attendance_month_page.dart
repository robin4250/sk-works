import 'dart:async';

import 'package:flutter/material.dart';

import '../../international/language_controller.dart';
import 'worker_attendance_sheet_repository.dart';

/// Receiver-owned partner attendance, read-only. No import or receipt action.
class PartnerAttendanceMonthPage extends StatefulWidget {
  const PartnerAttendanceMonthPage({
    super.key,
    required this.worker,
    required this.initialMonth,
    this.repositoryOverride,
  });
  final PartnerAttendanceWorker worker;
  final DateTime initialMonth;
  final WorkerAttendanceSheetRepository? repositoryOverride;

  @override
  State<PartnerAttendanceMonthPage> createState() =>
      _PartnerAttendanceMonthPageState();
}

class _PartnerAttendanceMonthPageState
    extends State<PartnerAttendanceMonthPage> {
  late final _repository =
      widget.repositoryOverride ??
      WorkerAttendanceSheetRepository.maybeCreate();
  late DateTime _month;
  List<Map<String, dynamic>> _rows = const [];
  String? _siteId;
  bool _error = false;
  bool _loading = true;
  bool _scopeInvalidated = false;
  int _generation = 0;
  StreamSubscription? _auth;
  String _tr(String ja, String en) => SkoLanguageController.isEnglish ? en : ja;

  @override
  void initState() {
    super.initState();
    _month = DateTime(widget.initialMonth.year, widget.initialMonth.month);
    if (_repository == null ||
        !_repository.partnerWorkerIsCurrent(widget.worker)) {
      _scopeInvalidated = true;
      _loading = false;
      return;
    }
    _auth = _repository.partnerAuthChanges.listen((_) {
      if (!mounted) return;
      if (!_repository.partnerWorkerIsCurrent(widget.worker)) {
        _generation++;
        setState(() {
          _rows = const [];
          _loading = false;
          _scopeInvalidated = true;
          _error = true;
        });
      }
    });
    _load();
  }

  @override
  void dispose() {
    _auth?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final generation = ++_generation;
    final month = _month;
    setState(() {
      _rows = const [];
      _loading = true;
      _error = false;
      _siteId = null;
    });
    try {
      final repository = _repository;
      if (repository == null) {
        throw StateError(
          _tr('クラウド接続を確認してください。', 'Check the cloud connection.'),
        );
      }
      final rows = await repository.loadPartnerAttendanceMonth(
        widget.worker,
        month,
      );
      if (!mounted || generation != _generation || month != _month) return;
      setState(() {
        _rows = rows;
        _loading = false;
      });
    } catch (error) {
      if (!mounted || generation != _generation || month != _month) return;
      setState(() {
        _error = true;
        _loading = false;
      });
    }
  }

  void _move(int delta) {
    setState(() {
      _month = DateTime(_month.year, _month.month + delta);
    });
    _load();
  }

  String _destinationKey(Map<String, dynamic> row) => row['site_id'] is String
      ? 'site:${row['site_id']}'
      : 'route:${row['route_assignment_id']}';
  String _destinationLabel(Map<String, dynamic> row) => row['site_id'] is String
      ? (row['sites'] as Map)['name']?.toString() ??
            _tr('現場名を確認してください', 'Check the site name')
      : _tr('ルート勤務（現場指定なし）', 'Route work (no site assigned)');

  @override
  Widget build(BuildContext context) {
    SkoLanguageController.watch(context);
    if (_scopeInvalidated ||
        _repository == null ||
        !_repository.partnerWorkerIsCurrent(widget.worker)) {
      return Scaffold(
        appBar: AppBar(title: Text(_tr('協力会社の出勤表', 'Partner attendance'))),
        body: Center(
          child: Text(
            _tr(
              'ログイン状態が変わりました。開き直してください。',
              'Your sign-in session changed. Reopen this page.',
            ),
          ),
        ),
      );
    }
    final sites = <String, String>{};
    for (final row in _rows) {
      sites[_destinationKey(row)] = _destinationLabel(row);
    }
    final rows = _rows
        .where((row) => _siteId == null || _destinationKey(row) == _siteId)
        .toList();
    final total = rows.fold<double>(
      0,
      (sum, row) => sum + (row['base_man_days'] as num).toDouble(),
    );
    return Scaffold(
      appBar: AppBar(title: Text(_tr('協力会社の出勤表', 'Partner attendance'))),
      body: Column(
        children: [
          ListTile(
            title: Text(widget.worker.name),
            subtitle: Text(
              '${_tr('協力会社', 'Partner company')}: ${widget.worker.partnerName}',
              softWrap: true,
            ),
          ),
          Row(
            children: [
              IconButton(
                onPressed: _loading ? null : () => _move(-1),
                icon: const Icon(Icons.chevron_left),
              ),
              Expanded(
                child: Text(
                  _tr(
                    '${_month.year}年${_month.month}月',
                    '${_month.year}/${_month.month.toString().padLeft(2, '0')}',
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              IconButton(
                onPressed: _loading ? null : () => _move(1),
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
          if (!_loading && !_error) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: DropdownButton<String>(
                isExpanded: true,
                value: _siteId,
                hint: Text(_tr('すべての現場', 'All sites')),
                items: [
                  DropdownMenuItem<String>(
                    value: null,
                    child: Text(_tr('すべての現場', 'All sites')),
                  ),
                  for (final entry in sites.entries)
                    DropdownMenuItem(
                      value: entry.key,
                      child: Text(
                        entry.value,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (value) => setState(() {
                  _siteId = value;
                }),
              ),
            ),
            Text(
              _tr(
                '表示中：${rows.length}件 / 人工合計：$total',
                '${rows.length} records / Total person-days: $total',
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                _tr(
                  '協力会社の登録済み出勤を、月・現場ごとに確認できます。',
                  'Review registered partner attendance by month and site.',
                ),
              ),
            ),
          ],
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _tr(
                            '出勤記録を読み込めませんでした。ログイン状態と会社を確認して再試行してください。',
                            'Attendance records could not be loaded. Check your sign-in and company, then try again.',
                          ),
                        ),
                        TextButton(
                          onPressed: _load,
                          child: Text(_tr('再読み込み', 'Reload')),
                        ),
                      ],
                    ),
                  )
                : rows.isEmpty
                ? Center(
                    child: Text(
                      _tr(
                        'この条件の出勤記録はありません',
                        'No attendance records match these filters.',
                      ),
                    ),
                  )
                : ListView.builder(
                    itemCount: rows.length,
                    itemBuilder: (context, index) {
                      final row = rows[index];
                      return ListTile(
                        key: ValueKey<String>(row['id'] as String),
                        title: Text(
                          '${row['work_date']} / ${_destinationLabel(row)}',
                        ),
                        subtitle: Text(
                          _tr(
                            '人工 ${row['base_man_days']} / 残業 ${row['overtime_hours']}h / 早出 ${row['early_hours']}h / 夜間 ${row['night_hours']}h',
                            'Person-days ${row['base_man_days']} / Overtime ${row['overtime_hours']}h / Early ${row['early_hours']}h / Night ${row['night_hours']}h',
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
