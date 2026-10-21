import 'dart:async';

import 'package:flutter/material.dart';

/// An entry appears only for an actual pending row marked reviewable by the
/// existing server contract. This does not grant approval authority locally.
class QualificationPhotoReviewEntry extends StatefulWidget {
  const QualificationPhotoReviewEntry({
    super.key,
    required this.loadPending,
    required this.scope,
    required this.scopeChanges,
    required this.onOpen,
  });

  final Future<List<Map<String, dynamic>>> Function() loadPending;
  final Object? Function() scope;
  final Stream<Object?> scopeChanges;
  final Future<void> Function() onOpen;

  @override
  State<QualificationPhotoReviewEntry> createState() => _EntryState();
}

class _EntryState extends State<QualificationPhotoReviewEntry>
    with WidgetsBindingObserver {
  StreamSubscription<Object?>? _subscription;
  Object? _scope;
  int _generation = 0;
  int _count = 0;
  bool _busy = false;
  bool _foreground = true;

  @override
  void initState() {
    super.initState();
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _foreground = lifecycle == null || lifecycle == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
    _subscription = widget.scopeChanges.listen(
      (_) => _invalidate(),
      onError: (Object _, StackTrace __) => _invalidate(),
      onDone: _invalidate,
    );
    unawaited(_load());
  }

  void _invalidate() {
    _generation++;
    _scope = null;
    if (mounted) {
      setState(() => _count = 0);
    }
  }

  bool _current(Object scope, int generation) =>
      mounted && _foreground && generation == _generation &&
      _scope == scope && widget.scope() == scope;

  Future<void> _load() async {
    _invalidate();
    final scope = widget.scope();
    if (!_foreground || scope == null) return;
    final generation = _generation;
    _scope = scope;
    try {
      final rows = await widget.loadPending();
      if (!_current(scope, generation)) return;
      setState(() {
        _count = rows.where((row) =>
            row['status'] == 'pending' && row['can_review'] == true).length;
      });
    } catch (_) {
      if (_current(scope, generation)) _invalidate();
    }
  }

  Future<void> _open() async {
    final scope = _scope;
    final generation = _generation;
    if (_busy || _count == 0 || scope == null ||
        !_current(scope, generation)) {
      _invalidate();
      return;
    }
    setState(() => _busy = true);
    try {
      await widget.onOpen();
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        await _load();
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _invalidate();
    if (_foreground) unawaited(_load());
  }

  @override
  void dispose() {
    _generation++;
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_subscription?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _count == 0 || !_foreground ||
      _scope == null || widget.scope() != _scope
      ? const SizedBox.shrink()
      : Card(
          child: ListTile(
            leading: const Icon(Icons.fact_check_outlined),
            title: const Text('資格写真の承認待ち'),
            subtitle: Text('承認できる申請 $_count件'),
            trailing: const Icon(Icons.chevron_right),
            onTap: _busy ? null : _open,
          ),
        );
}
