import 'package:flutter/material.dart';

import 'employee_retirement_repository.dart';
import 'people_cloud_repository.dart';

class EmployeeRetirementPage extends StatefulWidget {
  const EmployeeRetirementPage({
    super.key,
    required this.companyId,
    required this.workerId,
    required this.workerName,
    required this.privacySession,
    this.repository,
  });
  final String companyId, workerId, workerName;
  final PersonnelPrivacySession privacySession;
  @visibleForTesting
  final EmployeeRetirementRepository? repository;
  @override
  State<EmployeeRetirementPage> createState() => _EmployeeRetirementPageState();
}

class _EmployeeRetirementPageState extends State<EmployeeRetirementPage> {
  bool _confirmed = false, _busy = false;
  String? _error;
  bool _queued = false;
  EmployeeRetirementRepository? get _repository =>
      widget.repository ?? EmployeeRetirementRepository.maybeCreate();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _refreshQueue();
    });
  }

  Future<void> _refreshQueue() async {
    final repository = _repository;
    if (_busy || repository == null) return;
    final lease = widget.privacySession.epoch;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final state = await repository.queueState(
        companyId: widget.companyId,
        workerId: widget.workerId,
        verifyContext: () {
          widget.privacySession.verify(lease);
          final snapshot = widget.privacySession.snapshot;
          if (snapshot?.company != widget.companyId ||
              snapshot?.canManage != true) {
            throw const PersonnelScopeChanged();
          }
        },
      );
      if (!mounted) return;
      if (state == RetirementQueueState.completed) {
        Navigator.of(context).pop(true);
        return;
      }
      setState(() {
        _queued = state == RetirementQueueState.pending;
        if (state == RetirementQueueState.renewRequired) {
          _confirmed = false;
          _error = '受付時のログインが終了しました。対象を確認して再開してください。';
        }
      });
    } catch (_) {
      if (mounted) setState(() => _error = '退職処理の状態を取得できませんでした。');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submit() async {
    if (_busy || !_confirmed || _queued) return;
    final repository = _repository;
    if (repository == null) {
      setState(() => _error = 'ログイン情報を確認できません。画面を開き直してください。');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final lease = widget.privacySession.epoch;
    void verifyContext() {
      widget.privacySession.verify(lease);
      final snapshot = widget.privacySession.snapshot;
      if (snapshot?.company != widget.companyId ||
          snapshot?.canManage != true ||
          !snapshot!.records.any(
            (row) => row['id'] == widget.workerId && row['active'] == true,
          )) {
        throw const PersonnelScopeChanged();
      }
    }

    try {
      await repository.retire(
        companyId: widget.companyId,
        workerId: widget.workerId,
        verifyContext: verifyContext,
      );
      if (mounted) Navigator.of(context).pop(true);
    } on RetirementQueued {
      if (mounted) setState(() => _queued = true);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = '退職処理を確認できません。一覧を再読み込みして状態を確認してください。再実行は自動で行いません。',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: Scaffold(
      appBar: AppBar(title: const Text('退職手続き')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            widget.workerName,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 16),
          const Text('退職後は退職者一覧に表示します。社員情報・給与・日報・署名・資格書類は削除しません。'),
          if (_queued)
            const Text('退職手続きを受け付けました。本人の倉庫への保存を確認するまで在籍状態です。')
          else
            CheckboxListTile(
              value: _confirmed,
              title: const Text('対象を確認し、退職として登録します'),
              onChanged: _busy
                  ? null
                  : (value) => setState(() => _confirmed = value == true),
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(_error!),
            ),
          const SizedBox(height: 20),
          if (_queued)
            FilledButton(
              onPressed: _busy ? null : _refreshQueue,
              child: Text(_busy ? '確認しています…' : '処理状況を確認'),
            )
          else
            FilledButton(
              onPressed: !_busy && _confirmed ? _submit : null,
              child: Text(_busy ? '確認しています…' : '退職として登録'),
            ),
        ],
      ),
    ),
  );
}
