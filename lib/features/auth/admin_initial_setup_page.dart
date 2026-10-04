import 'package:flutter/material.dart';

import '../people/company_submitted_documents_page.dart';
import '../people/employee_initial_registration_page.dart';
import '../people/employee_registration_page.dart';
import '../qualifications/qualification_cloud_page.dart';
import 'admin_initial_setup_repository.dart';

class AdminInitialSetupWizardPage extends StatefulWidget {
  const AdminInitialSetupWizardPage({
    super.key,
    required this.onCompleted,
    required this.onSignOut,
  });

  final VoidCallback onCompleted;
  final Future<void> Function() onSignOut;

  @override
  State<AdminInitialSetupWizardPage> createState() =>
      _AdminInitialSetupWizardPageState();
}

class _AdminInitialSetupWizardPageState
    extends State<AdminInitialSetupWizardPage> {
  final _repository = AdminInitialSetupRepository.maybeCreate();

  bool _loading = true;
  bool _busy = false;
  String? _error;
  AdminInitialSetupState? _state;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final repository = _repository;
    if (repository == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final state = await repository.loadState();
      if (!mounted) return;
      setState(() {
        _state = state;
        _loading = false;
      });
      if (state.completed) widget.onCompleted();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _openAndComplete({
    required String step,
    required Widget page,
  }) async {
    final repository = _repository;
    if (repository == null || _busy) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => page),
    );
    if (!mounted) return;

    setState(() => _busy = true);
    try {
      await repository.markStep(step);
      await _load();
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _stepTile({
    required int number,
    required String title,
    required String body,
    required bool completed,
    VoidCallback? onTap,
    String actionLabel = '開く',
  }) {
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          child: completed
              ? const Icon(Icons.check)
              : Text(
                  '$number',
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
        ),
        title: Text(
          '$number. $title',
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        subtitle: Text(body),
        trailing: completed
            ? const Icon(Icons.check_circle_outline)
            : FilledButton(
                onPressed: _busy ? null : onTap,
                child: Text(actionLabel),
              ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = _state;
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'SKO 初期設定',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        actions: [
          TextButton(
            onPressed: _busy ? null : widget.onSignOut,
            child: const Text('ログアウト'),
          ),
        ],
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null && state == null
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
                            child: const Text('再試行'),
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                    children: [
                      const Card(
                        child: Padding(
                          padding: EdgeInsets.all(16),
                          child: Text(
                            '管理者の初回設定はこの順番で進めます。'
                            '現場登録や単価設定は初回必須ではなく、SKO開始後に通常メニューから設定できます。',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          _error!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ],
                      const SizedBox(height: 10),
                      _stepTile(
                        number: 1,
                        title: '個人情報登録',
                        body: '管理者本人の氏名・電話番号などを登録します。',
                        completed: state?.personalProfileCompleted == true,
                      ),
                      _stepTile(
                        number: 2,
                        title: '会社情報登録',
                        body: '会社名・住所・連絡先などの会社基本情報を登録します。',
                        completed: state?.companyProfileCompleted == true,
                      ),
                      _stepTile(
                        number: 3,
                        title: '提出書類登録',
                        body: '会社として提出・保管する書類を確認・登録します。',
                        completed: state?.companyDocumentsReviewed == true,
                        onTap: () => _openAndComplete(
                          step: 'company_documents',
                          page: const CompanySubmittedDocumentsPage(),
                        ),
                      ),
                      _stepTile(
                        number: 4,
                        title: '資格設定',
                        body: '会社で使う資格種類・資格情報を確認し、必要な資格を設定します。',
                        completed:
                            state?.qualificationSettingsReviewed == true,
                        onTap: () => _openAndComplete(
                          step: 'qualification_settings',
                          page: const QualificationCloudPage(),
                        ),
                      ),
                      _stepTile(
                        number: 5,
                        title: '従業員登録',
                        body: '従業員の名前と携帯電話番号を先に登録します。',
                        completed:
                            state?.employeeRegistrationReviewed == true,
                        onTap: () => _openAndComplete(
                          step: 'employee_registration',
                          page: const EmployeeRegistrationPage(),
                        ),
                      ),
                      _stepTile(
                        number: 6,
                        title: '初回登録',
                        body: '登録済み従業員へTestFlightと本人専用の初回ログイン情報を送ります。',
                        completed:
                            state?.initialRegistrationReviewed == true,
                        onTap: () => _openAndComplete(
                          step: 'initial_registration',
                          page: const EmployeeInitialRegistrationPage(),
                        ),
                        actionLabel: '送信へ',
                      ),
                    ],
                  ),
      ),
    );
  }
}
