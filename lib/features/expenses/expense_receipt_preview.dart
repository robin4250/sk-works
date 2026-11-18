import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../data/authenticated_storage_download.dart';
import '../../data/supabase_backend.dart';

/// Reloads the receipt with the current session when the preview becomes active.
class ExpenseReceiptPreview extends StatefulWidget {
  const ExpenseReceiptPreview({
    super.key,
    required this.objectPath,
    @visibleForTesting this.initialActor,
    @visibleForTesting this.actorChanges,
    @visibleForTesting this.bytesLoader,
    @visibleForTesting this.imageBuilder,
    @visibleForTesting this.previewLifetime = const Duration(seconds: 300),
  });

  final String objectPath;
  final String? initialActor;
  final Stream<String?>? actorChanges;
  final Future<Uint8List> Function(String path)? bytesLoader;
  final Widget Function(Uint8List bytes)? imageBuilder;
  final Duration previewLifetime;

  @override
  State<ExpenseReceiptPreview> createState() => _ExpenseReceiptPreviewState();
}

class _ExpenseReceiptPreviewState extends State<ExpenseReceiptPreview>
    with WidgetsBindingObserver {
  StreamSubscription<String?>? _subscription;
  Timer? _expiry;
  String? _actor;
  Uint8List? _bytes;
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
    final previous = _bytes;
    _bytes = null;
    if (previous != null) {
      // Remove this preview's decoded cache only; never flush other app images.
      PaintingBinding.instance.imageCache
          .evict(MemoryImage(previous), includeLive: true);
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
    _expiry = Timer(widget.previewLifetime, () {
      if (!mounted || generation != _generation) return;
      setState(() {
        _clear();
        _failed = true;
      });
    });
    try {
      final bytes = await (widget.bytesLoader?.call(widget.objectPath) ??
          downloadAuthenticatedStorageObject(
            SupabaseBackend.client,
            bucket: 'expense-receipts',
            path: widget.objectPath,
          ));
      if (!mounted || generation != _generation || _revoked || _suspended) return;
      if (!_sameActor) {
        _revoke();
        return;
      }
      if (bytes.isEmpty) throw StateError('receipt_unavailable');
      setState(() => _bytes = bytes);
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
    final bytes = _bytes;
    if (bytes == null) {
      return const Padding(
        padding: EdgeInsets.all(12), child: CircularProgressIndicator());
    }
    return widget.imageBuilder?.call(bytes) ?? Image.memory(
      bytes,
      height: 220,
      fit: BoxFit.contain,
      errorBuilder: (_, error, stack) =>
          const Text('領収書の写真を表示できません。'),
    );
  }
}
