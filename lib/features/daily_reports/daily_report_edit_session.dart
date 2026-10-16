import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Durable identifiers only. Signatures and report contents are never stored.
class DailyReportEditSession {
  const DailyReportEditSession({required this.actorId, required this.companyId,
    required this.reportId, required this.requestId, this.confirmed = false});
  final String actorId, companyId, reportId, requestId;
  final bool confirmed;
  DailyReportEditSession confirm() => DailyReportEditSession(actorId: actorId,
    companyId: companyId, reportId: reportId, requestId: requestId, confirmed: true);
  Map<String, Object> toJson() => {'actor': actorId, 'company': companyId,
    'report': reportId, 'request': requestId, 'confirmed': confirmed};
  static DailyReportEditSession parse(String raw) {
    final value = jsonDecode(raw);
    if (value is! Map || ['actor', 'company', 'report', 'request'].any(
      (key) => value[key] is! String || (value[key] as String).isEmpty) ||
      value['confirmed'] is! bool) {
      throw const FormatException('Invalid daily report edit session');
    }
    return DailyReportEditSession(actorId: value['actor'] as String,
      companyId: value['company'] as String, reportId: value['report'] as String,
      requestId: value['request'] as String, confirmed: value['confirmed'] as bool);
  }
}

class DailyReportEditSessionStore {
  DailyReportEditSessionStore({Future<String?> Function(String)? read,
    Future<void> Function(String, String)? write,
    Future<void> Function(String)? remove})
    : _read = read ?? SharedPreferencesAsync().getString,
      _write = write ?? SharedPreferencesAsync().setString,
      _remove = remove ?? SharedPreferencesAsync().remove;
  final Future<String?> Function(String) _read;
  final Future<void> Function(String, String) _write;
  final Future<void> Function(String) _remove;
  String _key(String actor, String report) => 'sko.daily_report_edit.v1.$actor.$report';
  Future<DailyReportEditSession?> load(String actor, String report) async {
    final raw = await _read(_key(actor, report));
    if (raw == null) return null;
    final session = DailyReportEditSession.parse(raw);
    if (session.actorId != actor || session.reportId != report) {
      throw const FormatException('Daily report edit session scope mismatch');
    }
    return session;
  }
  Future<void> remember(DailyReportEditSession session) =>
    _write(_key(session.actorId, session.reportId), jsonEncode(session.toJson()));
  Future<void> clear(DailyReportEditSession session) async {
    final current = await load(session.actorId, session.reportId);
    if (current?.requestId == session.requestId &&
        current?.companyId == session.companyId) {
      await _remove(_key(session.actorId, session.reportId));
    }
  }
}
