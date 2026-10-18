import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/supabase_backend.dart';
import '../../international/language_controller.dart';
import '../referrals/app_referral_repository.dart' show referralJapanTime;

abstract class SiteMapNoticeSource {
  String? get actor;
  Stream<String?> get actorChanges;
  Future<Map<String, dynamic>?> target(String verificationId);
}

/// Reads one saved verification using the caller's existing Data API access.
class SupabaseSiteMapNoticeSource implements SiteMapNoticeSource {
  SupabaseSiteMapNoticeSource(this.client);
  final SupabaseClient client;
  static const columns =
      'id,company_id,worker_id,confirmed_at,event_type,latitude,longitude,'
      'workers!attendance_verifications_worker_id_fkey(name),'
      'sites!attendance_verifications_site_id_fkey(name)';
  @override
  String? get actor => client.auth.currentUser?.id;
  @override
  Stream<String?> get actorChanges =>
      client.auth.onAuthStateChange.map((state) => state.session?.user.id);
  @override
  Future<Map<String, dynamic>?> target(String verificationId) => client
      .from('attendance_verifications')
      .select(columns)
      .eq('id', verificationId)
      .maybeSingle();
}

final _uuid = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);

class SiteMapNoticeTarget {
  const SiteMapNoticeTarget._(
    this.verificationId,
    this.companyId,
    this.workerId,
    this.confirmedAt,
    this.latitude,
    this.longitude,
    this.workerName,
    this.siteName,
  );
  final String verificationId, companyId, workerId, confirmedAt;
  final double latitude, longitude;
  final String workerName, siteName;

  factory SiteMapNoticeTarget.fromRow(
    String requestedId,
    Map<String, dynamic> row,
  ) {
    final company = row['company_id'];
    final worker = row['worker_id'];
    final time = row['confirmed_at'];
    final lat = row['latitude'];
    final lon = row['longitude'];
    if (!_uuid.hasMatch(requestedId) ||
        row['id'] != requestedId ||
        company is! String ||
        !_uuid.hasMatch(company) ||
        worker is! String ||
        !_uuid.hasMatch(worker) ||
        time is! String ||
        !_validTime(time) ||
        lat is! num ||
        lon is! num ||
        !lat.isFinite ||
        !lon.isFinite ||
        lat < -90 ||
        lat > 90 ||
        lon < -180 ||
        lon > 180) {
      throw const FormatException('Invalid saved location');
    }
    String name(Object? value) =>
        value is Map && value['name'] is String ? value['name'] as String : '';
    return SiteMapNoticeTarget._(
      requestedId,
      company,
      worker,
      time,
      lat.toDouble(),
      lon.toDouble(),
      name(row['workers']),
      name(row['sites']),
    );
  }

  static bool _validTime(String value) {
    final match = RegExp(
      r'^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.\d{1,9})?(?:Z|([+-])(\d{2}):(\d{2}))$',
    ).firstMatch(value);
    if (match == null) return false;
    int part(int index) => int.parse(match.group(index)!);
    final date = DateTime.utc(part(1), part(2), part(3));
    return part(1) > 0 &&
        date.year == part(1) &&
        date.month == part(2) &&
        date.day == part(3) &&
        part(4) < 24 &&
        part(5) < 60 &&
        part(6) < 60 &&
        (match.group(7) == null || (part(8) < 24 && part(9) < 60)) &&
        DateTime.tryParse(value) != null;
  }

  Uri get mapUri => Uri.https('www.google.com', '/maps/search/', {
    'api': '1',
    'query': '$latitude,$longitude',
  });
}

typedef SiteMapNoticeOpener = Future<bool> Function(Uri uri);

/// Historical saved coordinates only; never requests the current GPS position.
class SiteMapNotificationPage extends StatefulWidget {
  const SiteMapNotificationPage({
    super.key,
    required this.verificationId,
    this.source,
    this.openMap,
  });
  final String verificationId;
  final SiteMapNoticeSource? source;
  final SiteMapNoticeOpener? openMap;
  @override
  State<SiteMapNotificationPage> createState() =>
      _SiteMapNotificationPageState();
}

class _SiteMapNotificationPageState extends State<SiteMapNotificationPage>
    with WidgetsBindingObserver {
  SiteMapNoticeSource? _source;
  StreamSubscription<String?>? _subscription;
  String? _actor;
  SiteMapNoticeTarget? _target;
  bool _loading = true, _changed = false, _active = true, _opening = false;
  String? _error;
  int _generation = 0;

  String _text(String ja, String en) =>
      SkoLanguageController.isEnglish ? en : ja;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _active = lifecycle == null || lifecycle == AppLifecycleState.resumed;
    _source =
        widget.source ??
        (SupabaseBackend.isInitialized
            ? SupabaseSiteMapNoticeSource(SupabaseBackend.client)
            : null);
    _actor = _source?.actor;
    _subscription = _source?.actorChanges.listen((actor) {
      if (actor != _actor) _invalidate();
    }, onError: (Object error) => _invalidate());
    _load();
  }

  @override
  void didUpdateWidget(covariant SiteMapNotificationPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.source != widget.source ||
        oldWidget.verificationId != widget.verificationId) {
      _invalidate();
    }
  }

  void _invalidate() {
    _changed = true;
    _generation++;
    if (mounted) {
      setState(() {
        _target = null;
        _loading = false;
        _opening = false;
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _active = state == AppLifecycleState.resumed;
    _generation++;
    if (_source?.actor != _actor) _invalidate();
    if (!_active) {
      if (mounted) {
        setState(() {
          _target = null;
          _loading = false;
          _opening = false;
        });
      }
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
      _loading = true;
      _target = null;
      _error = null;
    });
    try {
      final source = _source;
      if (source == null ||
          _actor == null ||
          !_uuid.hasMatch(widget.verificationId)) {
        throw const FormatException('Missing saved target');
      }
      final row = await source.target(widget.verificationId);
      if (_source?.actor != _actor) _invalidate();
      if (!_current(generation)) return;
      if (row == null) throw const FormatException('Saved target unavailable');
      final target = SiteMapNoticeTarget.fromRow(widget.verificationId, row);
      setState(() {
        _target = target;
        _loading = false;
      });
    } catch (_) {
      if (_source?.actor != _actor) _invalidate();
      if (!mounted || !_active || _changed || generation != _generation) return;
      setState(() {
        _target = null;
        _loading = false;
        _error = 'unavailable';
      });
    }
  }

  Future<void> _open() async {
    if (_source?.actor != _actor) _invalidate();
    final target = _target;
    if (target == null || _opening || !_current(_generation)) return;
    final generation = _generation;
    setState(() => _opening = true);
    try {
      final opened =
          await (widget.openMap?.call(target.mapUri) ??
              launchUrl(target.mapUri, mode: LaunchMode.externalApplication));
      if (_source?.actor != _actor) _invalidate();
      if (_current(generation) && !opened) _showMapError();
    } catch (_) {
      if (_source?.actor != _actor) _invalidate();
      if (_current(generation)) _showMapError();
    } finally {
      if (_current(generation)) setState(() => _opening = false);
    }
  }

  void _showMapError() => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        _text(
          '地図を開けませんでした。もう一度お試しください。',
          'Could not open the map. Please try again.',
        ),
      ),
    ),
  );

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
    return Scaffold(
      appBar: AppBar(
        title: Text(_text('通知の打刻位置', 'Location from this notification')),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _changed
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  _text(
                    'ログイン状態が変わったか、確認できません。通知一覧から開き直してください。',
                    'Your sign-in changed or could not be verified. Open this again from notifications.',
                  ),
                ),
              ),
            )
          : target == null || _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _text(
                        '通知の打刻位置を確認できません。記録がないか、閲覧できない可能性があります。',
                        'The saved location is unavailable. The record may be missing or you may not have access.',
                      ),
                    ),
                    TextButton(
                      onPressed: _load,
                      child: Text(_text('再読み込み', 'Reload')),
                    ),
                  ],
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Text(
                  _text(
                    '通知当時に保存された位置です。',
                    'This is the location saved with the notified record.',
                  ),
                ),
                if (target.workerName.isNotEmpty) Text(target.workerName),
                if (target.siteName.isNotEmpty) Text(target.siteName),
                Text(referralJapanTime(target.confirmedAt)),
                Text('${target.latitude}, ${target.longitude}'),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _opening ? null : _open,
                  child: Text(_text('Google マップで開く', 'Open in Google Maps')),
                ),
              ],
            ),
    );
  }
}
