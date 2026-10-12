import 'package:flutter/material.dart';
import 'expense_claim.dart';

enum _ReviewFilter { all, pending, approved, rejected, withdrawn }

/// The host supplies authoritative claims and authorized update callbacks.
/// This page never optimistically approves or reallocates a claim.
class ExpenseClaimsPage extends StatefulWidget {
  const ExpenseClaimsPage({
    super.key,
    required this.claims,
    this.applicantId,
    this.header,
    this.canDecide,
    this.onApprove,
    this.onReject,
    this.onAllocate,
    this.destinations = const [],
    this.allowSettlementSetup = false,
    this.costAllocationEnabled = false,
  });
  final ExpenseClaims claims;
  final String? applicantId;
  final Widget? header;
  final bool Function(ExpenseClaim)? canDecide;
  final Future<void> Function(ExpenseClaim claim)? onApprove;
  final Future<void> Function(ExpenseClaim claim)? onReject;
  final Future<void> Function(
    ExpenseClaim claim,
    ExpenseAllocation destination,
  )?
  onAllocate;
  final List<ExpenseAllocation> destinations;
  final bool allowSettlementSetup;
  final bool costAllocationEnabled;
  @override
  State<ExpenseClaimsPage> createState() => _ExpenseClaimsPageState();
}

class _ExpenseClaimsPageState extends State<ExpenseClaimsPage> {
  ExpenseList _list = ExpenseList.allocation;
  _ReviewFilter _filter = _ReviewFilter.all;
  bool _busy = false;
  String? _error;
  int _generation = 0;
  @override
  void didUpdateWidget(covariant ExpenseClaimsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.claims, widget.claims) ||
        oldWidget.applicantId != widget.applicantId ||
        oldWidget.onApprove != widget.onApprove ||
        oldWidget.onReject != widget.onReject ||
        oldWidget.onAllocate != widget.onAllocate ||
        !identical(oldWidget.destinations, widget.destinations)) {
      _generation++;
      _error = null;
    }
  }

  @override
  void dispose() {
    _generation++;
    super.dispose();
  }

  Future<void> _request(int generation, Future<void> Function() action) async {
    if (_busy || generation != _generation) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() => _error = '更新結果を確認できませんでした。保存先の状態を確認してください。');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _listLabel(ExpenseList list) => switch (list) {
    ExpenseList.allocation => 'すべて',
    ExpenseList.ownCompany => '自社',
    ExpenseList.customer => '取引会社',
    ExpenseList.subcontractor => '下請け会社',
  };

  String _categoryLabel(ExpenseCategory category) => switch (category) {
    ExpenseCategory.unallocated => '承認後に振り分け',
    ExpenseCategory.ownCompany => '自社',
    ExpenseCategory.customer => '取引会社',
    ExpenseCategory.subcontractor => '下請け会社',
  };

  String _filterLabel(_ReviewFilter filter) => switch (filter) {
    _ReviewFilter.all => '全件',
    _ReviewFilter.pending => '承認待ち',
    _ReviewFilter.approved => '承認済み',
    _ReviewFilter.rejected => '却下',
    _ReviewFilter.withdrawn => '取り下げ',
  };

  bool _matches(ExpenseClaim c) => switch (_filter) {
    _ReviewFilter.all => true,
    _ReviewFilter.withdrawn => c.withdrawn,
    _ReviewFilter.pending =>
      !c.withdrawn && c.approval == ExpenseApproval.pending,
    _ReviewFilter.approved =>
      !c.withdrawn && c.approval == ExpenseApproval.approved,
    _ReviewFilter.rejected =>
      !c.withdrawn && c.approval == ExpenseApproval.rejected,
  };

  void _help() => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('経費の承認・振り分け'),
      content: SingleChildScrollView(
        child: Text(
          '1. 利用月と申請者・内容・金額を確認し、担当者が承認または却下します。\n\n'
          '管理者・サブ管理者は承認時に現金精算／給料精算と対象月を選び、「承認して保存」を押します。'
          '承認済みで未設定の申請は「精算方法を設定」から選択します。\n\n'
          '2. 承認済みの申請で「振り分け」を押し、費用の負担先を選びます。'
          '取引会社・下請け会社は、登録済みの会社を選び、確認して保存します。'
          '初回承認時の負担先は自社です。\n\n'
          '3. 「すべて」は全状態の履歴です。負担先と承認状態を組み合わせて絞り込めます。'
          '申請者名を押すと、その人の申請一覧を閲覧できます。\n\n'
          '承認済みの表示金額は経費の合計で、支払済額ではありません。'
          '${widget.costAllocationEnabled ? '取引会社・下請け会社へ確認して振り分けた経費は、利用月の請求書・支払証明書へ原額で別途加算します。税・福利厚生費は加算しません。内訳は2ページ目で確認できます。給料精算の給与支給への接続は準備中です。' : '現在の帳票連携は経費明細の表示です。支給・請求・支払額への追加は準備中です。'}'
          '確定済み帳票は変更しません。\n\n'
          '通信結果が不明なときは、別の操作をせず「同じ操作を再確認」を使ってください。',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('閉じる'),
        ),
      ],
    ),
  );

  Future<void> _allocate(ExpenseClaim claim, int generation) async {
    final action = widget.onAllocate;
    if (_busy ||
        action == null ||
        claim.withdrawn ||
        claim.approval != ExpenseApproval.approved) {
      return;
    }
    final destinations = List<ExpenseAllocation>.unmodifiable(
      widget.destinations,
    );
    ExpenseCategory? category;
    ExpenseAllocation? destination;
    final result = await showDialog<ExpenseAllocation>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialog) {
          final options = destinations
              .where((d) => d.category == category)
              .toList();
          return AlertDialog(
            title: const Text('費用の負担先を選択'),
            content: SizedBox(
              width: 360,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('${claim.applicantName} / ${claim.amountYen}円'),
                    Text(claim.description),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<ExpenseCategory>(
                      decoration: const InputDecoration(labelText: '負担先の区分'),
                      isExpanded: true,
                      items: [
                        for (final c in [
                          ExpenseCategory.ownCompany,
                          ExpenseCategory.customer,
                          ExpenseCategory.subcontractor,
                        ])
                          if (destinations.any((d) => d.category == c))
                            DropdownMenuItem(
                              value: c,
                              child: Text(_categoryLabel(c)),
                            ),
                      ],
                      onChanged: (value) => setDialog(() {
                        category = value;
                        destination = value == ExpenseCategory.ownCompany
                            ? destinations.firstWhere(
                                (d) => d.category == value,
                              )
                            : null;
                      }),
                    ),
                    if (category != null &&
                        category != ExpenseCategory.ownCompany) ...[
                      const SizedBox(height: 12),
                      DropdownButtonFormField<int>(
                        key: ValueKey(category),
                        decoration: const InputDecoration(labelText: '会社名'),
                        isExpanded: true,
                        items: [
                          for (var i = 0; i < options.length; i++)
                            DropdownMenuItem(
                              value: i,
                              child: Text(
                                options[i].counterpartyName ??
                                    options[i].counterpartyId!,
                              ),
                            ),
                        ],
                        onChanged: (value) => setDialog(
                          () => destination = value == null
                              ? null
                              : options[value],
                        ),
                      ),
                    ],
                    if (destination != null) ...[
                      const SizedBox(height: 16),
                      Text(
                        '変更後：${_categoryLabel(destination!.category)}'
                        '${destination!.counterpartyName == null ? '' : ' / ${destination!.counterpartyName}'}',
                      ),
                      Text(switch (destination!.category) {
                        ExpenseCategory.customer => widget.costAllocationEnabled
                            ? '原額を別途加算：取引会社の請求書（税・福利厚生費の対象外）'
                            : '経費明細の表示先：取引会社の請求書',
                        ExpenseCategory.subcontractor => widget.costAllocationEnabled
                            ? '原額を別途加算：下請け会社の支払証明書（税・福利厚生費の対象外）'
                            : '経費明細の表示先：下請け会社の支払証明書',
                        _ => '自社が負担する経費として管理します。',
                      }),
                    ],
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
                onPressed: destination == null
                    ? null
                    : () => Navigator.pop(context, destination),
                child: const Text('確認して保存'),
              ),
            ],
          );
        },
      ),
    );
    if (!mounted ||
        generation != _generation ||
        result == null ||
        widget.onAllocate != action) {
      return;
    }
    await _request(generation, () => action(claim, result));
  }

  Widget _card(ExpenseClaim claim, int generation) {
    final onApprove = widget.onApprove;
    final onReject = widget.onReject;
    final approved =
        claim.approval == ExpenseApproval.approved && !claim.withdrawn;
    final canDecide =
        !_busy && !claim.withdrawn && widget.canDecide?.call(claim) != false;
    return Card(
      key: ValueKey(claim.id),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  '${claim.amountYen}円',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                Chip(label: Text(expenseClaimStatusLabel(claim))),
              ],
            ),
            Text(
              '利用日：${claim.incurredOn.year}/${claim.incurredOn.month}/${claim.incurredOn.day}',
            ),
            if (claim.settlement != null)
              Text('${claim.approval == ExpenseApproval.approved ? '精算予定' : '前回の精算設定'}：${claim.settlement!.label} / ${claim.settlement!.month.year}年${claim.settlement!.month.month}月'),
            const SizedBox(height: 8),
            Text(
              claim.description,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            TextButton(
              onPressed: widget.applicantId != null
                  ? null
                  : () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => ExpenseClaimsPage(
                          claims: widget.claims,
                          applicantId: claim.applicantId,
                        ),
                      ),
                    ),
              child: Text(claim.applicantName),
            ),
            Text(
              '費用の負担先：${_categoryLabel(claim.allocation.category)}'
              '${claim.allocation.counterpartyName == null ? '' : ' / ${claim.allocation.counterpartyName}'}',
            ),
            if (claim.allocation.category == ExpenseCategory.customer)
              const Text('経費明細の表示先：請求書'),
            if (claim.allocation.category == ExpenseCategory.subcontractor)
              const Text('経費明細の表示先：支払証明書'),
            if (widget.applicantId == null) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  TextButton(
                    style: TextButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      foregroundColor: Theme.of(context).colorScheme.onPrimary,
                      disabledBackgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                    ),
                    onPressed:
                        !canDecide ||
                            onApprove == null ||
                            (claim.approval == ExpenseApproval.approved &&
                              !(widget.allowSettlementSetup && claim.settlement == null))
                        ? null
                        : () => _request(generation, () => onApprove(claim)),
                    child: Text(claim.approval == ExpenseApproval.approved && widget.allowSettlementSetup && claim.settlement == null ? '精算方法を設定' : '承認'),
                  ),
                  TextButton(
                    onPressed:
                        !canDecide ||
                            onReject == null ||
                            claim.approval == ExpenseApproval.rejected
                        ? null
                        : () => _request(generation, () => onReject(claim)),
                    child: const Text('却下'),
                  ),
                  if (approved) OutlinedButton(
                    onPressed:
                        _busy ||
                            !approved ||
                            widget.onAllocate == null ||
                            (widget.costAllocationEnabled && claim.settlement == null) ||
                            widget.destinations.isEmpty
                        ? null
                        : () => _allocate(claim, generation),
                    child: const Text('振り分け'),
                  ),
                ],
              ),
              if (approved) Text(widget.costAllocationEnabled && claim.settlement == null
                  ? '先に管理者・サブ管理者が精算方法を設定してください。'
                  : '費用の負担先を変える場合は「振り分け」を押します。'),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final generation = _generation;
    final scope = widget.applicantId == null
        ? widget.claims
        : widget.claims.forApplicant(widget.applicantId!);
    final entries = scope.forList(_list);
    final visible = entries.where(_matches).toList();
    final approved = entries
        .where((c) => !c.withdrawn && c.approval == ExpenseApproval.approved)
        .toList();
    final amount = approved.fold<int>(0, (sum, c) => sum + c.amountYen);
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: kToolbarHeight,
        title: Text(widget.applicantId == null ? '経費の承認・振り分け' : '個人の経費申請'),
        actions: [
          IconButton(
            tooltip: '経費の承認・振り分けのヘルプ',
            onPressed: _help,
            icon: const Icon(Icons.help_outline),
          ),
        ],
      ),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (widget.header != null) widget.header!,
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('まず申請内容を確認し、承認または却下します。'),
                      const SizedBox(height: 12),
                      const Text('承認状態'),
                      Wrap(
                        spacing: 8,
                        children: [
                          for (final filter in _ReviewFilter.values)
                            ChoiceChip(
                              label: Text(_filterLabel(filter)),
                              selected: _filter == filter,
                              onSelected: (_) =>
                                  setState(() => _filter = filter),
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      const Text('負担先で絞り込む'),
                      Wrap(
                        spacing: 8,
                        children: [
                          for (final kind in ExpenseList.values)
                            ChoiceChip(
                              label: Text(
                                '${_listLabel(kind)}（${scope.forList(kind).length}）',
                              ),
                              selected: _list == kind,
                              onSelected: (_) => setState(() => _list = kind),
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        '表示：${visible.length}件 / この負担先の承認済み：${approved.length}件・$amount円',
                      ),
                      const Text('承認済み金額は支払済額ではありません。'),
                      if (widget.onApprove == null &&
                          widget.onReject == null &&
                          widget.onAllocate == null)
                        const Text('閲覧専用です。承認・振り分けは担当者の一覧で行います。'),
                      if (_error != null) Text(_error!),
                    ],
                  ),
                ),
                if (_busy) const LinearProgressIndicator(),
              ],
            ),
          ),
          if (visible.isEmpty)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('この条件に該当する申請はありません'),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) => _card(visible[index], generation),
                  childCount: visible.length,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
