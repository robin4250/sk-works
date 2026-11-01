import 'package:flutter/material.dart';

import 'site_order_outgoing_journal.dart';
import 'site_order_outgoing_consent.dart';
import 'site_order_outgoing_execution.dart';
import 'site_order_original_review_page.dart';
import 'site_order_delivery_journal.dart';
import 'site_order_workflow_repository.dart';

/// Recovery stays available while generation is OFF. It cannot prepare, sign,
/// render or send by itself. A bound persisted-original review is a separate route.
/// Unobserved results never become cancellation or resend permission.
class SiteOrderOutgoingRecoveryPage extends StatefulWidget {
  const SiteOrderOutgoingRecoveryPage({
    super.key,
    required this.api,
    required this.siteId,
  });
  final SiteOrderWorkflowApi api;
  final String siteId;
  @override
  State<SiteOrderOutgoingRecoveryPage> createState() =>
      _SiteOrderOutgoingRecoveryPageState();
}

class _SiteOrderOutgoingRecoveryPageState
    extends State<SiteOrderOutgoingRecoveryPage> {
  List<SiteOrderPendingPrepare> _entries = const [];
  List<SiteOrderConsentReference> _decisions = const [];
  List<SiteOrderDeliveryRecord> _recorded = const [];
  final _observed = <String, SiteOrderExecutionObservation>{};
  bool _busy = true, _retired = false, _readSucceeded = false;
  String? _message;
  @override
  void initState() {
    super.initState();
    widget.api.addListener(_changed);
    _load();
  }

  void _changed() {
    if (!widget.api.invalidated || !mounted) {
      return;
    }
    setState(() {
      _retired = true;
      _entries = const [];
      _decisions = const [];
      _recorded = const [];
      _observed.clear();
      _message = 'ログイン・会社の状態が変わりました。開き直してください。';
    });
  }

  @override
  void didUpdateWidget(covariant SiteOrderOutgoingRecoveryPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.siteId != oldWidget.siteId || widget.api != oldWidget.api) {
      oldWidget.api.removeListener(_changed);
      _retired = true;
      _entries = const [];
      _decisions = const [];
      _recorded = const [];
      _observed.clear();
      _message = '現場が変わりました。開き直してください。';
    }
  }

  Future<void> _load() async {
    if (_retired) {
      return;
    }
    _readSucceeded = false;
    try {
      final entries = await widget.api.pendingOutgoing(widget.siteId);
      final decisions = await widget.api.pendingOutgoingConsents(widget.siteId);
      final recorded = await widget.api.recordedOutgoing(widget.siteId);
      if (!mounted || _retired || widget.api.invalidated) {
        return;
      }
      setState(() {
        _decisions = decisions;
        _recorded = recorded;
        _observed.clear();
        final requests = decisions.map((d) => d.prepare.requestId).toSet();
        _entries = entries
            .where((e) => !requests.contains(e.requestId))
            .toList(growable: false);
        _readSucceeded = true;
      });
    } catch (_) {
      if (mounted && !_retired) {
        setState(() => _message = '保存状態を確認できません。記録は保持しています。');
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _act(SiteOrderPendingPrepare entry, {required bool stop}) async {
    if (_busy || _retired || widget.api.invalidated) {
      return;
    }
    if (stop) {
      final confirmed = await showDialog<bool>(
        context: context,
        useRootNavigator: false,
        builder: (dialog) => AlertDialog(
          title: const Text('この注文の準備を停止'),
          content: const Text('結果不明の準備も照合し、未署名なら今後の準備を停止します。送信済みの注文は取り消しません。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog, false),
              child: const Text('戻る'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialog, true),
              child: const Text('停止を確認'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted || _retired || widget.api.invalidated) {
        return;
      }
    }
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final state = stop
          ? await widget.api.retireOutgoing(entry, confirmed: true)
          : await widget.api.inspectOutgoing(entry);
      if (!mounted || _retired || widget.api.invalidated) {
        return;
      }
      setState(
        () => _message = switch (state) {
          'retired' => '準備の停止を確認しました。注文の取消ではありません。',
          'prepared_review_required' => '準備済みです。署名・共有は行っていません。',
          'advanced' => '署名などが進んでいるため停止していません。保存済みの注文を確認してください。',
          'changed' => '内容の変更を検出しました。記録を保持して確認してください。',
          _ => '結果はまだ確認できません。再送せず、記録を保持しています。',
        },
      );
      await _load();
    } catch (_) {
      if (mounted && !_retired) {
        setState(() => _message = '結果を確認できません。再送せず、記録を保持しています。');
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _inspectDecision(SiteOrderConsentReference reference) async {
    if (_busy || _retired || widget.api.invalidated) {
      return;
    }
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final result = await widget.api.inspectOutgoingConsent(reference);
      if (!mounted || _retired || widget.api.invalidated) {
        return;
      }
      SiteOrderExecutionObservation? execution;
      if (result.observed) {
        execution = await widget.api.resolveOutgoingExecutionForReview(
          reference,
          jobId: result.jobId!,
        );
        if (!mounted || _retired || widget.api.invalidated) {
          return;
        }
      }
      setState(() {
        _observed.remove(reference.prepare.requestId);
        if (execution != null) {
          _observed[reference.prepare.requestId] = execution;
        }
        _message = execution?.recipientStored == true
            ? '相手会社の受信箱に保存されています。相手の承認は未確認です。'
            : execution?.unresolved == true
            ? '共有結果が未解決です。再送せず確認してください。'
            : execution != null
            ? '保存した注文の原本・共有状態を確認できます。'
            : '押印確認の結果は未確認です。再実行せず記録を保持しています。';
      });
    } catch (_) {
      if (mounted && !_retired) {
        setState(() {
          _observed.remove(reference.prepare.requestId);
          _message = '押印確認の結果を確認できません。再実行せず記録を保持しています。';
        });
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  void dispose() {
    widget.api.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('注文の準備結果'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('閉じる'),
        ),
      ],
    ),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('結果不明の注文は自動で再送しません。状態を照会するか、未署名の準備を停止できます。'),
        if (_message != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(_message!),
          ),
        if (_busy) const LinearProgressIndicator(),
        if (!_busy &&
            _readSucceeded &&
            _entries.isEmpty &&
            _decisions.isEmpty &&
            !_retired)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Text('確認待ちの準備記録はありません。'),
          ),
        for (final reference in _decisions)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('確認待ちの押印内容'),
                  Text('識別番号 ${reference.prepare.requestId}'),
                  OutlinedButton(
                    onPressed: _busy || _retired
                        ? null
                        : () => _inspectDecision(reference),
                    child: const Text('押印確認の保存結果を照会'),
                  ),
                  if (_observed[reference.prepare.requestId]
                      case final execution?)
                    OutlinedButton(
                      onPressed: _busy || _retired
                          ? null
                          : () async {
                              widget.api.requireCurrent();
                              await Navigator.push<SiteOrderDeliveryRecord>(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => SiteOrderOriginalReviewPage(
                                    api: widget.api,
                                    reference: reference,
                                    jobId: execution.jobId,
                                    recipientCompanyId:
                                        execution.recipientCompanyId,
                                  ),
                                ),
                              );
                              if (mounted &&
                                  !_retired &&
                                  !widget.api.invalidated) {
                                await _load();
                              }
                            },
                      child: const Text('保存原本・共有状態を確認'),
                    ),
                ],
              ),
            ),
          ),
        for (final record in _recorded)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('共有結果の保管記録（相手の承認は未確認）'),
                  Text('識別番号 ${record.reference.prepare.requestId}'),
                  OutlinedButton(
                    onPressed: _busy || _retired
                        ? null
                        : () async {
                            widget.api.requireCurrent();
                            await Navigator.push<SiteOrderDeliveryRecord>(
                              context,
                              MaterialPageRoute(
                                builder: (_) => SiteOrderOriginalReviewPage(
                                  api: widget.api,
                                  reference: record.reference,
                                  jobId: record.jobId,
                                  recipientCompanyId: record.recipientCompanyId,
                                ),
                              ),
                            );
                            if (mounted &&
                                !_retired &&
                                !widget.api.invalidated) {
                              await _load();
                            }
                          },
                    child: const Text('保存原本・共有状態を再照会'),
                  ),
                ],
              ),
            ),
          ),
        for (final entry in _entries)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('確認待ちの注文'),
                  Text('識別番号 ${entry.requestId}'),
                  OutlinedButton(
                    onPressed: _busy || _retired
                        ? null
                        : () => _act(entry, stop: false),
                    child: const Text('状態を照会'),
                  ),
                  TextButton(
                    onPressed: _busy || _retired
                        ? null
                        : () => _act(entry, stop: true),
                    child: const Text('準備を停止'),
                  ),
                ],
              ),
            ),
          ),
      ],
    ),
  );
}
