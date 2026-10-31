import 'dart:io';
import 'dart:async';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/material.dart';
import 'expense_receipt_attachment.dart';
import 'expense_review_detail_page.dart';
import 'expense_review_history_dialog.dart';
import 'package:flutter/services.dart';
import 'expense_claim.dart';
import 'expense_claims_page.dart';
import 'expense_submission_repository.dart';
import 'expense_personal_change_repository.dart';
import 'expense_edit_dialog.dart';
import 'expense_receipt_amount_recognition.dart';

class ExpensePersonalPage extends StatefulWidget {
  const ExpensePersonalPage({super.key, this.access, this.changes, this.pickReceipt, this.recognizeReceiptText});
  final ExpenseSubmissionAccess? access;
  final ExpensePersonalChangeAccess? changes;
  final Future<ExpenseReceiptAttachment?> Function(ImageSource source)? pickReceipt;
  final Future<String> Function(String localPath)? recognizeReceiptText;
  @override
  State<ExpensePersonalPage> createState() => _ExpensePersonalPageState();
}

class _ExpensePersonalPageState extends State<ExpensePersonalPage> with WidgetsBindingObserver {
  ExpenseSubmissionAccess? _access;
  ExpensePersonalChangeAccess? _changes;
  ExpensePersonalChange? _pendingChange;
  final _description = TextEditingController(),
      _amount = TextEditingController();
  List<Map<String, dynamic>> _scopes = [];
  Map<String, dynamic>? _scope;
  List<ExpenseClaim> _history = [];
  ExpenseSubmission? _pending;
  ExpenseReceiptAttachment? _receipt;
  DateTime _date = DateTime.now(), _month = DateTime.now();
  bool _busy = true, _ready = false;
  bool _submitting = false;
  String? _error, _actor;
  int _generation = 0;
  int _ocrGeneration = 0, _amountRevision = 0;
  bool _ocrReading = false;
  String? _ocrMessage;
  List<ExpenseReceiptAmountCandidate> _amountCandidates = const [];
  ExpenseReceiptAttachment? _candidateReceipt;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _amount.addListener(() => _amountRevision++);
    try {
      _access = widget.access ?? ExpenseSubmissionRepository();
      _changes =
          widget.changes ??
          (widget.access == null ? ExpensePersonalChangeRepository() : null);
    } catch (_) {
      _error = '経費申請に接続できません。';
      _busy = false;
    }
    if (_access != null) _loadScopes();
  }

  @override
  void dispose() {
    _generation++;
    _ocrGeneration++;
    WidgetsBinding.instance.removeObserver(this);
    _description.dispose();
    _amount.dispose();
    super.dispose();
  }

  void _clearOcr() {
    _ocrGeneration++;
    _ocrReading = false;
    _ocrMessage = null;
    _amountCandidates = const [];
    _candidateReceipt = null;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (mounted && (state == AppLifecycleState.hidden || state == AppLifecycleState.paused)) {
      setState(_clearOcr);
    }
  }

  Future<void> _recognizeReceipt(ExpenseReceiptAttachment photo) async {
    final request = ++_ocrGeneration;
    final generation = _generation, actor = _actor;
    final company = _scope?['company_id'], worker = _scope?['worker_id'];
    final initialAmount = _amount.text, amountRevision = _amountRevision;
    bool current() => _current(generation) && request == _ocrGeneration &&
      actor == _actor && company == _scope?['company_id'] && worker == _scope?['worker_id'] &&
      identical(_receipt, photo) && _pending == null;
    setState(() { _ocrReading = true; _ocrMessage = null; });
    try {
      final readText = widget.recognizeReceiptText;
      final result = readText == null
        ? await const ExpenseReceiptAmountRecognition().recognize(photo.localPath)
        : ExpenseReceiptAmountRecognition.parse(await readText(photo.localPath));
      if (!current()) return;
      setState(() {
        _ocrReading = false;
        _amountCandidates = result.candidates;
        _candidateReceipt = photo;
        final total = result.unambiguousTotal;
        final untouched = _amountRevision == amountRevision && _amount.text == initialAmount;
        if (total != null && initialAmount.trim().isEmpty && untouched) {
          _amount.text = '$total';
          _ocrMessage = '写真からの金額候補です。領収書の税込合計と金額を確認してから申請してください。';
        } else if (result.candidates.isEmpty) {
          _ocrMessage = '金額を読み取れませんでした。領収書を確認して金額を入力してください。';
        } else if (!untouched || initialAmount.trim().isNotEmpty) {
          _ocrMessage = '入力済みの金額は変更していません。写真の候補と比べてください。';
        } else {
          _ocrMessage = '写真の金額候補です。領収書の税込合計を確認して選択するか、金額を入力してください。';
        }
      });
    } catch (_) {
      if (current()) {
        setState(() {
          _ocrReading = false;
          _ocrMessage = '金額を読み取れませんでした。写真は保持しています。金額を入力して申請できます。';
        });
      }
    }
  }

  void _useAmountCandidate(ExpenseReceiptAmountCandidate candidate) {
    if (_busy || !_ready || _pending != null || _access?.actor != _actor ||
        _candidateReceipt == null || !identical(_receipt, _candidateReceipt) ||
        !_amountCandidates.contains(candidate)) {
      return;
    }
    setState(() {
      _amount.text = '${candidate.amountYen}';
      _ocrMessage = '選択した金額と領収書の税込合計を確認してから申請してください。';
    });
  }

  bool _current(int generation) =>
      mounted && generation == _generation && _access?.actor == _actor;
  Future<void> _loadScopes() async {
    final generation = ++_generation;
    setState(() {
      _clearOcr();
      _busy = true;
      _ready = false;
      _error = null;
    });
    try {
      _actor = _access!.actor;
      if (_actor == null) throw StateError('ログインが必要です。');
      final scopes = await _access!.scopes();
      if (!_current(generation)) {
        return;
      }
      setState(() {
        _scopes = scopes;
        _scope = scopes.length == 1 ? scopes.single : null;
      });
      if (_scope != null) await _loadSelection(generation);
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() => _error = '申請先を確認できません。再読み込みしてください。');
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _loadSelection(int generation) async {
    final scope = _scope!;
    final pending = await _access!.pending(
      scope['company_id'],
      scope['worker_id'],
    );
    if (!_current(generation)) {
      return;
    }
    setState(() {
      _pending = pending;
      _ready = false;
    });
    final change = await _changes?.pending(
      scope['company_id'],
      scope['worker_id'],
    );
    if (!_current(generation)) {
      return;
    }
    setState(() => _pendingChange = change);
    final history = await _access!.history(
      scope['company_id'],
      scope['worker_id'],
      _month,
    );
    if (!_current(generation)) {
      return;
    }
    setState(() { _history = history; _ready = true; });
  }

  Future<void> _reload() async {
    if (_scope == null) {
      return _loadScopes();
    }
    final generation = ++_generation;
    setState(() {
      _clearOcr();
      _busy = true;
      _ready = false;
      _error = null;
      _history = [];
    });
    try {
      await _loadSelection(generation);
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() => _error = '申請履歴を確認できません。再読み込みしてください。');
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _send() async {
    if (_busy ||
        !_ready ||
        _scope == null ||
        _pendingChange != null ||
        _access?.actor != _actor) {
      return;
    }
    final generation = ++_generation;
    setState(() {
      _busy = true;
      _submitting = true;
      _error = null;
      _clearOcr();
    });
    final companyName = _scope!['company_name']?.toString() ?? '所属会社';
    try {
      final draft =
          _pending ??
          ExpenseSubmission.create(
            _actor!,
            _scope!['company_id'],
            _scope!['worker_id'],
            _date,
            _description.text,
            _amount.text, receipt: _receipt,
          );
      setState(() => _pending = draft);
      await _access!.submit(draft);
      if (!_current(generation)) {
        return;
      }
      setState(() {
        _pending = null;
        _description.clear();
        _amount.clear();
        _receipt = null;
        _month = DateTime.parse(draft.date);
      });
      if (!mounted) {
        return;
      }
      var acknowledged = false;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('経費の申請が完了しました'),
          content: Text(
            '$companyNameへの経費申請を登録しました。承認状況は、この画面の申請履歴で確認できます。',
          ),
          actions: [
            FilledButton(
              onPressed: () {
                if (acknowledged) {
                  return;
                }
                acknowledged = true;
                Navigator.pop(dialogContext);
              },
              child: const Text('申請履歴を確認'),
            ),
          ],
        ),
      );
      if (!_current(generation)) {
        return;
      }
      try {
        await _loadSelection(generation);
      } catch (_) {
        if (_current(generation)) {
          setState(() {
            _ready = false;
            _error = '申請は登録済みですが、履歴を再読み込みできませんでした。再申請せず、この画面を再読み込みしてください。';
          });
        }
      }
    } catch (e) {
      if (mounted && generation == _generation) {
        setState(
          () =>
              _error = _pending == null ? '$e' : '保存結果を確認できません。同じ申請を再確認してください。',
        );
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() { _busy = false; _submitting = false; });
      }
    }
  }

  Future<void> _pickReceipt(ImageSource source) async {
    if (_busy || _pending != null || _scope == null || _access?.actor != _actor) {
      return;
    }
    final generation = _generation, actor = _actor, scope = _scope;
    setState(() { _busy = true; _clearOcr(); });
    try {
      ExpenseReceiptAttachment? photo;
      if (widget.pickReceipt != null) {
        photo = await widget.pickReceipt!(source);
      } else {
        final selected = await ImagePicker().pickImage(source: source, maxWidth: 1800, imageQuality: 85);
        if (selected != null) {
          photo = await ExpenseReceiptAttachment.capture(selected);
        }
      }
      if (!_current(generation) || actor != _actor || scope != _scope) {
        return;
      }
      if (photo != null) {
        setState(() { _receipt = photo; _error = null; });
        unawaited(_recognizeReceipt(photo));
      }
    } catch (_) {
      if (_current(generation)) {
        setState(() => _error = '領収書を取得できません。カメラ・写真の許可と画像（10MB以内のJPEG／PNG）を確認してください。');
      }
    } finally {
      if (_current(generation)) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _changeClaim(
    ExpenseClaim claim, {
    required bool withdraw,
  }) async {
    if (_busy ||
        _changes == null ||
        _pending != null ||
        _pendingChange != null ||
        claim.withdrawn) {
      return;
    }
    final generation = _generation;
    ExpenseSubmission? edit;
    if (withdraw) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('経費申請を削除'),
          content: const Text('この申請を取り下げます。申請・承認の履歴と確定済み帳票は残ります。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('キャンセル'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('削除する'),
            ),
          ],
        ),
      );
      if (confirmed != true) {
        return;
      }
    } else {
      edit = await showDialog<ExpenseSubmission>(
        context: context,
        builder: (_) => ExpenseEditDialog(claim: claim, actor: _actor!),
      );
      if (edit == null) {
        return;
      }
    }
    if (!_current(generation)) {
      return;
    }
    await _sendChange(ExpensePersonalChange.create(_actor!, claim, edit: edit));
  }

  Future<void> _sendChange(ExpensePersonalChange command) async {
    if (_busy || _access?.actor != _actor) {
      return;
    }
    final generation = ++_generation;
    setState(() {
      _clearOcr();
      _busy = true;
      _pendingChange = command;
      _error = null;
    });
    try {
      await _changes!.send(command);
      if (!_current(generation)) {
        return;
      }
      setState(() {
        _pendingChange = null;
        if (!command.withdrawing) {
          _month = DateTime.parse(command.parameters['p_date']);
        }
      });
      await _loadSelection(generation);
      if (mounted && _current(generation)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              command.withdrawing ? '申請を取り下げました' : '変更して再申請しました。承認待ちです。',
            ),
          ),
        );
      }
    } catch (_) {
      if (_current(generation)) {
        try {
          final pending = await _changes!.pending(
            command.company,
            command.worker,
          );
          if (_current(generation)) {
            setState(() {
              _pendingChange = pending;
            });
          }
        } catch (_) {
          /* Keep the fixed command until its outcome is known. */
        }
        if (_current(generation)) {
          setState(() {
            _error = '変更結果を確認できません。同じ変更の再確認か、履歴の再読み込みをしてください。';
          });
        }
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  Future<void> _pickDate({bool month = false}) async {
    final date = await showDatePicker(
      context: context,
      initialDate: month ? _month : _date,
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
    );
    if (date == null || !mounted) {
      return;
    }
    if (month) {
      setState(() => _month = date);
      await _reload();
    } else {
      setState(() => _date = date);
    }
  }

  String _label(DateTime d) => '${d.year}/${d.month}/${d.day}';
  @override
  Widget build(BuildContext context) {
    final pending = _pending;
    final editable =
        !_busy &&
        _ready &&
        pending == null &&
        _pendingChange == null &&
        _access?.actor == _actor;
    return PopScope(
      canPop: !_submitting,
      child: Scaffold(
      appBar: AppBar(toolbarHeight: kToolbarHeight, title: const Text('経費申請')),
      body: _actor != null && _access?.actor != _actor
          ? const Center(child: Text('ログイン情報が変わりました。開き直してください。'))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (_busy) const LinearProgressIndicator(),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(_error!),
                  ),
                if (_scopes.length > 1)
                  DropdownButtonFormField<String>(
                    initialValue: _scope == null
                        ? null
                        : '${_scope!['company_id']}/${_scope!['worker_id']}',
                    decoration: const InputDecoration(labelText: '申請する本人の所属'),
                    items: [
                      for (final s in _scopes)
                        DropdownMenuItem(
                          value: '${s['company_id']}/${s['worker_id']}',
                          child: Text(
                            '${s['company_name']}・${s['worker_name']}',
                          ),
                        ),
                    ],
                    onChanged: _busy
                        ? null
                        : (value) {
                            setState(() {
                              _scope = _scopes.singleWhere(
                                (s) =>
                                    '${s['company_id']}/${s['worker_id']}' ==
                                    value,
                              );
                              _pending = null;
                              _receipt = null;
                              _clearOcr();
                              _description.clear();
                              _amount.clear();
                            });
                            _reload();
                          },
                  ),
                if (_scope != null) ...[
                  Text('${_scope!['company_name']}・${_scope!['worker_name']}'),
                  const SizedBox(height: 12),
                  if (pending != null)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(
                          '確認中の申請\n${pending.date}　${pending.amount}円\n${pending.description}',
                        ),
                      ),
                    )
                  else ...[
                    OutlinedButton.icon(
                      onPressed: editable ? () => _pickDate() : null,
                      icon: const Icon(Icons.calendar_month),
                      label: Text('利用日　${_label(_date)}'),
                    ),
                    const Text('領収書の写真（任意）'),
                    Row(children: [
                      Expanded(child: SizedBox(height: 48,
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8)),
                          onPressed: editable ? () => _pickReceipt(ImageSource.camera) : null,
                          icon: const Icon(Icons.camera_alt, size: 20),
                          label: const FittedBox(fit: BoxFit.scaleDown, child: Text('写真を撮る', maxLines: 1)),
                        ),
                      )),
                      const SizedBox(width: 8),
                      Expanded(child: SizedBox(height: 48,
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8)),
                          onPressed: editable ? () => _pickReceipt(ImageSource.gallery) : null,
                          icon: const Icon(Icons.photo_library, size: 20),
                          label: const FittedBox(fit: BoxFit.scaleDown, child: Text('写真を選ぶ', maxLines: 1)),
                        ),
                      )),
                    ]),
                    if (_receipt != null) ...[
                      const Text('申請前の領収書プレビュー'),
                      Image.file(File(_receipt!.localPath), height: 180, fit: BoxFit.contain,
                        errorBuilder: (_, error, stack) => const Text('写真を確認できません。選び直してください。')),
                      TextButton(onPressed: editable ? () => setState(() { _receipt = null; _clearOcr(); }) : null,
                        child: const Text('写真を外す')),
                      if (_ocrReading) const Text('写真から金額候補を読み取り中です。金額は手入力もできます。'),
                      if (_ocrMessage != null) Text(_ocrMessage!),
                      if (_amountCandidates.isNotEmpty) Wrap(spacing: 8, runSpacing: 4, children: [
                        for (final candidate in _amountCandidates)
                          OutlinedButton(onPressed: editable ? () => _useAmountCandidate(candidate) : null,
                            child: Text('${candidate.label} ${candidate.amountYen}円')),
                      ]),
                    ],
                    TextField(
                      controller: _description,
                      enabled: editable,
                      maxLength: 1000,
                      maxLines: 2,
                      decoration: const InputDecoration(labelText: '内容'),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                      child: Text(
                        '税理士・会計士が内容を確認するため、いつ・どこで・何のために・何を購入／利用したかを具体的に記入してください。'
                        '説明が不足すると、再度確認をお願いする場合があります。\n'
                        '例：○○現場で使用する養生テープ3巻を、○○店で購入。',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                    TextField(
                      controller: _amount,
                      enabled: editable,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: const InputDecoration(labelText: '金額（円）'),
                    ),
                  ],
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed:
                        !_busy &&
                            _ready &&
                            _pendingChange == null &&
                            _access?.actor == _actor
                        ? _send
                        : null,
                    child: Text(pending == null ? '申請する' : '同じ申請を再確認'),
                  ),
                  if (_pendingChange != null)
                    OutlinedButton(
                      onPressed: _busy
                          ? null
                          : () => _sendChange(_pendingChange!),
                      child: const Text('確認中の変更を再確認'),
                    ),
                  const Divider(height: 32),
                  OutlinedButton(
                    onPressed: _busy ? null : () => _pickDate(month: true),
                    child: Text('利用月　${_month.year}年${_month.month}月'),
                  ),
                  for (final claim in _history)
                    Card(color: Colors.white, elevation: 1,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16),
                        side: BorderSide(color: Theme.of(context).colorScheme.primary.withValues(alpha: .12))),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    ListTile(
                      onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (detailContext) => ExpenseReviewDetailPage(
                        claim: claim,
                        onEdit: editable && _changes != null && !claim.withdrawn ? () async {
                          await _changeClaim(claim, withdraw: false);
                          if (detailContext.mounted && _pendingChange == null && _error == null) {
                            Navigator.pop(detailContext);
                          }
                        } : null,
                        onDelete: editable && _changes != null && !claim.withdrawn ? () async {
                          await _changeClaim(claim, withdraw: true);
                          if (detailContext.mounted && _pendingChange == null && _error == null &&
                              _history.any((item) => item.id == claim.id && item.withdrawn)) {
                            Navigator.pop(detailContext);
                          }
                        } : null,
                        onHistory: _access is! ExpenseSubmissionRepository ? null : () async {
                          try {
                            final result = await (_access as ExpenseSubmissionRepository).reviewHistory(claim);
                            if (!detailContext.mounted) {
                              return;
                            }
                            await showDialog<void>(context: detailContext, builder: (_) => ExpenseReviewHistoryDialog(
                              events: (result['events'] as List).map((e) => Map<String, dynamic>.from(e)).toList()));
                          } catch (_) {
                            if (detailContext.mounted) {
                              ScaffoldMessenger.of(detailContext).showSnackBar(const SnackBar(content: Text('履歴を取得できません。再度確認してください。')));
                            }
                          }
                        },
                      ))),
                      leading: CircleAvatar(radius: 17, backgroundColor: Theme.of(context).colorScheme.primary.withValues(alpha: .09),
                        child: Icon(Icons.receipt_long_outlined, size: 22, color: Theme.of(context).colorScheme.primary)),
                      title: Text(claim.description, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.black87)),
                      subtitle: Text(
                        '${_label(claim.incurredOn)}　${expenseClaimStatusLabel(claim)}'
                        '${claim.settlement == null ? '\n精算方法：未設定' : '\n${claim.approval == ExpenseApproval.approved ? '精算予定' : '前回の精算設定'}：${claim.settlement!.label} / ${claim.settlement!.month.year}年${claim.settlement!.month.month}月'}',
                      ),
                      trailing: Text('${claim.amountYen}円'),
                    ),
                    if (_changes != null && !claim.withdrawn)
                      Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                        child: Row(children: [
                          Expanded(child: OutlinedButton.icon(
                            onPressed: editable ? () => _changeClaim(claim, withdraw: false) : null,
                            icon: const Icon(Icons.edit_outlined),
                            style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48),
                              textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                            label: const Text('編集'))),
                          const SizedBox(width: 12),
                          Expanded(child: OutlinedButton.icon(
                            onPressed: editable ? () => _changeClaim(claim, withdraw: true) : null,
                            icon: const Icon(Icons.delete_outline),
                            style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48),
                              textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              foregroundColor: Theme.of(context).colorScheme.error),
                            label: const Text('削除'))),
                        ])),
                    ])),
                  if (_history.isNotEmpty)
                    TextButton(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => ExpenseClaimsPage(
                            claims: ExpenseClaims(
                              companyId: _scope!['company_id'],
                              claims: _history,
                            ),
                            applicantId: _scope!['worker_id'],
                          ),
                        ),
                      ),
                      child: const Text('個人の経費一覧を開く'),
                    ),
                ] else if (!_busy && _error == null)
                  const Text('申請できる本人の従業員登録がありません。'),
                TextButton(
                  onPressed: _busy ? null : _reload,
                  child: const Text('再読み込み'),
                ),
              ],
            ),
      ),
    );
  }
}

