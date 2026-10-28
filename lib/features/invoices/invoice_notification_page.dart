import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/supabase_backend.dart';
import '../../domain/invoice_engine.dart';
import '../../international/language_controller.dart';
import '../notifications/notification_preview_route_scope.dart';
import 'invoice_cloud_page.dart';
import 'invoice_cloud_repository.dart';
import 'invoice_list_card.dart';

/// Notification previews never initialize approval data via a legacy lookup.
InvoicePreviewPage invoiceNotificationPreview(InvoiceCalculationResult invoice, {String? notificationId}) =>
    InvoicePreviewPage(invoice: invoice, allowLegacyApprovalInitialization: false,
      approvalFromNotification: notificationId != null && RegExp(r'^[0-9a-fA-F]{8}-(?:[0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$').hasMatch(notificationId),
      approvalNotificationId: notificationId);

abstract interface class InvoiceNoticeSource {
  String? get actor;
  Stream<String?> get actorChanges;
  Future<List<InvoiceCalculationResult>> load();
}

/// Uses only the existing saved-invoice read path, without refreshing invoices.
class SupabaseInvoiceNoticeSource implements InvoiceNoticeSource {
  SupabaseInvoiceNoticeSource(this.client, this.repository);
  final SupabaseClient client;
  final InvoiceCloudRepository repository;
  @override
  String? get actor => sessionKey(client.auth.currentSession);
  @override
  Stream<String?> get actorChanges =>
      client.auth.onAuthStateChange.map((state) => sessionKey(state.session));

  /// UI invalidation only; the server verifies the session and permissions.
  @visibleForTesting
  static String? sessionKey(Session? session) {
    if (session == null) return null;
    return sessionKeyForToken(session.accessToken, session.user.id);
  }

  @visibleForTesting
  static String? sessionKeyForToken(String token, String userId) {
    try {
      final parts = token.split('.');
      if (parts.length != 3) return null;
      final claims = jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))));
      final sid = claims is Map ? claims['session_id'] : null;
      if (claims is! Map || claims['sub'] != userId || sid is! String ||
          !RegExp(r'^[0-9a-fA-F]{8}-(?:[0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$').hasMatch(sid)) {
        return null;
      }
      return '$userId/$sid';
    } catch (_) {
      return null;
    }
  }
  @override
  Future<List<InvoiceCalculationResult>> load() => repository.loadAll();
}

class InvoiceNotificationPage extends StatefulWidget {
  const InvoiceNotificationPage({
    super.key,
    required this.invoiceId,
    this.notificationId,
    this.source,
    this.previewBuilder,
  });
  final String invoiceId;
  final String? notificationId;
  final InvoiceNoticeSource? source;
  @visibleForTesting
  final Widget Function(InvoiceCalculationResult)? previewBuilder;
  @override
  State<InvoiceNotificationPage> createState() =>
      _InvoiceNotificationPageState();
}

class _InvoiceNotificationPageState extends State<InvoiceNotificationPage>
    with WidgetsBindingObserver {
  InvoiceNoticeSource? _source;
  StreamSubscription<String?>? _subscription;
  String? _actor;
  InvoiceCalculationResult? _target;
  bool _active = true, _changed = false, _loading = true, _preview = false;
  int _generation = 0;

  String _text(String ja, String en) =>
      SkoLanguageController.isEnglish ? en : ja;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _active = lifecycle == null || lifecycle == AppLifecycleState.resumed;
    _source = widget.source;
    if (_source == null && SupabaseBackend.isInitialized) {
      final repository = InvoiceCloudRepository.maybeCreate();
      if (repository != null) {
        _source = SupabaseInvoiceNoticeSource(
          SupabaseBackend.client,
          repository,
        );
      }
    }
    _actor = _source?.actor;
    _subscription = _source?.actorChanges.listen((actor) {
      if (actor != _actor) _invalidate();
    }, onError: (Object error) => _invalidate());
    _load();
  }

  @override
  void didUpdateWidget(covariant InvoiceNotificationPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.source != widget.source ||
        oldWidget.invoiceId != widget.invoiceId ||
        oldWidget.notificationId != widget.notificationId) {
      _invalidate();
    }
  }

  void _invalidate() {
    _changed = true;
    _generation++;
    if (!mounted) return;
    setState(() {
      _target = null;
      _preview = false;
      _loading = false;
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _active = state == AppLifecycleState.resumed;
    _generation++;
    if (_source?.actor != _actor) _invalidate();
    if (!_active) {
      setState(() {
        _target = null;
        _preview = false;
        _loading = false;
      });
    } else if (!_changed) {
      _load();
    }
  }

  bool _current(int generation) =>
      mounted &&
      _active &&
      !_changed &&
      generation == _generation &&
      _actor != null &&
      _source?.actor == _actor;

  Future<void> _load() async {
    final generation = ++_generation;
    if (_source?.actor != _actor) _invalidate();
    if (!mounted || !_active || _changed) return;
    setState(() {
      _target = null;
      _preview = false;
      _loading = true;
    });
    try {
      final source = _source;
      if (source == null ||
          _actor == null ||
          !RegExp(r'^[0-9a-fA-F]{8}-(?:[0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$')
              .hasMatch(widget.invoiceId)) {
        throw const FormatException('Unavailable target');
      }
      final rows = await source.load();
      if (_source?.actor != _actor) _invalidate();
      if (!_current(generation)) return;
      final targets = rows
          .where((row) => row.invoiceId == widget.invoiceId)
          .toList();
      if (targets.length != 1) {
        throw const FormatException('Unavailable target');
      }
      setState(() {
        _target = targets.single;
        _loading = false;
      });
    } catch (_) {
      if (_source?.actor != _actor) _invalidate();
      if (!mounted || !_active || _changed || generation != _generation) {
        return;
      }
      setState(() {
        _target = null;
        _loading = false;
      });
    }
  }

  bool _canPreview(InvoiceCalculationResult invoice) =>
      !invoice.amountPending && invoice.outputReadinessError == null;

  void _open() {
    if (_source?.actor != _actor) _invalidate();
    if (!_current(_generation) || _target == null || !_canPreview(_target!)) {
      return;
    }
    setState(() => _preview = true);
  }

  @override
  void dispose() {
    _generation++;
    WidgetsBinding.instance.removeObserver(this);
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    SkoLanguageController.watch(context);
    final target = _target;
    final visible = _current(_generation);
    // Keep the preview and its routes in one subtree for actor/lifecycle cleanup.
    if (visible && target != null && _preview && _canPreview(target)) {
      return NotificationPreviewHost(
        builder: (_) => widget.previewBuilder?.call(target) ??
            invoiceNotificationPreview(target, notificationId: widget.notificationId),
        onClose: () {
          if (mounted) setState(() => _preview = false);
        },
      );
    }
    return Scaffold(
      appBar: AppBar(title: Text(_text('請求書', 'Invoice'))),
      body: !_active || _changed || _source?.actor != _actor
          ? Center(
              child: Text(
                _text(
                  '表示を終了しました。通知を開き直してください。',
                  'This view has closed. Open the notification again.',
                ),
              ),
            )
          : _loading
          ? const Center(child: CircularProgressIndicator())
          : target == null
          ? Center(
              child: Text(
                _text(
                  '対象の請求書は見つからないか、閲覧できません。',
                  'The requested invoice is unavailable.',
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(12),
              children: [
                InvoiceListCard(
                  invoice: target,
                  periodLabel: target.billingPeriod,
                  onTap: _open,
                ),
                if (target.amountPending)
                  Text(
                    _text(
                      '請求金額は未確定です。数量・退勤日報等の確認完了をお待ちください。',
                      'The invoice amount is pending. Wait for quantity and report checks.',
                    ),
                  )
                else if (!_canPreview(target))
                  Text(
                    _text(
                      '帳票の出力準備を確認してください。',
                      'Invoice output is not ready. Please check its settings.',
                    ),
                  )
                else
                  FilledButton(
                    onPressed: _open,
                    child: Text(_text('請求書を開く', 'Open invoice')),
                  ),
              ],
            ),
    );
  }
}
