import 'dart:async';

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'personal_vault_page.dart';
import 'personal_vault_repository.dart';

/// Candidate route. Root must expose it only after API/Storage deployment tests.
class PersonalVaultScreen extends StatefulWidget {
  const PersonalVaultScreen({super.key, required this.client});
  final SupabaseClient client;
  @override
  State<PersonalVaultScreen> createState() => _PersonalVaultScreenState();
}

class _PersonalVaultScreenState extends State<PersonalVaultScreen>
    with WidgetsBindingObserver {
  late PersonalVaultRepository _repository;
  StreamSubscription<AuthState>? _auth;
  Completer<void> _lifetime = Completer<void>();
  bool _retired = false;
  int _authGeneration = 0;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _bind();
  }
  void _bind() {
    final generation = ++_authGeneration;
    void retire() { if (generation == _authGeneration) { _retire(); } }
    _repository = PersonalVaultRepository(widget.client);
    final session = widget.client.auth.currentSession;
    _retired = session == null || session.isExpired;
    _auth = widget.client.auth.onAuthStateChange.listen((event) {
      if (event.event == AuthChangeEvent.signedOut ||
          event.session?.user.id != session?.user.id ||
          event.session?.accessToken != session?.accessToken) { retire(); }
    }, onError: (Object _) => retire(), onDone: retire);
  }
  void _retire() {
    if (!_lifetime.isCompleted) { _lifetime.complete(); }
    if (mounted && !_retired) { setState(() => _retired = true); }
  }
  @override
  void didUpdateWidget(covariant PersonalVaultScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.client, oldWidget.client)) {
      _retire();
      unawaited(_auth?.cancel());
      _lifetime = Completer<void>();
      _bind();
    }
  }
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) { _retire(); }
  }
  @override
  void dispose() {
    _authGeneration++;
    if (!_lifetime.isCompleted) { _lifetime.complete(); }
    unawaited(_auth?.cancel());
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
  Future<void> _open(PersonalVaultEntry entry, PersonalVaultAction action) async {
    if (_retired || !mounted) { return; }
    final lifetime = _lifetime;
    await _repository.withOwnPdf<void>(entry, (lease) async {
      if (!mounted || _retired || !identical(lifetime, _lifetime)) {
        lease.invalidate();
        return;
      }
      switch (action) {
        case PersonalVaultAction.preview:
          await Navigator.of(context).push<void>(MaterialPageRoute(builder: (_) =>
            PersonalVaultPdfSessionBoundary(lease: lease,
              child: Scaffold(appBar: AppBar(title: Text(entry.label)),
                body: PdfPreview(build: (_) => lease.readBytes(),
                  allowPrinting: false, allowSharing: false)))));
        case PersonalVaultAction.save:
          final bytes = await lease.readBytes();
          // No await between the final session check and the native handoff.
          // A share/print operation already handed to the OS cannot be recalled.
          await Printing.sharePdf(bytes: bytes, filename: 'SKO-personal-record.pdf');
        case PersonalVaultAction.print:
          await Printing.layoutPdf(onLayout: (_) => lease.readBytes());
      }
    }, invalidated: lifetime.future);
  }
  @override
  Widget build(BuildContext context) => _retired
      ? const Scaffold(body: Center(child: Text('安全のため書類を閉じました。画面を開き直してください。')))
      : PersonalVaultPage(key: ObjectKey(_lifetime), loadMine: _repository.loadMine,
          openOwnPdf: _open);
}

/// Disposes the preview child and removes only its own route on invalidation.
/// It must never pop an unrelated page which was pushed above the preview.
class PersonalVaultPdfSessionBoundary extends StatefulWidget {
  const PersonalVaultPdfSessionBoundary({super.key, required this.lease, required this.child});
  final PersonalVaultPdfLease lease;
  final Widget child;
  @override
  State<PersonalVaultPdfSessionBoundary> createState() => _PersonalVaultPdfSessionBoundaryState();
}
class _PersonalVaultPdfSessionBoundaryState extends State<PersonalVaultPdfSessionBoundary> {
  bool _valid = true;
  int _generation = 0;
  @override
  void initState() { super.initState(); _observe(); }
  @override
  void didUpdateWidget(covariant PersonalVaultPdfSessionBoundary oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.lease, widget.lease)) {
      oldWidget.lease.invalidate();
      _valid = true;
      _observe();
    }
  }
  void _observe() {
    final generation = ++_generation;
    unawaited(widget.lease.invalidated.then((_) {
      if (!mounted || generation != _generation) { return; }
      final route = ModalRoute.of(context);
      final navigator = Navigator.maybeOf(context);
      setState(() => _valid = false);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && generation == _generation && route != null &&
            route.isActive && navigator != null && navigator.mounted) {
          navigator.removeRoute(route);
        }
      });
    }));
  }
  @override
  void dispose() { _generation++; super.dispose(); }
  @override
  Widget build(BuildContext context) => _valid ? widget.child
      : const Scaffold(body: Center(child: Text('書類の表示を終了しました。')));
}
