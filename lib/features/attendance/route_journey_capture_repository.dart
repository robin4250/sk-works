import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../data/supabase_backend.dart';
import 'gps_photo_capture_result.dart';
import 'route_journey_capture_draft.dart';

class RouteJourneyCaptureRepository {
  RouteJourneyCaptureRepository._(this._client);
  final SupabaseClient _client;
  static const bucket = 'attendance-route-evidence';
  static RouteJourneyCaptureRepository? maybeCreate() {
    if (!SupabaseBackend.isInitialized ||
        SupabaseBackend.client.auth.currentUser == null) {
      return null;
    }
    return RouteJourneyCaptureRepository._(SupabaseBackend.client);
  }

  String get userId =>
      _client.auth.currentUser?.id ?? (throw StateError('ログインが必要です'));
  Future<void> _requireMembership(String companyId) async {
    final rows = await _client
        .from('company_members')
        .select('company_id')
        .eq('user_id', userId)
        .eq('company_id', companyId)
        .limit(1);
    if (rows.isEmpty) throw StateError('対象会社の所属を確認できません');
  }

  Future<Map<String, dynamic>> workspace(String sourceId) async {
    dynamic value;
    try {
      value = await _client.rpc(
        'route_journey_visit_workspace',
        params: {'p_source_clock_in_id': sourceId},
      );
    } on PostgrestException catch (error) {
      if (error.code != 'PGRST202' && error.code != '42883') rethrow;
      value = await _client.rpc(
        'route_journey_workspace',
        params: {'p_source_clock_in_id': sourceId},
      );
    }
    if (value is! Map ||
        value['version'] != 1 ||
        value['source_clock_in_id'] != sourceId ||
        value['company_id'] is! String ||
        value['work_date'] is! String) {
      throw StateError('途中現場の勤務情報を確認できません');
    }
    await _requireMembership(value['company_id'] as String);
    return Map<String, dynamic>.from(value);
  }

  Future<bool> enabled(String sourceId) async {
    try {
      return (await workspace(sourceId))['enabled'] == true;
    } catch (_) {
      return false;
    }
  }

  String _key(String companyId) =>
      'sko.route.capture.pending.v1.$userId.$companyId';
  Future<RouteJourneyCaptureDraft?> loadPending(String companyId) async {
    await _requireMembership(companyId);
    final value = (await SharedPreferences.getInstance()).getString(
      _key(companyId),
    );
    if (value == null) return null;
    final draft = RouteJourneyCaptureDraft.restore(value);
    if (draft.userId != userId || draft.companyId != companyId) {
      throw StateError('保留中の本人・会社が一致しません');
    }
    return draft;
  }

  /// Enumerate actual memberships so multiple pending companies require an
  /// explicit source selection; never infer the company from the first row.
  Future<List<RouteJourneyCaptureDraft>> allPending() async {
    final rows = await _client
        .from('company_members')
        .select('company_id')
        .eq('user_id', userId);
    final pending = <RouteJourneyCaptureDraft>[];
    for (final companyId
        in rows.map((row) => row['company_id'] as String).toSet()) {
      final draft = await loadPending(companyId);
      if (draft != null) pending.add(draft);
    }
    return List.unmodifiable(pending);
  }

  Future<Map<String, dynamic>> submit(RouteJourneyCaptureDraft draft) async {
    if (draft.userId != userId) throw StateError('保留中の本人・会社が一致しません');
    await _requireMembership(draft.companyId);
    final preferences = await SharedPreferences.getInstance();
    final key = _key(draft.companyId);
    final previous = preferences.getString(key);
    if (previous != null && previous != draft.encoded) {
      throw StateError('先に保留中の途中現場記録を確認してください');
    }
    if (!await preferences.setString(key, draft.encoded)) {
      throw StateError('再確認用の記録を保存できません');
    }
    final row = await recoverRouteJourneyCapture(
      draft,
      readExact: () async {
        final value = await _client.rpc(
          draft.visitKind == null
              ? 'route_journey_capture_exact'
              : 'route_journey_visit_exact',
          params: {'p_id': draft.id},
        );
        if (value == null) return null;
        if (value is! Map) throw StateError('記録の照会結果を確認できません');
        return Map<String, dynamic>.from(value);
      },
      insert: () async {
        if (!draft.canInsertOn(DateTime.now())) {
          throw StateError('日付が変わったため新規登録せず、元の記録だけ照会します');
        }
        final value = await _client.rpc(
          draft.visitKind == null
              ? 'save_route_journey_capture'
              : 'save_route_journey_visit',
          params: {
            if (draft.visitKind != null) 'p_kind': draft.visitKind,
            if (draft.visitKind != null)
              'p_start_capture_id': draft.visitStartId,
            'p_id': draft.id,
            'p_source_clock_in_id': draft.sourceId,
            'p_route_stop_id': draft.stopId,
            'p_origin_kind': draft.originKind,
            'p_payload': draft.payload,
          },
        );
        if (value is! Map) throw StateError('途中現場の登録結果を確認できません');
        return Map<String, dynamic>.from(value);
      },
    );
    await preferences.remove(key);
    return row;
  }

  Future<String> upload(
    CapturedPhoto photo,
    CaptureShiftContext context,
    String workerId,
  ) async {
    if (context.sourceClockInId == null || context.routeId == null) {
      throw StateError('撮影対象の勤務を確認してください');
    }
    final source = await workspace(context.sourceClockInId!);
    if (source['company_id'] != context.companyId ||
        source['worker_id'] != workerId ||
        source['route_assignment_id'] != context.routeId ||
        source['enabled'] != true ||
        source['is_open'] != true) {
      throw StateError('撮影対象の本人・会社・勤務が一致しません');
    }
    final path =
        '${context.companyId}/attendance/${context.routeId}/$workerId/${context.sourceClockInId}/${DateTime.now().microsecondsSinceEpoch}.jpg';
    await _client.storage
        .from(bucket)
        .uploadBinary(
          path,
          photo.bytes,
          fileOptions: const FileOptions(upsert: false),
        );
    return path; // Never delete on an unknown insert response.
  }
}
