import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/supabase_backend.dart';

abstract class AttendanceNoticeSource {
  String? get actor;
  Stream<String?> get actorChanges;
  Future<Map<String, dynamic>?> target(String id);
  Future<List<Map<String, dynamic>>> day(String company, DateTime start, DateTime end);
}

class SupabaseAttendanceNoticeSource implements AttendanceNoticeSource {
  SupabaseAttendanceNoticeSource(this.client);
  final SupabaseClient client;
  static const columns = 'id,company_id,worker_id,event_type,confirmed_at,'
      'workers!attendance_verifications_worker_id_fkey(name),'
      'sites!attendance_verifications_site_id_fkey(name)';
  @override
  String? get actor => client.auth.currentUser?.id;
  @override
  Stream<String?> get actorChanges => client.auth.onAuthStateChange
      .map((state) => state.session?.user.id);
  @override
  Future<Map<String, dynamic>?> target(String id) => client
      .from('attendance_verifications').select(columns).eq('id', id).maybeSingle();
  @override
  Future<List<Map<String, dynamic>>> day(String company, DateTime start, DateTime end) async {
    final expectedActor = actor;
    if (expectedActor == null) throw StateError('ログインが必要です。');
    final result = <Map<String, dynamic>>[];
    for (var offset = 0; ; offset += 500) {
      final rows = await client.from('attendance_verifications').select(columns)
          .eq('company_id', company)
          .gte('confirmed_at', start.toIso8601String())
          .lt('confirmed_at', end.toIso8601String())
          .order('confirmed_at').order('id').range(offset, offset + 499);
      if (actor != expectedActor) throw StateError('ログイン状態が変わりました。');
      result.addAll(rows);
      if (rows.length < 500) return result;
    }
  }
}

/// Resolves the original verification under the signed-in user's existing RLS.
/// Never substitutes today, the current worker, or a different company.
class AttendanceNotificationPage extends StatefulWidget {
  const AttendanceNotificationPage({super.key, required this.verificationId, this.source});
  final String verificationId;
  final AttendanceNoticeSource? source;
  @override
  State<AttendanceNotificationPage> createState() => _AttendanceNotificationPageState();
}

class _AttendanceNotificationPageState extends State<AttendanceNotificationPage> {
  AttendanceNoticeSource? _source;
  StreamSubscription<String?>? _subscription;
  String? _actor;
  String? _error;
  bool _loading = true;
  bool _actorChanged = false;
  int _generation = 0;
  List<Map<String, dynamic>> _rows = [];
  DateTime? _date;

  @override
  void initState() {
    super.initState();
    _source = widget.source ?? (SupabaseBackend.isInitialized
        ? SupabaseAttendanceNoticeSource(SupabaseBackend.client) : null);
    _actor = _source?.actor;
    _subscription = _source?.actorChanges.listen((actor) {
      if (actor != _actor) _invalidateActor();
    }, onError: (Object error) => _invalidateActor());
    _load();
  }

  void _invalidateActor() {
    _actorChanged = true;
    _generation++;
    if (mounted) setState(() {
      _rows = [];
      _date = null;
      _loading = false;
      _error = 'ログイン状態が変わったか、確認できません。通知一覧から開き直してください。';
    });
  }

  @override
  void dispose() {
    _generation++;
    _subscription?.cancel();
    super.dispose();
  }

  bool _current(int generation) => mounted && !_actorChanged &&
      generation == _generation && _source?.actor == _actor;

  Future<void> _load() async {
    final generation = ++_generation;
    final source = _source;
    setState(() { _loading = true; _error = null; _rows = []; _date = null; });
    try {
      if (_actorChanged || source?.actor != _actor) {
        throw StateError('ログイン状態が変わりました。通知一覧から開き直してください。');
      }
      if (source == null || _actor == null) {
        throw StateError('ログインとクラウド接続を確認してください。');
      }
      if (!RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$')
          .hasMatch(widget.verificationId)) {
        throw StateError('通知の出勤記録IDが正しくありません。');
      }
      final target = await source.target(widget.verificationId);
      if (!_current(generation)) return;
      if (target == null) {
        throw StateError('対象の出勤記録は削除されたか、閲覧権限がありません。');
      }
      final company = target['company_id']?.toString() ?? '';
      final worker = target['worker_id']?.toString() ?? '';
      final rawTime = target['confirmed_at']?.toString() ?? '';
      final time = DateTime.tryParse(rawTime);
      if (target['id'] != widget.verificationId || company.isEmpty || worker.isEmpty ||
          time == null || !RegExp(r'(Z|[+-]\d{2}:\d{2})$').hasMatch(rawTime)) {
        throw StateError('対象の出勤記録の日時・会社・従業員を確認できません。');
      }
      final jst = time.toUtc().add(const Duration(hours: 9));
      final date = DateTime.utc(jst.year, jst.month, jst.day);
      final start = date.subtract(const Duration(hours: 9));
      final rows = await source.day(company, start, start.add(const Duration(days: 1)));
      if (!_current(generation)) return;
      final exact = rows.where((row) => row['id'] == widget.verificationId).toList();
      if (exact.length != 1 || exact.single['company_id'] != company ||
          exact.single['worker_id'] != worker || exact.single['confirmed_at'] != target['confirmed_at']) {
        throw StateError('対象の出勤記録が変更されたか、閲覧できなくなりました。再読み込みしてください。');
      }
      setState(() {
        _date = date;
        _rows = [exact.single, ...rows.where((row) => row['id'] != widget.verificationId)];
        _loading = false;
      });
    } catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _loading = false;
        _rows = [];
        _error = source?.actor != _actor
            ? 'ログイン状態が変わりました。通知一覧から開き直してください。'
            : error is StateError ? error.message.toString()
            : '出勤記録を読み込めません。接続または閲覧権限を確認して再試行してください。';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('通知の出勤記録')),
      body: _loading ? const Center(child: CircularProgressIndicator())
          : _error != null ? Center(child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(_error!),
                const SizedBox(height: 16),
                if (!_actorChanged) FilledButton(onPressed: _load, child: const Text('再読み込み')),
              ])))
          : RefreshIndicator(onRefresh: _load, child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(12),
              children: [
                Text('${_date!.year}/${_date!.month}/${_date!.day} の出勤記録',
                    style: Theme.of(context).textTheme.titleLarge),
                const Text('通知の対象を先頭に表示しています。以下は同じ会社・同じ日の記録です。'),
                for (final row in _rows) Card(
                  key: ValueKey('verification-${row['id']}'),
                  color: row['id'] == widget.verificationId
                      ? Theme.of(context).colorScheme.primaryContainer : null,
                  child: ListTile(
                    leading: Icon(row['id'] == widget.verificationId
                        ? Icons.notifications_active : Icons.history),
                    title: Text('${row['id'] == widget.verificationId ? '通知の対象：' : ''}'
                        '${_name(row['workers'], '従業員情報なし')}'),
                    subtitle: Text('${_name(row['sites'], '現場未設定')} / '
                        '${row['event_type'] == 'clock_in' ? '出勤' : row['event_type'] == 'clock_out' ? '退勤' : '勤務記録'} / '
                        '${_time(row['confirmed_at'])}'),
                  ),
                ),
              ],
            )),
    );
  }

  String _name(Object? raw, String fallback) => raw is Map &&
      raw['name']?.toString().trim().isNotEmpty == true ? raw['name'].toString() : fallback;
  String _time(Object? raw) {
    final time = DateTime.tryParse(raw?.toString() ?? '')?.toUtc().add(const Duration(hours: 9));
    if (time == null) return '時刻不明';
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }
}
