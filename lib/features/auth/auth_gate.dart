import 'package:flutter/material.dart';

import '../../data/supabase_backend.dart';
import 'admin_initial_setup_page.dart';
import 'admin_initial_setup_repository.dart';
import 'employee_onboarding_pages.dart';
import 'secure_onboarding_pages.dart';
import 'secure_onboarding_repository.dart';

class SupabaseAuthGate extends StatefulWidget {
  const SupabaseAuthGate({
    super.key,
    required this.homeBuilder,
  });

  final Widget Function(VoidCallback onSignOut) homeBuilder;

  @override
  State<SupabaseAuthGate> createState() => _SupabaseAuthGateState();
}

class _SupabaseAuthGateState extends State<SupabaseAuthGate> {
  late Future<_GateState> _state;

  SecureOnboardingRepository? get _repository =>
      SecureOnboardingRepository.maybeCreate();

  @override
  void initState() {
    super.initState();
    _state = _loadState();
  }

  Future<_GateState> _loadState() async {
    final repository = _repository;
    final user = SupabaseBackend.client.auth.currentUser;

    if (repository == null || user == null) {
      return const _GateState.unauthenticated();
    }

    final employee = await repository.employeeOnboardingState();
    if (employee != null && employee.status == 'cancelled') {
      return _GateState.employeeInviteInvalid(employee);
    }

    if (employee != null && employee.status != 'approved') {
      if (employee.needsPrimaryPassword) {
        return _GateState.employeePassword(employee);
      }
      if (employee.needsProfile) {
        return _GateState.employeeProfile(employee);
      }
      if (employee.awaitingApproval) {
        return _GateState.employeeApprovalPending(employee);
      }
    }

    final hasCompany = await repository.hasCompanyMembership();
    if (!hasCompany) {
      if (repository.companySetupDeferred) {
        return const _GateState.companyDeferred();
      }
      return const _GateState.needsCompany();
    }

    final adminSetupRepository = AdminInitialSetupRepository.maybeCreate();
    if (adminSetupRepository != null) {
      final setup = await adminSetupRepository.loadState();
      if (setup.required && !setup.completed) {
        return const _GateState.needsAdminInitialSetup();
      }
    }

    return const _GateState.authenticated();
  }

  void _reload() {
    setState(() {
      _state = _loadState();
    });
  }

  Future<void> _signOut() async {
    await _repository?.signOut();
    _reload();
  }

  Future<void> _resumeCompanySetup() async {
    await _repository?.setCompanySetupDeferred(false);
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_GateState>(
      future: _state,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const _LoadingScreen();
        }

        if (snapshot.hasError) {
          return _ErrorScreen(
            message: snapshot.error.toString(),
            onRetry: _reload,
          );
        }

        final state = snapshot.data ?? const _GateState.unauthenticated();

        return switch (state.status) {
          _GateStatus.unauthenticated =>
            SecureAuthPage(onAuthenticated: _reload),
          _GateStatus.employeePassword => EmployeePrimaryPasswordPage(
              name: state.employee!.name,
              onCompleted: _reload,
              onSignOut: _signOut,
            ),
          _GateStatus.employeeProfile => EmployeeProfileOnboardingPage(
              name: state.employee!.name,
              onSubmitted: _reload,
              onSignOut: _signOut,
            ),
          _GateStatus.employeeApprovalPending => EmployeeApprovalWaitingPage(
              name: state.employee!.name,
              onRefresh: _reload,
              onSignOut: _signOut,
            ),
          _GateStatus.employeeInviteInvalid => EmployeeInviteInvalidPage(
              onSignOut: _signOut,
            ),
          _GateStatus.needsCompany => CompanyProfileSetupPage(
              onCompleted: _reload,
              onDeferred: _reload,
              onSignOut: _signOut,
            ),
          _GateStatus.companyDeferred => DeferredCompanySetupPage(
              onResume: _resumeCompanySetup,
              onSignOut: _signOut,
            ),
          _GateStatus.needsAdminInitialSetup => AdminInitialSetupWizardPage(
              onCompleted: _reload,
              onSignOut: _signOut,
            ),
          _GateStatus.authenticated => widget.homeBuilder(_signOut),
        };
      },
    );
  }
}

class _LoadingScreen extends StatelessWidget {
  const _LoadingScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}

class _ErrorScreen extends StatelessWidget {
  const _ErrorScreen({
    required this.message,
    required this.onRetry,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48),
              const SizedBox(height: 12),
              const Text(
                '初期設定を読み込めませんでした',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Text(message, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('再試行'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _GateStatus {
  unauthenticated,
  employeePassword,
  employeeProfile,
  employeeApprovalPending,
  employeeInviteInvalid,
  needsCompany,
  companyDeferred,
  needsAdminInitialSetup,
  authenticated,
}

class _GateState {
  const _GateState._(this.status, [this.employee]);

  const _GateState.unauthenticated()
      : this._(_GateStatus.unauthenticated);
  const _GateState.employeePassword(EmployeeOnboardingState employee)
      : this._(_GateStatus.employeePassword, employee);
  const _GateState.employeeProfile(EmployeeOnboardingState employee)
      : this._(_GateStatus.employeeProfile, employee);
  const _GateState.employeeApprovalPending(EmployeeOnboardingState employee)
      : this._(_GateStatus.employeeApprovalPending, employee);
  const _GateState.employeeInviteInvalid(EmployeeOnboardingState employee)
      : this._(_GateStatus.employeeInviteInvalid, employee);
  const _GateState.needsCompany()
      : this._(_GateStatus.needsCompany);
  const _GateState.companyDeferred()
      : this._(_GateStatus.companyDeferred);
  const _GateState.needsAdminInitialSetup()
      : this._(_GateStatus.needsAdminInitialSetup);
  const _GateState.authenticated()
      : this._(_GateStatus.authenticated);

  final _GateStatus status;
  final EmployeeOnboardingState? employee;
}
