import 'dart:async';
import 'package:flutter/material.dart';
import 'scheduled_checkout_repository.dart';

/// Request a fresh server check after GPS clock-in, a native notification tap,
/// manual attendance correction or returning from the real checkout flow.
class ScheduledCheckoutGateController {
  ScheduledCheckoutGateController._();
  static final instance = ScheduledCheckoutGateController._();
  Future<void> Function()? _check;
  Future<bool> Function()? _back;
  Future<void> requestCheck() async { await _check?.call(); }
  Future<bool> handleSystemBack() async => await _back?.call() ?? false;
}

class ScheduledCheckoutGate extends StatefulWidget {
  const ScheduledCheckoutGate({super.key, required this.actorId, required this.load,
    required this.postpone, required this.checkoutBuilder, required this.child,
    this.managementBuilder, this.onReauthenticate, this.onServerChanged});
  final String actorId;
  final Future<ScheduledCheckoutState> Function() load;
  final Future<ScheduledCheckoutState> Function(ScheduledCheckoutTarget) postpone;
  final Widget Function(BuildContext, ScheduledCheckoutTarget) checkoutBuilder;
  final Widget Function(BuildContext, ScheduledCheckoutTarget)? managementBuilder;
  final Future<void> Function()? onReauthenticate;
  final Future<void> Function()? onServerChanged;
  final Widget child;
  @override State<ScheduledCheckoutGate> createState() => _ScheduledCheckoutGateState();
}
class _ScheduledCheckoutGateState extends State<ScheduledCheckoutGate> with WidgetsBindingObserver {
  ScheduledCheckoutState? _state;
  Object? _error;
  bool _busy = false;
  int _generation = 0;
  Timer? _timer;
  GlobalKey<NavigatorState> _navigator = GlobalKey<NavigatorState>();
  String? _navigationIdentity;
  bool _routeOpen = false;
  late final Future<void> Function() _boundCheck = _check;
  late final Future<bool> Function() _boundBack = _handleBack;
  ScheduledCheckoutTarget? get _target => _state?.due.isNotEmpty == true ? _state!.due.first : null;
  @override void initState() {
    super.initState();WidgetsBinding.instance.addObserver(this);
    ScheduledCheckoutGateController.instance._check = _boundCheck;
    ScheduledCheckoutGateController.instance._back = _boundBack;
    unawaited(_check());
  }
  @override void didUpdateWidget(ScheduledCheckoutGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.actorId != widget.actorId) {
      _generation++;_timer?.cancel();_state = null;_error = null;_busy = false;
      _navigationIdentity = null;_navigator = GlobalKey<NavigatorState>();_routeOpen = false;
      unawaited(_check());
    }
  }
  @override void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) { unawaited(_check()); }
  }
  @override void dispose() {
    _generation++;_timer?.cancel();WidgetsBinding.instance.removeObserver(this);
    if (ScheduledCheckoutGateController.instance._check == _boundCheck) { ScheduledCheckoutGateController.instance._check = null; }
    if (ScheduledCheckoutGateController.instance._back == _boundBack) { ScheduledCheckoutGateController.instance._back = null; }
    super.dispose();
  }
  Future<bool> _handleBack() async {
    if (_state != null && _error == null && _target == null) { return false; }
    final nav = _navigator.currentState;
    if (nav != null && nav.canPop()) { await nav.maybePop(); }
    return true;
  }
  void _scheduleCheck() {
    _timer?.cancel();
    final state = _state;
    if (state == null) { return; }
    final upcoming = state.targets.where((v) => !v.due).map((v) => v.reminderAt).toList()..sort();
    // The server comparison remains authoritative. Device timers only request
    // another check and never manufacture a due/complete result.
    var delay = const Duration(seconds: 30);
    if (upcoming.isNotEmpty) {
      final until = upcoming.first.difference(state.serverTime) + const Duration(seconds: 1);
      if (until < delay) { delay = until.isNegative ? const Duration(seconds: 1) : until; }
    }
    _timer = Timer(delay, () => unawaited(_check()));
  }
  void _accept(ScheduledCheckoutState result) {
    final due = result.due;
    final identity = due.isEmpty ? null : '${result.actorId}/${due.first.sourceId}';
    if (_navigationIdentity != identity) {
      _navigationIdentity = identity;_navigator = GlobalKey<NavigatorState>();_routeOpen = false;
    }
    _state = result;_error = null;
  }
  Future<void> _check() async {
    if (_busy) { return; }
    final generation = _generation;
    setState(() => _busy = true);
    try {
      final result = await widget.load();
      if (!mounted || generation != _generation) { return; }
      if (result.actorId != widget.actorId) { throw StateError('退勤対象の本人を確認できません。'); }
      setState(() => _accept(result));
    } catch (error) {
      if (mounted && generation == _generation) { setState(() => _error = error); }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _busy = false);_scheduleCheck();
      }
    }
  }
  Future<void> _postpone(ScheduledCheckoutTarget target) async {
    if (_busy) { return; }
    final generation = _generation;
    setState(() => _busy = true);
    try {
      final result = await widget.postpone(target);
      if (!mounted || generation != _generation) { return; }
      if (result.actorId != widget.actorId) { throw StateError('退勤対象の本人を確認できません。'); }
      setState(() => _accept(result));
      await _notifyServerChanged();
    } catch (error) {
      if (mounted && generation == _generation) { setState(() => _error = error); }
    } finally {
      if (mounted && generation == _generation) { setState(() => _busy = false);_scheduleCheck(); }
    }
  }
  Future<void> _open(ScheduledCheckoutTarget target, {bool management = false}) async {
    final builder = management ? widget.managementBuilder : widget.checkoutBuilder;
    if (_busy || _routeOpen || builder == null || (management && !target.canManageAttendance)) { return; }
    final nav = _navigator.currentState;
    if (nav == null) { return; }
    final generation = _generation;
    setState(() => _routeOpen = true);
    await nav.push<void>(MaterialPageRoute(builder: (context) => builder(context, target)));
    if (mounted && generation == _generation) {
      setState(() => _routeOpen = false);await _check();await _notifyServerChanged();
    }
  }
  Future<void> _notifyServerChanged() async {
    final generation = _generation;
    try { await widget.onServerChanged?.call(); } catch (_) {
      if (mounted && generation == _generation) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(const SnackBar(content: Text(
          '通知予定を同期できませんでした。アプリを開いた時に退勤状態を再確認します。')));
      }
    }
  }
  Widget _confirmation(ScheduledCheckoutTarget target) => Scaffold(
    appBar: AppBar(automaticallyImplyLeading: false, title: const Text('退勤の確認')),
    body: SafeArea(child: Center(child: SingleChildScrollView(padding: const EdgeInsets.all(20),
      child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 440), child: Column(
        mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [const Icon(Icons.notifications_active_outlined, size: 40),const SizedBox(height: 12),
          const Text('退勤予定時刻です。', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),Text('${target.workDate}の勤務を確認してください。'),
          const SizedBox(height: 20),FilledButton(onPressed: _busy ? null : () => _open(target), child: const Text('退勤して日報へ')),
          const SizedBox(height: 8),OutlinedButton(onPressed: _busy ? null : () => _postpone(target), child: const Text('まだ勤務中・30分後に再通知')),
          if (target.canManageAttendance && widget.managementBuilder != null)
            TextButton(onPressed: _busy ? null : () => _open(target, management: true), child: const Text('管理者の勤怠管理で確認')),
          const ExpansionTile(leading: Icon(Icons.help_outline), title: Text('この確認について'), children: [Text(
            '予定時刻だけで自動退勤はしません。本人が退勤を確定してから、日報・報告者サインの保存まで進みます。同じ現場の日報に自分が登録済みなら、重複入力は求めません。現場責任者のサイン待ちは別の通知で確認します。')]),
        ],
      )),
    ))),
  );
  Widget _status() => ColoredBox(color: Theme.of(context).scaffoldBackgroundColor,
    child: SafeArea(child: Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(
      mainAxisSize: MainAxisSize.min, children: [
        if (_busy) const CircularProgressIndicator(),
        if (_error != null) ...[const Text('退勤予定を確認できません。接続とログイン状態を確認してください。'),
          FilledButton(onPressed: _busy ? null : _check, child: const Text('もう一度確認')),
          if (widget.onReauthenticate != null) TextButton(onPressed: _busy ? null : widget.onReauthenticate, child: const Text('ログイン状態を確認'))],
      ],
    )))));
  @override Widget build(BuildContext context) {
    final target = _target;
    final blocked = _state == null || _error != null || target != null;
    return PopScope(canPop: !blocked, child: Stack(children: [
      Offstage(offstage: blocked, child: widget.child),
      if (target != null) Positioned.fill(child: Offstage(offstage: _error != null,
        child: HeroControllerScope.none(child: Navigator(
          key: _navigator, onGenerateRoute: (_) => MaterialPageRoute<void>(builder: (_) => _confirmation(target)),
        )))),
      if (_state == null || _error != null) Positioned.fill(child: _status()),
    ]));
  }
}
