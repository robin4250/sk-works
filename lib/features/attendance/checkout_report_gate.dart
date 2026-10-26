import 'dart:async';

import 'package:flutter/material.dart';

import '../daily_reports/daily_report_page.dart';
import '../daily_reports/shared_daily_report_repository.dart';
import '../../data/supabase_backend.dart';
import '../../widgets/sko_scroll_chrome.dart';
import 'attendance_protected_routes.dart';
import 'attendance_verification_page.dart';
import 'checkout_native_reminder_coordinator.dart';
import 'checkout_report_gate_repository.dart';
import 'group_checkout_dialog.dart';
import 'scheduled_checkout_gate.dart';
import 'scheduled_checkout_repository.dart';

/// Activation means onboarding/authentication completed, never permission to
/// bypass an outstanding server registration. Auth recovery stays outside it.
class CheckoutReportGateController extends ChangeNotifier {
  static final instance = CheckoutReportGateController();
  String? actorId;
  Future<void> Function()? reauthenticate;
  int revision = 0;
  Future<bool> Function()? handleSystemBack;
  Future<bool> Function(String sourceClockInId)? handleSavedSource;
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
  Future<bool> handleSavedCheckout(String sourceClockInId) async {
    if (actorId == null) return false;
    final handler = handleSavedSource;
    if (handler == null) throw StateError('日報の確認画面を準備できません。再読み込みしてください。');
    return handler(sourceClockInId);
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
    this.repository, this.controller, this.reportBuilder, this.beforeRegistration,
    this.sharedReportRepository, this.scheduledFlowBuilder, this.managementBuilder,
    this.onContinueSavedReport});
  final Widget child;
  final CheckoutReportGateRepository? repository;
  final CheckoutReportGateController? controller;
  @visibleForTesting final Widget Function(PendingCheckoutRegistration, VoidCallback)? reportBuilder;
  @visibleForTesting final Future<void> Function(BuildContext, PendingCheckoutRegistration)? beforeRegistration;
  @visibleForTesting final SharedDailyReportRepository? sharedReportRepository;
  @visibleForTesting final Widget Function(String actorId, Widget child)? scheduledFlowBuilder;
  @visibleForTesting final Widget Function(PendingCheckoutRegistration)? managementBuilder;
  @visibleForTesting final void Function(PendingCheckoutRegistration)? onContinueSavedReport;
  @override State<CheckoutReportGate> createState() => _CheckoutReportGateState();
}
class _CheckoutReportGateState extends State<CheckoutReportGate> with WidgetsBindingObserver {
  late final _controller = widget.controller ?? CheckoutReportGateController.instance;
  late final _repository = widget.repository ?? CheckoutReportGateRepository.maybeCreate();
  late final _sharedReports = widget.sharedReportRepository ??
      (widget.repository == null ? SharedDailyReportRepository.maybeCreate() : null);
  late final _scheduledRepository = SupabaseBackend.isInitialized
      ? ScheduledCheckoutRepository(SupabaseBackend.client) : null;
  List<PendingCheckoutRegistration> _pending = const [];
  List<PendingCheckoutRegistration> _registrations = const [];
  bool _checking = false;
  Object? _error;
  int _generation = 0;
  String? _actor;
  var _navigator = GlobalKey<NavigatorState>();
  String? _renderedIdentity;
  bool _canManageCurrent = false;
  bool _managementHold = false;
  String? _managementHoldText;
  final Set<String> _continuing = {};
  final Set<String> _continued = {};
  CheckoutNativeReminderCoordinator? _nativeReminders;
  int _nativeEpoch = 0;

  @override void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (_controller.actorId != null && _controller.actorId != _repository?.actorId) {
      _controller.deactivate(_controller.actorId!, _controller._activation);
    }
    _controller.handleSystemBack = _handleBack;
    _controller.handleSavedSource = _handleSavedSource;
    _controller.addListener(_changed);
    if (_controller.actorId != null) { _changed(); }
  }
  Future<bool> _handleBack() async {
    final blocked = _actor != null && (_checking || _error != null || _pending.isNotEmpty);
    if (!blocked) { return ScheduledCheckoutGateController.instance.handleSystemBack(); }
    if (!_checking && _error == null && _pending.isNotEmpty) {
      await _navigator.currentState?.maybePop();
    }
    return true;
  }
  void _changed() {
    if (!mounted) { return; }
    final actor = _controller.actorId;
    if (actor != _actor) {
      _continuing.clear();
      _continued.clear();
      _pending = const [];
      _registrations = const [];
      _canManageCurrent = false;
      _managementHold = false;
      _managementHoldText = null;
      _renderedIdentity = null;
      _navigator = GlobalKey<NavigatorState>();
      _actor = actor;
      unawaited(_replaceNativeActor(actor));
    }
    if (actor == null) {
      _generation++;
      setState(() { _checking = false; _error = null; });
      return;
    }
    unawaited(_read(actor));
  }
  bool _sameRegistration(PendingCheckoutRegistration before, PendingCheckoutRegistration after) =>
      before.identity == after.identity && before.companyId == after.companyId &&
      before.workerId == after.workerId && before.workDate == after.workDate &&
      before.siteId == after.siteId && before.routeId == after.routeId &&
      (before.reportId == null || before.reportId == after.reportId);

  Future<void> _continueSavedReport(PendingCheckoutRegistration target) async {
    final actor = _actor;
    if (actor == null || _controller.actorId != actor || _repository?.actorId != actor) return;
    final key = '$actor/${target.identity}';
    if (_continuing.contains(key) || _continued.contains(key)) return;
    _continuing.add(key);
    final expectedGeneration = _generation + 1;
    try {
      await _read(actor);
      PendingCheckoutRegistration? eligible() {
        if (!mounted || _actor != actor || _controller.actorId != actor ||
            _repository?.actorId != actor || _generation != expectedGeneration ||
            _checking || _error != null || _pending.isNotEmpty) { return null; }
        return _registrations.where((row) => _sameRegistration(target, row) &&
          !row.blocking && row.state == 'reporter_saved_waiting_supervisor' &&
          row.reportId != null).firstOrNull;
      }
      if (eligible() == null) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final saved = eligible();
        if (saved == null || _continued.contains(key)) return;
        final continuation = widget.onContinueSavedReport;
        final navigator = SkoScrollChromeController.navigatorKey.currentState;
        if (continuation == null && navigator == null) return;
        _continued.add(key);
        if (continuation != null) {
          continuation(saved);
        } else {
          unawaited(navigator!.push<void>(MaterialPageRoute(builder: (_) => DailyReportPage(
            initialReportId: saved.reportId, initialDate: saved.workDate,
            initialSiteId: saved.siteId, initialRouteAssignmentId: saved.routeId,
            vehicleClockInId: saved.sourceClockInId,
            groupClockInAnchorId: saved.sourceClockInId))));
        }
      });
    } finally {
      _continuing.remove(key);
    }
  }
  Future<void> _read(String actor) async {
    final generation = ++_generation;
    setState(() { _checking = true; _error = null; _canManageCurrent = false; });
    try {
      final repository = _repository;
      if (repository == null || repository.actorId != actor) { throw StateError('ログイン状態を確認してください。'); }
      var rows = await repository.readPending();
      if (!mounted || generation != _generation || _controller.actorId != actor || repository.actorId != actor) return;
      final direct = rows.where((row) => row.blocking && row.choiceAvailable &&
        !row.reportStarted && row.state != 'report_choice_required').firstOrNull;
      if (direct != null) {
        // A single-member automatic start is persisted before displaying the
        // form. A later roster addition cannot turn it into checkout-only.
        await repository.choose(direct, createReport: true);
        if (!mounted || generation != _generation || _controller.actorId != actor || repository.actorId != actor) return;
        rows = await repository.readPending();
      }
      if (!mounted || generation != _generation || _controller.actorId != actor || repository.actorId != actor) { return; }
      final pending = rows.where((row) => row.blocking).toList();
      var canManage = false;
      var managementHold = false;
      String? managementHoldText;
      if (pending.isNotEmpty && pending.first.state != 'report_choice_required' && _sharedReports != null) {
        final context = await _sharedReports.loadForSource(pending.first.sourceClockInId);
        if (context.actorId != actor || context.companyId != pending.first.companyId ||
            context.workerId != pending.first.workerId || context.workDate != pending.first.workDate) {
          throw StateError('日報の勤務原本を確認できません。');
        }
        canManage = context.canManageAttendance;
        managementHold = context.isManagementHold;
        if (managementHold) { managementHoldText = context.managementHoldMessage; }
      }
      if (!mounted || generation != _generation || _controller.actorId != actor || repository.actorId != actor) { return; }
      final identity = pending.isEmpty ? null : '${pending.first.identity}/${pending.first.state}/hold:$managementHold';
      setState(() {
        if (identity != _renderedIdentity) {
          _navigator = GlobalKey<NavigatorState>();
          _renderedIdentity = identity;
        }
        _pending = pending;
        _registrations = rows;
        _canManageCurrent = canManage;
        _managementHold = managementHold;
        _managementHoldText = managementHoldText;
        _checking = false;
      });
    } catch (error) {
      if (!mounted || generation != _generation || _controller.actorId != actor) { return; }
      setState(() { _error = error; _checking = false; });
    }
  }
  Future<bool> _handleSavedSource(String sourceClockInId) async {
    final actor = _controller.actorId;
    if (actor == null) return false;
    await _read(actor);
    if (!mounted || _controller.actorId != actor || _actor != actor || _checking || _error != null) return true;
    final enabled = _repository?.enforcementEnabled;
    if (enabled == false) return false;
    if (enabled != true) {
      setState(() => _error = StateError('日報登録の提供状態を確認できません。'));
      return true;
    }
    return _pending.isNotEmpty ||
        _registrations.any((row) => row.sourceClockInId == sourceClockInId);
  }
  Future<void> _replaceNativeActor(String? actor) async {
    final epoch = ++_nativeEpoch;
    final previous = _nativeReminders;
    _nativeReminders = null;
    await previous?.dispose();
    final repository = _scheduledRepository;
    if (!mounted || epoch != _nativeEpoch || actor == null || repository == null ||
        _controller.actorId != actor || repository.actorId != actor || widget.repository != null) { return; }
    final coordinator = CheckoutNativeReminderCoordinator(
      currentActorId: () => repository.actorId,
      currentSessionIdentity: () => repository.currentSessionIdentity,
      sessionChanges: repository.client.auth.onAuthStateChange.map(
        (event) => ScheduledCheckoutRepository.sessionIdentityOf(event.session)),
      loadPlan: () async {
        final identity = repository.currentSessionIdentity;
        if (identity == null || repository.actorId != actor || _controller.actorId != actor) {
          throw StateError('通知予定の本人を確認できません。');
        }
        final plan = await repository.loadNotificationPlan();
        if (plan.actorId != actor || repository.actorId != actor ||
            repository.currentSessionIdentity != identity || _controller.actorId != actor) {
          throw StateError('通知予定のログイン状態が変わりました。');
        }
        return NativeCheckoutDevicePlan(actorId: actor, sessionIdentity: identity,
          serverTime: plan.state.serverTime,
          notifications: [for (final item in plan.plannedNotifications)
            NativeCheckoutDeviceNotification(sourceId: item.sourceId, fireAt: item.fireAt)],
          hasDueConfirmation: plan.state.due.isNotEmpty);
      },
      requestGateCheck: (_) async {
        final identity = repository.currentSessionIdentity;
        if (identity == null || repository.actorId != actor || _controller.actorId != actor) return false;
        final fresh = await repository.read();
        if (!mounted || fresh.actorId != actor || repository.actorId != actor ||
            repository.currentSessionIdentity != identity || _controller.actorId != actor) { return false; }
        // A native cue only requests authoritative reads. It is never a route
        // target or a local completion flag; absent sources are stale cues.
        _controller.requestCheck();
        await ScheduledCheckoutGateController.instance.requestCheck();
        return repository.actorId == actor && repository.currentSessionIdentity == identity;
      });
    _nativeReminders = coordinator;
    await coordinator.init();
  }
  @override void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _controller.actorId != null) {
      _changed();
      unawaited(_nativeReminders?.refresh());
    }
  }
  @override void dispose() {
    _generation++;
    _nativeEpoch++;
    unawaited(_nativeReminders?.dispose());
    WidgetsBinding.instance.removeObserver(this);
    _controller.removeListener(_changed);
    if (_controller.handleSystemBack == _handleBack) { _controller.handleSystemBack = null; }
    if (_controller.handleSavedSource == _handleSavedSource) { _controller.handleSavedSource = null; }
    super.dispose();
  }
  Future<void> _openManagement() async {
    if (!_canManageCurrent || _checking || _error != null || _pending.isEmpty) return;
    final target = _pending.first;
    final actor = _actor;
    await _navigator.currentState?.push<void>(MaterialPageRoute(builder: (_) =>
      widget.managementBuilder?.call(target) ?? attendanceManagementDestination(
        initialWorkerId: target.workerId, initialDate: target.workDate,
        restrictedRecovery: true)));
    if (mounted && actor != null && _actor == actor && _controller.actorId == actor) {
      _changed();
      await ScheduledCheckoutGateController.instance.requestCheck();
      unawaited(CheckoutNativeReminderCoordinator.refreshCurrent());
    }
  }
  Widget _scheduledFlow(Widget child) {
    final actor = _actor;
    if (actor == null) return child;
    if (widget.scheduledFlowBuilder != null) return widget.scheduledFlowBuilder!(actor, child);
    // Legacy injected report-only fixtures do not stand in for a production
    // schedule capability. Combined-flow tests inject the scheduled wrapper.
    if (widget.repository != null) return child;
    Future<ScheduledCheckoutState> load() async {
      final repository = _scheduledRepository;
      if (repository == null || repository.actorId != actor) {
        throw StateError('退勤予定の本人を確認できません。');
      }
      return repository.read();
    }
    return ScheduledCheckoutGate(key: ValueKey('scheduled-checkout/$actor'),
      actorId: actor, load: load,
      postpone: (target) async {
        final repository = _scheduledRepository;
        if (repository == null || repository.actorId != actor) {
          throw StateError('退勤予定の本人を確認できません。');
        }
        return repository.postpone(target);
      },
      checkoutBuilder: (_, target) => AttendanceVerificationPage(
        initialEventType: 'clock_out', initialSourceClockInId: target.sourceId,
        scheduledCheckoutTarget: target),
      managementBuilder: (_, target) => attendanceManagementDestination(
        initialWorkerId: target.workerId, initialDate: DateTime.parse(target.workDate),
        restrictedRecovery: true),
      onReauthenticate: _controller.reauthenticate,
      onServerChanged: CheckoutNativeReminderCoordinator.refreshCurrent,
      child: child);
  }
  Widget _status() => Scaffold(body: SafeArea(child: Center(child: Padding(
    padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [
      if (_checking) const CircularProgressIndicator(),
      const SizedBox(height: 12),
      Text(_managementHold ? (_managementHoldText ?? '勤怠管理での確認が必要です。') :
        _error == null && _pending.isNotEmpty && _pending.first.state == 'source_conflict'
          ? '勤務原本を確認できないため日報を登録できません。管理者へ確認してください。'
          : _error == null ? '日報の登録状況を確認しています' : '日報の登録状況を確認できません。保存内容は保持しています。'),
      if (_managementHold || _error != null || (!_checking && _pending.isNotEmpty && _pending.first.state == 'source_conflict')) ...[
        const SizedBox(height: 12),
        if (!_managementHold) FilledButton(onPressed: _changed, child: const Text('再試行')),
        TextButton(onPressed: _controller.reauthenticate, child: const Text('ログインし直す')),
        if (_canManageCurrent && _error == null)
          OutlinedButton(onPressed: _openManagement, child: const Text('管理者の勤怠管理で確認')),
      ],
    ]),
  ))));
  @override Widget build(BuildContext context) {
    final blocked = _actor != null && (_checking || _error != null || _pending.isNotEmpty);
    return Stack(fit: StackFit.expand, children: [
      Offstage(offstage: blocked, child: IgnorePointer(ignoring: blocked, child: _scheduledFlow(widget.child))),
      if (blocked) Positioned.fill(child: PopScope(canPop: false, child: Stack(children: [
        if (_pending.isNotEmpty) Positioned.fill(child: NavigatorPopHandler<Object?>(
          onPopWithResult: (_) => _navigator.currentState?.maybePop(),
          // The ordinary Navigator remains mounted offstage. Its inherited
          // MaterialApp HeroController must not attach to this second Navigator.
          child: HeroControllerScope.none(child: Navigator(key: _navigator, onGenerateRoute: (_) {
            final target = _pending.first;
            return MaterialPageRoute<void>(settings: RouteSettings(name: target.identity), builder: (_) =>
              target.state == 'source_conflict' || _managementHold ? _status() :
              target.state == 'report_choice_required' ? _CheckoutReportChoice(
                target: target, onChoose: (createReport) async {
                  await _repository!.choose(target, createReport: createReport);
                  if (mounted) _changed();
                }) :
              _BeforeReportRegistration(
                key: ValueKey('$_actor/${target.identity}/group'),
                before: target.siteId != null && target.routeId == null &&
                    (widget.beforeRegistration != null || widget.reportBuilder == null)
                  ? (context) => widget.beforeRegistration?.call(context, target) ??
                      showGroupCheckoutAfterPersonalSave(context,
                        anchorId: target.sourceClockInId, workDate: target.workDate)
                  : null,
                child: widget.reportBuilder?.call(target, () => unawaited(_continueSavedReport(target))) ?? DailyReportPage(
                key: ValueKey('$_actor/${target.identity}'),
                initialDate: target.workDate, initialSiteId: target.siteId,
                initialRouteAssignmentId: target.routeId, initialReportId: target.reportId,
                vehicleClockInId: target.sourceClockInId, groupClockInAnchorId: target.sourceClockInId,
                restrictedReporterRegistration: true, registrationActorId: _actor,
                registrationCompanyId: target.companyId, registrationWorkerId: target.workerId,
                onManageRegistration: _openManagement,
                onRegistrationSaved: () => unawaited(_continueSavedReport(target)))));
          })),
        )),
        if (_pending.isEmpty || _checking || _error != null) Positioned.fill(child: _status()),
      ]))),
    ]);
  }
}

/// The existing optional group checkout belongs to the restricted Navigator:
/// members can finish checkout before the reporter signs the shared report,
/// while ordinary pages remain inaccessible. Restart safely reloads candidates
/// from the saved personal anchor instead of repeating the personal checkout.
class _BeforeReportRegistration extends StatefulWidget {
  const _BeforeReportRegistration({super.key, required this.before, required this.child});
  final Future<void> Function(BuildContext)? before;
  final Widget child;
  @override State<_BeforeReportRegistration> createState() => _BeforeReportRegistrationState();
}
class _BeforeReportRegistrationState extends State<_BeforeReportRegistration> {
  bool _ready = false;
  @override void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) { return; }
      await widget.before?.call(context);
      if (mounted) { setState(() => _ready = true); }
    });
  }
  @override Widget build(BuildContext context) => widget.before == null || _ready
      ? widget.child
      : const PopScope(canPop: false, child: Scaffold(body: Center(child: CircularProgressIndicator())));
}

/// The choice is saved on the server before releasing or starting the gate.
class _CheckoutReportChoice extends StatefulWidget {
  const _CheckoutReportChoice({required this.target, required this.onChoose});
  final PendingCheckoutRegistration target;
  final Future<void> Function(bool createReport) onChoose;
  @override State<_CheckoutReportChoice> createState() => _CheckoutReportChoiceState();
}
class _CheckoutReportChoiceState extends State<_CheckoutReportChoice> {
  bool _saving = false;
  bool? _pendingChoice;
  Object? _error;
  Future<void> _choose(bool createReport) async {
    if (_saving) return;
    setState(() { _saving = true; _pendingChoice = createReport; _error = null; });
    try {
      await widget.onChoose(createReport);
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
  @override Widget build(BuildContext context) => PopScope(canPop: false,
    child: Scaffold(appBar: AppBar(title: const Text('退勤後の日報'), automaticallyImplyLeading: false),
      body: SafeArea(child: Center(child: Padding(padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('${widget.target.workDate.month}/${widget.target.workDate.day} 現場メンバー ${widget.target.memberCount}人'),
            const SizedBox(height: 12),
            const Text('退勤は記録済みです。日報を作成しますか？'),
            const SizedBox(height: 16),
            FilledButton(onPressed: _saving || (_error != null && _pendingChoice == false) ? null : () => _choose(true),
              child: const Text('日報を作成する')),
            const SizedBox(height: 8),
            OutlinedButton(onPressed: _saving || (_error != null && _pendingChoice == true) ? null : () => _choose(false),
              child: const Text('退勤のみ')),
            const SizedBox(height: 12),
            const Text('退勤のみを選んでも、出勤表から後で日報を作成できます。'),
            if (_saving) const Center(child: CircularProgressIndicator()),
            if (_error != null) const Text('選択結果を確認できません。同じボタンでもう一度確認してください。'),
          ]))))));
}
