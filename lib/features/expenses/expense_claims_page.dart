import 'package:flutter/material.dart';
import 'expense_claim.dart';

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
  @override
  State<ExpenseClaimsPage> createState() => _ExpenseClaimsPageState();
}

class _ExpenseClaimsPageState extends State<ExpenseClaimsPage> {
  ExpenseList _list = ExpenseList.allocation;
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

  @override
  Widget build(BuildContext context) {
    final generation = _generation;
    final onApprove = widget.onApprove;
    final onReject = widget.onReject;
    final onAllocate = widget.onAllocate;
    final destinations = List<ExpenseAllocation>.unmodifiable(
      widget.destinations,
    );
    final scope = widget.applicantId == null
        ? widget.claims
        : widget.claims.forApplicant(widget.applicantId!);
    final visible = scope.forList(_list);
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: kToolbarHeight,
        title: Text(widget.applicantId == null ? '経費申請一覧' : '個人の経費申請'),
      ),
      body: Column(
        children: [
          if (widget.header != null) widget.header!,
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                for (final kind in ExpenseList.values)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(switch (kind) {
                        ExpenseList.allocation => '振り分け用',
                        ExpenseList.ownCompany => '自社',
                        ExpenseList.subcontractor => '下請け・協力会社',
                        ExpenseList.customer => '取引先',
                      }),
                      selected: _list == kind,
                      onSelected: (_) => setState(() => _list = kind),
                    ),
                  ),
              ],
            ),
          ),
          if (onApprove == null && onReject == null && onAllocate == null)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Text('閲覧専用です。承認・振り分けは担当者の一覧で行います。'),
            ),
          if (_busy) const LinearProgressIndicator(),
          if (_error != null)
            Padding(padding: const EdgeInsets.all(12), child: Text(_error!)),
          Expanded(
            child: visible.isEmpty
                ? const Center(child: Text('申請はありません'))
                : ListView.builder(
                    itemCount: visible.length,
                    padding: const EdgeInsets.all(12),
                    itemBuilder: (context, index) {
                      final claim = visible[index];
                      return Card(
                        key: ValueKey(claim.id),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${claim.incurredOn.year}/${claim.incurredOn.month}/${claim.incurredOn.day}  ${claim.amountYen}円',
                              ),
                              Text(claim.description),
                              Text(
                                '${expenseApprovalLabel(claim.approval)} / ${expenseCategoryLabel(claim.allocation.category)}'
                                '${claim.allocation.counterpartyName == null ? '' : ' / ${claim.allocation.counterpartyName}'}',
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
                              Wrap(
                                spacing: 8,
                                children: [
                                  TextButton(
                                    onPressed:
                                        _busy ||
                                            onApprove == null ||
                                            widget.canDecide?.call(claim) ==
                                                false ||
                                            claim.approval ==
                                                ExpenseApproval.approved
                                        ? null
                                        : () => _request(
                                            generation,
                                            () => onApprove(claim),
                                          ),
                                    child: const Text('承認'),
                                  ),
                                  TextButton(
                                    onPressed:
                                        _busy ||
                                            onReject == null ||
                                            widget.canDecide?.call(claim) ==
                                                false ||
                                            claim.approval ==
                                                ExpenseApproval.rejected
                                        ? null
                                        : () => _request(
                                            generation,
                                            () => onReject(claim),
                                          ),
                                    child: const Text('却下'),
                                  ),
                                  PopupMenuButton<int>(
                                    enabled:
                                        !_busy &&
                                        onAllocate != null &&
                                        claim.approval ==
                                            ExpenseApproval.approved &&
                                        destinations.isNotEmpty,
                                    tooltip: '振り分け',
                                    onSelected: (index) => _request(
                                      generation,
                                      () => onAllocate!(
                                        claim,
                                        destinations[index],
                                      ),
                                    ),
                                    itemBuilder: (_) => [
                                      for (
                                        var i = 0;
                                        i < destinations.length;
                                        i++
                                      )
                                        PopupMenuItem(
                                          value: i,
                                          child: Text(
                                            '${expenseCategoryLabel(destinations[i].category)}'
                                            '${destinations[i].counterpartyName == null ? '' : ' / ${destinations[i].counterpartyName}'}',
                                          ),
                                        ),
                                    ],
                                    child: const Padding(
                                      padding: EdgeInsets.all(12),
                                      child: Text('振り分け'),
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
        ],
      ),
    );
  }
}
