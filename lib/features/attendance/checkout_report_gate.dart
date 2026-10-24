import 'dart:async';

import 'package:flutter/material.dart';

import '../daily_reports/daily_report_page.dart';
import 'checkout_report_gate_repository.dart';

/// Activation means onboarding/authentication completed, never permission to
/// bypass an outstanding server registration. Auth recovery stays outside it.
class CheckoutReportGateController extends ChangeNotifier {
  static final instance = CheckoutReportGateController();
  String? actorId;
  Future<void> Function()? reauthenticate;
  int revision = 0;
  Future<bool> Function()? handleSystemBack;
  int _activation = 0;
  int activate(String actor, Future<void> Function() recovery) {
    actorId = actor;
    reauthenticate = recovery;
    revision++;
    _activation++;
    notifyListeners();
    return _activation;
  }
  void deactivate(String actor, int activation) {
    if (actorId != actor || activation != _activation) { return; }
    actorId = null;
    reauthenticate = null;
    revision++;
    notifyListeners();
  }
  bool requestCheck() {
    if (actorId == null) { return false; }
    revision++;
    notifyListeners();
    return true;
  }
}

/// Must be mounted before MaterialApp registers its own pop observer. A
/// builder-only PopScope has no parent ModalRoute and cannot redirect a system
/// back event from the hidden normal Navigator to the dedicated report flow.
class CheckoutReportBackBoundary extends StatefulWidget {
  const CheckoutReportBackBoundary({super.key, required this.child, this.controller});
  final Widget child;
  final CheckoutReportGateController? controller;
  @override State<CheckoutReportBackBoundary> createState() => _CheckoutReportBackBoundaryState();
}
class _CheckoutReportBackBoundaryState extends State<CheckoutReportBackBoundary> with WidgetsBindingObserver {
  @override void initState() { super.initState(); WidgetsBinding.instance.addObserver(this); }
  @override Future<bool> didPopRoute() async =>
      await (widget.controller ?? CheckoutReportGateController.instance).handleSystemBack?.call() ?? false;
  @override void dispose() { WidgetsBinding.instance.removeObserver(this); super.dispose(); }
  @override Widget build(BuildContext context) => widget.child;
}

class CheckoutReportGateActivation extends StatefulWidget {
  const CheckoutReportGateActivation({super.key, required this.actorId,
    required this.onReauthenticate, required this.child});
  final String actorId;
  final Future<void> Function() onReauthenticate;
  final Widget child;
  @override State<CheckoutReportGateActivation> createState() => _CheckoutReportGateActivationState();
}
class _CheckoutReportGateActivationState extends State<CheckoutReportGateActivation> {
  int? _activation;
  @override void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _activation = CheckoutReportGateController.instance.activate(widget.actorId, widget.onReauthenticate);
        setState(() {});
      }
    });
  }
  // Route replacement is not proof of sign-out. Keep activation when this
  // home subtree is replaced; otherwise a deep link could dismiss the gate.
  @override void dispose() { super.dispose(); }
  @override Widget build(BuildContext context) => Stack(fit: StackFit.expand, children: [
    Offstage(offstage: _activation == null, child: widget.child),
    if (_activation == null) const ColoredBox(color: Colors.white, child: Center(child: CircularProgressIndicator())),
  ]);
}

/// Placed above the ordinary Navigator so pushed pages, tabs and deep links
/// remain inaccessible while authoritative registration is pending/unknown.
/// The hidden Navigator is retained to preserve its state and unsaved drafts.
class CheckoutReportGate extends StatefulWidget {
  const CheckoutReportGate({super.key, required this.child,
    this.repository, this.controller, this.reportBuilder});
  final Widget child;
  final CheckoutReportGateRepository? repository;
  final CheckoutReportGateController? controller;
  @visibleForTesting final Widget Function(PendingCheckoutRegistration, VoidCallback)? reportBuilder;
  @override State<CheckoutReportGate> createState() => _CheckoutReportGateState();
}
class _CheckoutReportGateState extends State<CheckoutReportGate> with WidgetsBindingObserver {
  late final _controller = widget.controller ?? CheckoutReportGateController.instance;
  late final _repository = widget.repository ?? CheckoutReportGateRepository.maybeCreate();
  List<PendingCheckoutRegistration> _pending = const [];
  bool _checking = false;
  Object? _error;
  int _generation = 0;
  String? _actor;
  var _navigator = GlobalKey<NavigatorState>();
  String? _renderedIdentity;

  @override void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (_controller.actorId != null && _controller.actorId != _repository?.actorId) {
      _controller.deactivate(_controller.actorId!, _controller._activation);
    }
    _controller.handleSystemBack = _handleBack;
    _controller.addListener(_changed);
    if (_controller.actorId != null) { _changed(); }
  }
  Future<bool> _handleBack() async {
    final blocked = _actor != null && (_checking || _error != null || _pending.isNotEmpty);
    if (!blocked) { return false; }
    if (!_checking && _error == null && _pending.isNotEmpty) {
      await _navigator.currentState?.maybePop();
    }
    return true;
  }
  void _changed() {
    if (!mounted) { return; }
    final actor = _controller.actorId;
    if (actor != _actor) {
      _pending = const [];
      _renderedIdentity = null;
      _navigator = GlobalKey<NavigatorState>();
      _actor = actor;
    }
    if (actor == null) {
      _generation++;
      setState(() { _checking = false; _error = null; });
      return;
    }
    unawaited(_read(actor));
  }
  Future<void> _read(String actor) async {
    final generation = ++_generation;
    setState(() { _checking = true; _error = null; });
    try {
      final repository = _repository;
      if (repository == null || repository.actorId != actor) { throw StateError('ログイン状態を確認してください。'); }
      final rows = await repository.readPending();
      if (!mounted || generation != _generation || _controller.actorId != actor || repository.actorId != actor) { return; }
      final pending = rows.where((row) => row.blocking).toList();
      final identity = pending.isEmpty ? null : pending.first.identity;
      setState(() {
        if (identity != _renderedIdentity) {
          _navigator = GlobalKey<NavigatorState>();
          _renderedIdentity = identity;
        }
        _pending = pending;
        _checking = false;
      });
    } catch (error) {
      if (!mounted || generation != _generation || _controller.actorId != actor) { return; }
      setState(() { _error = error; _checking = false; });
    }
  }
  @override void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _controller.actorId != null) { _changed(); }
  }
  @override void dispose() {
    _generation++;
    WidgetsBinding.instance.removeObserver(this);
    _controller.removeListener(_changed);
    if (_controller.handleSystemBack == _handleBack) { _controller.handleSystemBack = null; }
    super.dispose();
  }
  Widget _status() => Scaffold(body: SafeArea(child: Center(child: Padding(
    padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [
      if (_checking) const CircularProgressIndicator(),
      const SizedBox(height: 12),
      Text(_error == null && _pending.isNotEmpty && _pending.first.state == 'source_conflict'
          ? '勤務原本を確認できないため日報を登録できません。管理者へ確認してください。'
          : _error == null ? '日報の登録状況を確認しています' : '日報の登録状況を確認できません。保存内容は保持しています。'),
      if (_error != null || (!_checking && _pending.isNotEmpty && _pending.first.state == 'source_conflict')) ...[
        const SizedBox(height: 12),
        FilledButton(onPressed: _changed, child: const Text('再試行')),
        TextButton(onPressed: _controller.reauthenticate, child: const Text('ログインし直す')),
      ],
    ]),
  ))));
  @override Widget build(BuildContext context) {
    final blocked = _actor != null && (_checking || _error != null || _pending.isNotEmpty);
    return Stack(fit: StackFit.expand, children: [
      Offstage(offstage: blocked, child: IgnorePointer(ignoring: blocked, child: widget.child)),
      if (blocked) Positioned.fill(child: PopScope(canPop: false, child: Stack(children: [
        if (_pending.isNotEmpty && _pending.first.state != 'source_conflict') Positioned.fill(child: NavigatorPopHandler<Object?>(
          onPopWithResult: (_) => _navigator.currentState?.maybePop(),
          // The ordinary Navigator remains mounted offstage. Its inherited
          // MaterialApp HeroController must not attach to this second Navigator.
          child: HeroControllerScope.none(child: Navigator(key: _navigator, onGenerateRoute: (_) {
            final target = _pending.first;
            return MaterialPageRoute<void>(settings: RouteSettings(name: target.identity), builder: (_) =>
              widget.reportBuilder?.call(target, _changed) ?? DailyReportPage(
                key: ValueKey('$_actor/${target.identity}'),
                initialDate: target.workDate, initialSiteId: target.siteId,
                initialRouteAssignmentId: target.routeId, initialReportId: target.reportId,
                vehicleClockInId: target.sourceClockInId, groupClockInAnchorId: target.sourceClockInId,
                restrictedReporterRegistration: true, registrationActorId: _actor,
                registrationCompanyId: target.companyId, registrationWorkerId: target.workerId,
                onRegistrationSaved: _changed));
          })),
        )),
        if (_pending.isEmpty || _checking || _error != null || _pending.first.state == 'source_conflict') Positioned.fill(child: _status()),
      ]))),
    ]);
  }
}
