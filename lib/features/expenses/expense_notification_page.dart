import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/supabase_backend.dart';
import 'expense_notification_target.dart';
import '../../international/language_controller.dart';

abstract interface class ExpenseNoticeSource {
  String? get actor;
  Stream<String?> get actorChanges;
  Future<Map<String, dynamic>?> load(String notificationId);
}

class SupabaseExpenseNoticeSource implements ExpenseNoticeSource {
  SupabaseExpenseNoticeSource(this.client);
  final SupabaseClient client;
  @override
  String? get actor => client.auth.currentUser?.id;
  @override
  Stream<String?> get actorChanges =>
      client.auth.onAuthStateChange.map((state) => state.session?.user.id);
  @override
  Future<Map<String, dynamic>?> load(String notificationId) async {
    final raw = await client.rpc(
      'expense_notification_target',
      params: {'p_notification_id': notificationId},
    );
    return raw is Map ? Map<String, dynamic>.from(raw) : null;
  }
}

/// Read-only target. Opening a notification never approves, allocates or pays.
class ExpenseNotificationPage extends StatefulWidget {
  const ExpenseNotificationPage({
    super.key,
    required this.notificationId,
    required this.actionKey,
    required this.actionId,
    this.source,
  });
  final String notificationId, actionKey, actionId;
  final ExpenseNoticeSource? source;
  @override
  State<ExpenseNotificationPage> createState() =>
      _ExpenseNotificationPageState();
}

class _ExpenseNotificationPageState extends State<ExpenseNotificationPage>
    with WidgetsBindingObserver {
  ExpenseNoticeSource? _source;
  StreamSubscription<String?>? _subscription;
  String? _actor;
  Map<String, dynamic>? _claim;
  int _generation = 0;
  bool _active = true, _changed = false, _loading = false;
  bool get _completed => widget.actionKey == 'expense_review_completed';
  String _text(String ja, String en) =>
      SkoLanguageController.isEnglish ? en : ja;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final state = WidgetsBinding.instance.lifecycleState;
    _active = state == null || state == AppLifecycleState.resumed;
    _source =
        widget.source ??
        (SupabaseBackend.isInitialized
            ? SupabaseExpenseNoticeSource(SupabaseBackend.client)
            : null);
    _actor = _source?.actor;
    _subscription = _source?.actorChanges.listen((actor) {
      if (actor != _actor) _invalidate();
    }, onError: (Object _) => _invalidate());
    _load();
  }

  @override
  void didUpdateWidget(covariant ExpenseNotificationPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.notificationId != widget.notificationId ||
        oldWidget.actionId != widget.actionId ||
        oldWidget.actionKey != widget.actionKey ||
        oldWidget.source != widget.source) {
      _invalidate();
    }
  }

  void _invalidate() {
    _changed = true;
    _generation++;
    if (mounted) {
      setState(() {
        _claim = null;
        _loading = false;
      });
    }
  }

  bool get _available =>
      mounted &&
      _active &&
      !_changed &&
      _actor != null &&
      _source?.actor == _actor;
  bool _current(int generation) => _available && generation == _generation;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _active = state == AppLifecycleState.resumed;
    _generation++;
    if (_source?.actor != _actor) _invalidate();
    if (!_active) {
      if (mounted) {
        setState(() {
          _claim = null;
          _loading = false;
        });
      }
    } else if (!_changed) {
      _load();
    }
  }

  Future<void> _load() async {
    final generation = ++_generation;
    if (_source?.actor != _actor) _invalidate();
    if (!_available) return;
    setState(() {
      _claim = null;
      _loading = true;
    });
    try {
      if (!isExpenseNoticeUuid(widget.notificationId) ||
          !isExpenseNoticeUuid(widget.actionId) ||
          ![
            'expense_review_request',
            'expense_review_completed',
          ].contains(widget.actionKey)) {
        throw const FormatException('Invalid target');
      }
      final value = await _source!.load(widget.notificationId);
      if (_source?.actor != _actor) _invalidate();
      if (!_current(generation)) return;
      final claim = parseExpenseNotificationTarget(
        value,
        notificationId: widget.notificationId,
        actionKey: widget.actionKey,
        actionId: widget.actionId,
      );
      setState(() {
        _claim = claim;
        _loading = false;
      });
    } catch (_) {
      if (_source?.actor != _actor) _invalidate();
      if (_current(generation)) {
        setState(() {
          _claim = null;
          _loading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _generation++;
    WidgetsBinding.instance.removeObserver(this);
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    SkoLanguageController.watch(context);
    final claim = _available ? _claim : null;
    final status = switch (claim?['approval']) {
      'pending' => _text('承認待ち', 'Pending'),
      'approved' => _text('承認済み', 'Approved'),
      'rejected' => _text('却下済み', 'Rejected'),
      _ => '',
    };
    final method = switch (claim?['settlement_method']) {
      'payroll' => _text('給与精算', 'Payroll settlement'),
      'cash' => _text('現金精算', 'Cash settlement'),
      'paid' => _text('支払済み', 'Already paid'),
      'advance' => _text('立替精算（過去の設定）', 'Advance settlement (historical)'),
      _ => _text('未設定', 'Not set'),
    };
    final category = switch (claim?['allocation']) {
      'ownCompany' => _text('自社', 'Own company'),
      'subcontractor' => _text('下請け会社', 'Subcontractor'),
      'customer' => _text('取引会社', 'Customer'),
      'other' => _text('その他', 'Other'),
      _ => _text('未振り分け', 'Unallocated'),
    };
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _completed
              ? _text('振り分け完了', 'Allocation completed')
              : _text('経費申請', 'Expense application'),
        ),
      ),
      body: _loading && _available
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (claim == null)
                  Text(
                    _text(
                      '対象の経費申請を表示できません。通知一覧から開き直してください。',
                      'This expense is unavailable. Open it again from notifications.',
                    ),
                  )
                else ...[
                  Text(
                    _completed
                        ? _text(
                            '通知作成時の確定内容です。現在の状態は経費一覧で確認してください。',
                            'This is the confirmed result at the time of notification. Check Expenses for its current state.',
                          )
                        : _text(
                            '現在の申請内容です。承認・振り分けは経費一覧で行ってください。',
                            'This is the current application. Review and allocate it from Expenses.',
                          ),
                  ),
                  const SizedBox(height: 16),
                  Text(claim['applicant_name'] as String),
                  Text(
                    '${claim['amount_yen']}円',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  Text('${_text('利用日', 'Date')}: ${claim['incurred_on']}'),
                  Text(claim['description'] as String),
                  const Divider(),
                  Text('${_text('承認', 'Approval')}: $status'),
                  Text('${_text('負担先', 'Allocation')}: $category'),
                  if (claim['counterparty_name'] is String &&
                      (claim['counterparty_name'] as String).trim().isNotEmpty)
                    Text(claim['counterparty_name'] as String),
                  Text('${_text('精算方法', 'Settlement')}: $method'),
                if (_completed && ['payroll', 'cash'].contains(claim['settlement_method']))
                  Text(_text('精算方法の確定通知です。給与への反映や現金の支払完了は別に確認してください。',
                      'This confirms the settlement method. Check payroll inclusion or cash payment separately.')),
                  if (claim['settlement_method'] != null)
                    Text(
                      '${_text('精算対象月', 'Settlement month')}: ${claim['settlement_month']}',
                    ),
                  if (claim['review_memo'] is String &&
                      (claim['review_memo'] as String).trim().isNotEmpty)
                    Text('${_text('メモ', 'Memo')}: ${claim['review_memo']}'),
                ],
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: _available && !_loading ? _load : null,
                  icon: const Icon(Icons.refresh),
                  label: Text(_text('再読み込み', 'Reload')),
                ),
              ],
            ),
    );
  }
}
