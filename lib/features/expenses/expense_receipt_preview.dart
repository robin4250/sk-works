import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/supabase_backend.dart';

/// A signed URL is a temporary bearer credential, never an authorization cache.
class ExpenseReceiptPreview extends StatefulWidget {
  const ExpenseReceiptPreview({
    super.key,
    required this.objectPath,
    @visibleForTesting this.initialActor,
    @visibleForTesting this.actorChanges,
    @visibleForTesting this.urlLoader,
    @visibleForTesting this.imageBuilder,
    @visibleForTesting this.urlLifetime = const Duration(seconds: 300),
  });

  final String objectPath;
  final String? initialActor;
  final Stream<String?>? actorChanges;
  final Future<String> Function(String path)? urlLoader;
  final Widget Function(String url)? imageBuilder;
  final Duration urlLifetime;

  @override
  State<ExpenseReceiptPreview> createState() => _ExpenseReceiptPreviewState();
}

class _ExpenseReceiptPreviewState extends State<ExpenseReceiptPreview>
    with WidgetsBindingObserver {
  StreamSubscription<String?>? _subscription;
  Timer? _expiry;
  String? _actor;
  String? _url;
  bool _revoked = false;
  bool _suspended = false;
  bool _failed = false;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _suspended = lifecycle != null && lifecycle != AppLifecycleState.resumed;
    _actor = widget.initialActor ??
        (SupabaseBackend.isInitialized
            ? SupabaseBackend.client.auth.currentUser?.id
            : null);
    _revoked = _actor == null;
    final changes = widget.actorChanges ??
        (SupabaseBackend.isInitialized
            ? SupabaseBackend.client.auth.onAuthStateChange
                .map((event) => event.session?.user.id)
            : const Stream<String?>.empty());
    _subscription = changes.listen((actor) {
      if (_revoked || !mounted) return;
      if (actor != _actor) {
        _revoke();
      } else if (!_suspended) {
        // Token refresh can follow permission changes: request authorization again.
        _load();
      }
    }, onError: (Object error) => _revoke(), onDone: _revoke);
    if (!_revoked && !_suspended) _load();
  }

  void _clear() {
    _generation++;
    _expiry?.cancel();
    _expiry = null;
    final previous = _url;
    _url = null;
    if (previous != null) {
      // Remove this preview's decoded cache only; never flush other app images.
      PaintingBinding.instance.imageCache
          .evict(NetworkImage(previous), includeLive: true);
    }
  }

  void _revoke() {
    if (!mounted || _revoked) return;
    setState(() {
      _revoked = true;
      _clear();
    });
  }

  bool get _sameActor => widget.actorChanges != null ||
      (SupabaseBackend.isInitialized &&
          SupabaseBackend.client.auth.currentUser?.id == _actor);

  Future<void> _load() async {
    if (!mounted || _revoked || _suspended) return;
    if (!_sameActor) {
      _revoke();
      return;
    }
    setState(() {
      _clear();
      _failed = false;
    });
    final generation = _generation;
    // Start expiry before the request, so network latency never extends the lease.
    _expiry = Timer(widget.urlLifetime, () {
      if (!mounted || generation != _generation) return;
      setState(() {
        _clear();
        _failed = true;
      });
    });
    try {
      final url = await (widget.urlLoader?.call(widget.objectPath) ??
          SupabaseBackend.client.storage
              .from('expense-receipts')
              .createSignedUrl(widget.objectPath, 300));
      if (!mounted || generation != _generation || _revoked || _suspended) return;
      if (!_sameActor) {
        _revoke();
        return;
      }
      if (url.isEmpty) throw StateError('receipt_unavailable');
      setState(() => _url = url);
    } catch (_) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _clear();
        _failed = true;
      });
    }
  }

  @override
  void didUpdateWidget(covariant ExpenseReceiptPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.objectPath != oldWidget.objectPath) _load();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted || _revoked) return;
    if (state != AppLifecycleState.resumed) {
      setState(() {
        _suspended = true;
        _clear();
      });
    } else if (_suspended) {
      setState(() => _suspended = false);
      _load();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _subscription?.cancel();
    _clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_revoked || _suspended) {
      return const Text('本人確認が必要です。領収書を開き直してください。');
    }
    if (_failed) {
      return const Text('領収書の写真を取得できません。開き直して確認してください。');
    }
    final url = _url;
    if (url == null) {
      return const Padding(
        padding: EdgeInsets.all(12), child: CircularProgressIndicator());
    }
    return widget.imageBuilder?.call(url) ?? Image.network(
      url,
      height: 220,
      fit: BoxFit.contain,
      errorBuilder: (_, error, stack) =>
          const Text('領収書の写真を表示できません。'),
    );
  }
}
