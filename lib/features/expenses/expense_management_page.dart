import 'package:flutter/material.dart';
import 'expense_claim.dart';
import 'expense_surface_card.dart';
import 'expense_claims_page.dart';
import 'expense_management_repository.dart';
import 'expense_settlement_choice.dart';
import 'expense_settlement_dialog.dart';
import 'expense_review_flow_dialog.dart';
import 'expense_review_detail_page.dart';
import 'expense_review_history_dialog.dart';
import 'expense_edit_dialog.dart';
import 'expense_submission_repository.dart';
import 'expense_manager_removal_repository.dart';
import 'expense_manager_removal_dialog.dart';

class ExpenseManagementPage extends StatefulWidget {
  const ExpenseManagementPage({super.key, this.access, this.removals});
  final ExpenseManagementAccess? access;
  final ExpenseManagerRemovalRepository? removals;
  @override
  State<ExpenseManagementPage> createState() => _ExpenseManagementPageState();
}

class _ExpenseManagementPageState extends State<ExpenseManagementPage> {
  late final ExpenseManagementAccess _access =
      widget.access ?? ExpenseManagementRepository();
  late final ExpenseManagerRemovalRepository _removals = widget.removals ?? ExpenseManagerRemovalRepository();
  ExpenseRemovalCommand? _removalPending;
  List<Map<String, dynamic>> _companies = [];
  String? _company, _actor, _error;
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  ExpenseReviewWorkspace? _data;
  ExpenseReviewCommand? _pending;
  bool _busy = true;
  int _generation = 0;
  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _generation++;
    super.dispose();
  }

  bool _current(int g) =>
      mounted && g == _generation && _access.actor == _actor;
  Future<void> _start() async {
    final g = ++_generation;
    setState(() {
      _busy = true;
      _data = null;
      _error = null;
    });
    try {
      _actor = _access.actor;
      if (_actor == null) throw StateError('ログインが必要です。');
      final companies = await _access.companies();
      if (!_current(g)) return;
      _companies = companies;
      if (!_companies.any((c) => c['company_id'] == _company)) {
        _company = companies.length == 1
            ? companies.single['company_id']
            : null;
      }
      if (_company != null) await _read(g);
    } catch (_) {
      if (mounted && g == _generation) _error = '経費一覧を取得できません。再読み込みしてください。';
    } finally {
      if (mounted && g == _generation) setState(() => _busy = false);
    }
  }

  Future<void> _read(int g) async {
    final pending = await _access.pending(_company!);
    if (!_current(g)) return;
    _pending = pending;
    _removalPending = _removals.actor != _actor ? null : await _removals.pending(_company!);
    if (!_current(g)) return;
    final data = await _access.load(_company!, _month);
    if (!_current(g)) return;
    _data = data;
  }

  Future<void> _reload() async {
    if (_busy || _company == null) return;
    final g = ++_generation;
    setState(() {
      _busy = true;
      _data = null;
      _error = null;
    });
    try {
      await _read(g);
    } catch (_) {
      if (mounted && g == _generation) _error = '経費一覧を取得できません。再読み込みしてください。';
    } finally {
      if (mounted && g == _generation) setState(() => _busy = false);
    }
  }

  Future<void> _act(
    ExpenseClaim claim,
    String action, [
    ExpenseAllocation? destination,
  ]) async {
    if (_busy || _pending != null || _removalPending != null || _data == null || _access.actor != _actor) {
      return;
    }
    final generation = _generation;
    final actor = _actor;
    final company = _company;
    final revision = _data!.revisions[claim.id]!;
    if (_data!.reviewFlowEnabled && _data!.canSettle && ['approve', 'reject'].contains(action)) {
      final decision = await showDialog<ExpenseReviewDecision>(context: context,
        builder: (_) => ExpenseReviewFlowDialog(claim: claim, destinations: _data!.destinations, initialApprove: action != 'reject'));
      if (decision == null || !_current(generation) || actor != _actor || company != _company ||
          _pending != null || _busy || _data?.revisions[claim.id] != revision) {
        return;
      }
      await _execute(ExpenseReviewCommand.create(_actor!, _company!, claim.id, revision,
        decision.approve ? 'approve' : 'reject', decision.destination,
        settlement: decision.settlement, confirmReview: true, memo: decision.memo));
      if (mounted && !_busy && _pending == null && _error == null) {
        final matches = _data?.claims.entries.where((c) => c.id == claim.id).toList();
        if (matches != null && matches.length == 1) await _openDetail(matches.single);
      }
      return;
    }
    ExpenseSettlementChoice? choice;
    if (action == 'approve' && _data!.settlementChoiceEnabled && _data!.canSettle) {
      choice = await showDialog<ExpenseSettlementChoice>(context: context,
        builder: (_) => ExpenseSettlementDialog(claim: claim));
      if (choice == null || !_current(generation) || actor != _actor || company != _company ||
          _pending != null || _busy || _data?.revisions[claim.id] != revision) {
        return;
      }
    }
    // The legacy settlement RPC supports cash/payroll only. Do not persist a
    // command it cannot accept or silently switch it to another method.
    if (choice?.method == ExpenseSettlementMethod.paid) {
      setState(() => _error = '支払済みの設定には承認・振り分け機能の更新が必要です。管理者へ確認してください。');
      return;
    }
    final command = ExpenseReviewCommand.create(
      _actor!,
      _company!,
      claim.id,
      revision,
      action,
      destination,
      settlement: choice,
      costRecoveryOptIn: action == 'allocate' && _data!.costAllocationEnabled,
    );
    await _execute(command);
  }

  bool _canRemove(ExpenseClaim claim) {
    final data=_data;
    return !_busy && _pending==null && _removalPending==null && data!=null &&
      _removals.actor==_actor && ExpenseRemovalCapability(data.removalData,_removals.session).enabled &&
      data.claims.entries.any((current)=>current.id==claim.id && current.revision==claim.revision && !current.managerDeleted && !current.withdrawn) && data.canDecide(claim,_actor!);
  }
  Future<void> _remove(ExpenseClaim claim)async{
    if(!_canRemove(claim))return;
    final g=_generation;final company=_company;final session=_removals.session;
    final reason=await showDialog<String>(context:context,builder:(_)=>ExpenseManagerRemovalDialog(claim:claim));
    if(reason==null || !_current(g) || company!=_company || session!=_removals.session || !_canRemove(claim))return;
    final command=ExpenseRemovalCommand.create(_actor!,company!,claim.id,claim.revision,session!,reason);
    final generation=++_generation;
    setState((){_busy=true;_error=null;});
    try{
      final result=await _removals.submit(command,ExpenseRemovalCapability(_data!.removalData,session));
      if(_current(generation))_error=result.correctionRequired?'削除を記録しました。確定済み原本の金額訂正は別途必要です。':'削除と申請者への通知を記録しました。通知の配信・閲覧は別途確認してください。';
    }catch(_){if(_current(generation))_error='削除結果は未確認です。「削除結果を照会」で確認してください。再送は行いません。';}
    finally{if(_current(generation)){try{await _read(generation);}catch(_){_data=null;}if(_current(generation))setState(()=>_busy=false);}}
  }
  Future<void> _observeRemoval()async{
    final command=_removalPending;if(_busy || command==null)return;
    final g=++_generation;setState((){_busy=true;_error=null;});
    try{final result=await _removals.observe(command);
      if(_current(g))_error=result==null?'保存結果は未確認です。再送せず管理者へ確認してください。':result.correctionRequired?'削除記録を確認しました。確定済み原本の訂正は別途必要です。':'削除と通知の保存結果を確認しました。';
    }catch(_){if(_current(g))_error='削除結果を照会できません。保留を維持しています。';}
    finally{if(_current(g)){try{await _read(g);}catch(_){_data=null;}if(_current(g))setState(()=>_busy=false);}}
  }

  Future<void> _openDetail(ExpenseClaim claim) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (detailContext) => ExpenseReviewDetailPage(
      claim: claim,
      onDelete: _canRemove(claim) ? () => _remove(claim) : null,
      onEdit: claim.managerDeleted || _removalPending!=null || _data?.canSettle != true || _access is! ExpenseManagementRepository ? null : () async {
        final generation = _generation;
        final edit = await showDialog<ExpenseSubmission>(context: detailContext,
          builder: (_) => ExpenseEditDialog(claim: claim, actor: _actor!));
        if (edit == null || !_current(generation) || _busy || _pending != null) return;
        await _execute(ExpenseReviewCommand.create(_actor!, _company!, claim.id, claim.revision, 'edit', null,
          confirmReview: true, memo: '', edit: edit));
        if (detailContext.mounted && _pending == null && _error == null) Navigator.pop(detailContext);
      },
      onHistory: _access is! ExpenseManagementRepository ? null : () async {
        try {
          final value = await _access.reviewHistory(claim);
          if (!detailContext.mounted) return;
          await showDialog<void>(context: detailContext, builder: (_) => ExpenseReviewHistoryDialog(
            events: (value['events'] as List).map((e) => Map<String, dynamic>.from(e)).toList()));
        } catch (_) {
          if (detailContext.mounted) ScaffoldMessenger.of(detailContext).showSnackBar(const SnackBar(content: Text('履歴を取得できません。再度確認してください。')));
        }
      },
    )));
  }

  Future<void> _execute(ExpenseReviewCommand command) async {
    if (_busy || _removalPending!=null || _access.actor != _actor) return;
    final g = ++_generation;
    setState(() {
      _busy = true;
      _pending = command;
      _error = null;
    });
    try {
      await _access.execute(command);
      if (_current(g)) _pending = null;
    } catch (_) {
      if (_current(g)) _error = '更新結果を確認してください。保留操作があれば同じ操作を再確認できます。';
    } finally {
      if (_current(g)) {
        _data = null;
        try {
          await _read(g);
        } catch (_) {
          if (_current(g)) _error = '最新の一覧を確認できません。再読み込みしてください。';
        }
      }
      if (mounted && g == _generation) setState(() => _busy = false);
    }
  }

  Future<void> _settings() async {
    final data = _data;
    if (_busy || data == null || !data.canConfigure || _pending != null || _removalPending!=null) return;
    final actor = _actor, company = _company;
    final selected = data.approvers.toSet();
    final result = await showDialog<List<String>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialog) => AlertDialog(
          title: const Text('経費の承認担当'),
          content: SizedBox(
            width: 360,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('経費ページだけの担当です。1〜3名を選択してください。'),
                  for (final c in data.candidates)
                    CheckboxListTile(
                      title: Text(c['name']),
                      value: selected.contains(c['user_id']),
                      onChanged: (v) => setDialog(() {
                        if (v == true) {
                          selected.add(c['user_id']);
                        } else {
                          selected.remove(c['user_id']);
                        }
                      }),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('キャンセル'),
            ),
            FilledButton(
              onPressed: selected.isEmpty || selected.length > 3
                  ? null
                  : () => Navigator.pop(context, selected.toList()),
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
    if (!mounted ||
        result == null ||
        _access.actor != actor ||
        _company != company) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _access.configure(company!, result, data.settingsRevision);
    } catch (_) {
      if (mounted) _error = '担当設定の保存結果を再読み込みで確認してください。';
    }
    if (!mounted) return;
    final g = ++_generation;
    _data = null;
    try {
      await _read(g);
    } catch (_) {
      if (_current(g)) _error = '担当設定を取得できません。再読み込みしてください。';
    }
    if (mounted) setState(() => _busy = false);
  }

  Widget _header() => Padding(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
    child: ExpenseSurfaceCard(child: Column(
    children: [
      if (_companies.length > 1)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: DropdownButtonFormField<String>(
            initialValue: _company,
            decoration: const InputDecoration(labelText: '会社'),
            items: [
              for (final c in _companies)
                DropdownMenuItem(
                  value: c['company_id'] as String,
                  child: Text(c['company_name']),
                ),
            ],
            onChanged: _busy
                ? null
                : (v) {
                    setState(() {
                      _company = v;
                      _pending = null;
                      _data = null;
                    });
                    _reload();
                  },
          ),
        ),
      Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            tooltip: '前月',
            onPressed: _busy
                ? null
                : () {
                    _month = DateTime(_month.year, _month.month - 1);
                    _reload();
                  },
            icon: const Icon(Icons.chevron_left),
          ),
          Expanded(
            child: Text(
              '${_month.year}年${_month.month}月（利用月）',
              textAlign: TextAlign.center,
            ),
          ),
          IconButton(
            tooltip: '翌月',
            onPressed: _busy
                ? null
                : () {
                    _month = DateTime(_month.year, _month.month + 1);
                    _reload();
                  },
            icon: const Icon(Icons.chevron_right),
          ),
          IconButton(
            tooltip: '再読み込み',
            onPressed: _busy ? null : (_company == null ? _start : _reload),
            icon: const Icon(Icons.refresh),
          ),
          if (_data?.canConfigure == true)
            IconButton(
              tooltip: '経費の承認担当',
              onPressed: _busy || _pending != null ? null : _settings,
              icon: const Icon(Icons.manage_accounts),
            ),
        ],
      ),
      if (_removalPending != null) ListTile(
        title: const Text('削除結果の確認が必要です'),
        subtitle: const Text('同じ本人・会社の現在の権限で保存結果だけを照会します。再送しません。'),
        trailing: TextButton(onPressed:_busy?null:_observeRemoval,child:const Text('削除結果を照会'))),
      if (_pending != null)
        ListTile(
          title: const Text('結果確認待ちの操作があります'),
          subtitle: const Text('別の変更を行う前に、同じ操作の結果を確認してください。'),
          trailing: TextButton(
            onPressed: _busy || _removalPending!=null ? null : () => _execute(_pending!),
            child: const Text('同じ操作を再確認'),
          ),
        ),
      if (_error != null)
        Padding(padding: const EdgeInsets.all(12), child: Text(_error!)),
      if (_busy) const LinearProgressIndicator(),
    ],
  )),
  );
  @override
  Widget build(BuildContext context) {
    if (_actor != null && _access.actor != _actor) {
      return Scaffold(
        backgroundColor: const Color(0xfff5f7fa),
        appBar: AppBar(
          toolbarHeight: kToolbarHeight,
          title: const Text('経費申請一覧'),
        ),
        body: const Center(child: Text('ログイン情報が変わりました。画面を開き直してください。')),
      );
    }
    final data = _data;
    if (data == null) {
      return Scaffold(
        backgroundColor: const Color(0xfff5f7fa),
        appBar: AppBar(
          toolbarHeight: kToolbarHeight,
          title: const Text('経費申請一覧'),
        ),
        body: ListView(
          children: [
            _header(),
            if (!_busy && _error == null)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  _companies.isEmpty
                      ? '経費の管理者・承認担当として利用できる会社はありません。'
                      : '会社を選択してください。',
                ),
              ),
          ],
        ),
      );
    }
    final enabled = !_busy && _pending == null && _removalPending==null && data.canReview;
    return ExpenseClaimsPage(
      claims: data.claims,
      header: _header(),
      canDecide: (c) => data.canDecide(c, _actor!),
      onApprove: enabled ? (c) => _act(c, 'approve') : null,
      allowSettlementSetup: data.settlementChoiceEnabled && data.canSettle,
      costAllocationEnabled: data.costAllocationEnabled,
      reviewFlowEnabled: data.reviewFlowEnabled && data.canSettle,
      onOpenDetail: data.reviewFlowEnabled ? (c) => _openDetail(c) : null,
      onDelete: ExpenseRemovalCapability(data.removalData,_removals.session).enabled ? (c) => _remove(c) : null,
      onReject: enabled ? (c) => _act(c, 'reject') : null,
      onAllocate: enabled && (!data.costAllocationEnabled || data.canSettle)
          ? (c, d) => _act(c, 'allocate', d) : null,
      destinations: data.destinations,
    );
  }
}

