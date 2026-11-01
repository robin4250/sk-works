import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crypto/crypto.dart';

import '../../data/supabase_backend.dart';
import '../auth/apple_session_navigation_binding.dart';

enum TradeCompanyPageMode { customer, subcontractor }

class TradeCompanyRecord {
  const TradeCompanyRecord({
    required this.id,
    required this.name,
    required this.tradeRole,
    required this.linkStatus,
    required this.postalCode,
    required this.address,
    required this.phone,
    required this.email,
    required this.corporateNumber,
    required this.notes,
    this.representativeName = '',
    this.representativePhone = '',
    required this.contractMethod,
    required this.dailyRateYen,
    required this.monthlyRateYen,
    required this.squareMeterUnitPriceYen,
    required this.squareMeterQuantity,
    required this.contractAmountYen,
  });

  final String id;
  final String name;
  final String tradeRole;
  final String linkStatus;
  final String postalCode;
  final String address;
  final String phone;
  final String email;
  final String corporateNumber;
  final String notes;
  final String representativeName;
  final String representativePhone;
  final String contractMethod;
  final int dailyRateYen;
  final int monthlyRateYen;
  final int squareMeterUnitPriceYen;
  final double squareMeterQuantity;
  final int contractAmountYen;

  bool get isCustomer => tradeRole == 'customer' || tradeRole == 'both';
  bool get isSubcontractor =>
      tradeRole == 'subcontractor' || tradeRole == 'both';

  factory TradeCompanyRecord.fromJson(Map<String, dynamic> row) {
    return TradeCompanyRecord(
      id: row['id']?.toString() ?? '',
      name: row['name']?.toString() ?? '',
      tradeRole: row['trade_role']?.toString() ?? 'customer',
      linkStatus: row['link_status']?.toString() ?? 'local',
      postalCode: row['postal_code']?.toString() ?? '',
      address: row['address']?.toString() ?? '',
      phone: row['phone']?.toString() ?? '',
      email: row['email']?.toString() ?? '',
      corporateNumber: row['corporate_number']?.toString() ?? '',
      notes: row['notes']?.toString() ?? '',
      representativeName: row['representative_name']?.toString() ?? '',
      representativePhone: row['representative_phone']?.toString() ?? '',
      contractMethod: row['contract_method']?.toString() ?? 'none',
      dailyRateYen: (row['daily_rate_yen'] as num?)?.toInt() ?? 0,
      monthlyRateYen: (row['monthly_rate_yen'] as num?)?.toInt() ?? 0,
      squareMeterUnitPriceYen:
          (row['square_meter_unit_price_yen'] as num?)?.toInt() ?? 0,
      squareMeterQuantity:
          (row['square_meter_quantity'] as num?)?.toDouble() ?? 0,
      contractAmountYen: (row['contract_amount_yen'] as num?)?.toInt() ?? 0,
    );
  }
}

class TradeCompanyLinkCandidate {
  const TradeCompanyLinkCandidate({
    required this.companyId,
    required this.companyName,
    required this.phone,
    required this.address,
    required this.corporateNumber,
    required this.matchScore,
  });

  final String companyId;
  final String companyName;
  final String phone;
  final String address;
  final String corporateNumber;
  final int matchScore;

  factory TradeCompanyLinkCandidate.fromJson(Map<String, dynamic> row) {
    return TradeCompanyLinkCandidate(
      companyId: row['company_id']?.toString() ?? '',
      companyName: row['company_name']?.toString() ?? '',
      phone: row['phone']?.toString() ?? '',
      address: row['address']?.toString() ?? '',
      corporateNumber: row['corporate_number']?.toString() ?? '',
      matchScore:
          (row['match_score'] as num?)?.toInt() ??
          int.tryParse(row['match_score']?.toString() ?? '') ??
          0,
    );
  }
}

class TradeCompanyRepository {
  TradeCompanyRepository._(this._client) : _authEvents = null;
  TradeCompanyRepository.forTesting(
    this._client, {
    Stream<AuthState>? Function()? authEvents,
  }) : _authEvents = authEvents;
  final Stream<AuthState>? Function()? _authEvents;

  final SupabaseClient _client;

  Future<CompanyLinkBoundContext> openBoundLinkContext() async {
    final context = CompanyLinkBoundContext._(
      _client,
      _authEvents == null ? _client.auth.onAuthStateChange : _authEvents!(),
    );
    try {
      await context.initialize();
      return context;
    } catch (_) {
      await context.dispose();
      rethrow;
    }
  }

  static TradeCompanyRepository? maybeCreate() {
    if (!SupabaseBackend.isInitialized) return null;
    final client = SupabaseBackend.client;
    if (client.auth.currentUser == null) return null;
    return TradeCompanyRepository._(client);
  }

  Future<List<TradeCompanyRecord>> loadAll() async {
    await _client.rpc('sync_trade_company_directory');
    final raw = await _client.rpc('trade_company_contact_workspace');
    if (raw is! List) return const [];
    return [
      for (final item in raw)
        if (item is Map)
          TradeCompanyRecord.fromJson(Map<String, dynamic>.from(item)),
    ];
  }

  Future<Map<String, dynamic>> linkWorkspace() async {
    final context = await openBoundLinkContext();
    try {
      final value = await context.workspace();
      // Existing entry callers use `enabled` only for navigation. Read-only
      // history and unresolved-result lookup remain available while writes stop.
      return {...value, 'enabled': value['available'] == true};
    } finally {
      await context.dispose();
    }
  }

  Future<void> setLinkEnabled(bool enabled) async {
    await _client.rpc(
      'set_trade_company_link_enabled',
      params: {'p_enabled': enabled},
    );
  }

  Future<List<Map<String, dynamic>>> searchLinkCompanies(String query) async {
    final raw = await _client.rpc(
      'search_trade_company_links',
      params: {'p_query': query.trim()},
    );
    return [
      for (final row in raw as List) Map<String, dynamic>.from(row as Map),
    ];
  }

  Future<void> requestLink({
    required String companyId,
    required TradeCompanyPageMode mode,
    required DateTime startMonth,
  }) async {
    await _client.rpc(
      'request_trade_company_link',
      params: {
        'p_target_company_id': companyId,
        'p_local_role': mode == TradeCompanyPageMode.customer
            ? 'customer'
            : 'subcontractor',
        'p_start_month':
            '${startMonth.year}-${startMonth.month.toString().padLeft(2, '0')}-01',
      },
    );
  }

  Future<void> respondLink(String id, String action) async {
    await _client.rpc(
      'respond_trade_company_link',
      params: {'p_request_id': id, 'p_action': action},
    );
  }

  Future<String> saveCompany({
    String? id,
    required String name,
    required String tradeRole,
    String? postalCode,
    String? address,
    String? phone,
    String? email,
    String? corporateNumber,
    String? notes,
    String? representativeName,
    String? representativePhone,
  }) async {
    final value = await _client.rpc(
      'save_trade_company_contact',
      params: {
        'p_data': {
          'id': id,
          'name': name,
          'trade_role': tradeRole,
          'postal_code': postalCode,
          'address': address,
          'phone': phone,
          'email': email,
          'corporate_number': corporateNumber,
          'notes': notes,
          'representative_name': representativeName,
          'representative_phone': representativePhone,
        },
      },
    );
    return value?.toString() ?? '';
  }

  Future<bool> deleteCompany(String id) async {
    try {
      final raw = await _client.rpc(
        'delete_trade_company_checked',
        params: {'p_trade_company_id': id},
      );
      if (raw is Map) {
        return raw['deleted'] == true;
      }
      return false;
    } on PostgrestException catch (error) {
      throw StateError(error.message);
    }
  }

  Future<void> saveContract({
    required String tradeCompanyId,
    required String contractMethod,
    required int dailyRateYen,
    required int monthlyRateYen,
    required int squareMeterUnitPriceYen,
    required double squareMeterQuantity,
    required int contractAmountYen,
  }) async {
    await _client.rpc(
      'save_trade_company_contract',
      params: {
        'p_trade_company_id': tradeCompanyId,
        'p_contract_method': contractMethod,
        'p_daily_rate_yen': dailyRateYen,
        'p_monthly_rate_yen': monthlyRateYen,
        'p_square_meter_unit_price_yen': squareMeterUnitPriceYen,
        'p_square_meter_quantity': squareMeterQuantity,
        'p_contract_amount_yen': contractAmountYen,
      },
    );
  }

  Future<List<TradeCompanyLinkCandidate>> linkCandidates(String id) async {
    final raw = await _client.rpc(
      'trade_company_link_candidates',
      params: {'p_trade_company_id': id},
    );
    if (raw is! List) return const [];
    return [
      for (final item in raw)
        if (item is Map)
          TradeCompanyLinkCandidate.fromJson(Map<String, dynamic>.from(item)),
    ];
  }

  Future<void> confirmLink({
    required String tradeCompanyId,
    required String linkedCompanyId,
  }) async {
    await _client.rpc(
      'confirm_trade_company_link',
      params: {
        'p_trade_company_id': tradeCompanyId,
        'p_linked_company_id': linkedCompanyId,
      },
    );
  }

  Future<void> selectCalculationSource({
    required String siteId,
    required String outputType,
    required String tradeCompanyId,
    required String source,
  }) async {
    await _client.rpc(
      'select_site_calculation_source',
      params: {
        'p_site_id': siteId,
        'p_output_type': outputType,
        'p_trade_company_id': tradeCompanyId,
        'p_source': source,
      },
    );
  }
}

/// Route-local lifetime and operation binding; never an authorization decision.
/// Server checks the live SID, membership and exact company on every command.
class CompanyLinkBoundContext {
  CompanyLinkBoundContext._(this._client, Stream<AuthState>? events) {
    _binding = AppleSessionNavigationBinding.fromSession(
      _client.auth.currentSession,
    );
    if (_binding == null) {
      throw StateError('ログイン状態を確認してください');
    }
    _trackingHealthy = events != null;
    try {
    _subscription = events?.listen((event) {
      AppleSessionNavigationBinding? next;
      try {
        next = AppleSessionNavigationBinding.fromSession(event.session);
      } catch (_) {
        _retire();
      }
      if (next != _binding) _retire();
    });
    } catch (_) {
      _retireTracking();
    }
    if (!_trackingHealthy) _retire();
  }
  final SupabaseClient _client;
  AppleSessionNavigationBinding? _binding;
  StreamSubscription<AuthState>? _subscription;
  late bool _trackingHealthy;
  void _retireTracking() {
    _trackingHealthy = false;
    _retire();
  }
  bool _retired = false;
  final _retirements = StreamController<void>.broadcast();
  Stream<void> get retirements => _retirements.stream;
  void retire() => _retire();
  void _retire() {
    if (_retired) return;
    _retired = true;
    _retirements.add(null);
  }

  String? _company;
  String? _pendingOperation;
  String? _pendingCommand;
  Map<String, dynamic>? _pendingPayload;
  String? _originalSession;
  String? _pendingFingerprint;
  SharedPreferences? _preferences;
  bool _corruptPending = false;
  static final Set<String> _activeMutations = {};
  String get _pendingKey =>
      'sko.company_link.pending.v1.${_binding!.actorId}.$_company';
  static final _uuid = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
  );
  String get companyId => _company ?? '';
  bool get hasUnknownResult => _pendingOperation != null || _corruptPending;
  bool get isCurrent {
    if (!_trackingHealthy) _retire();
    try {
      if (AppleSessionNavigationBinding.fromSession(
            _client.auth.currentSession,
          ) !=
          _binding) {
        _retire();
      }
    } catch (_) {
      _retire();
    }
    return !_retired;
  }

  void requireCurrent() {
    if (!isCurrent) throw StateError('ログイン・会社の状態が変わりました。画面を開き直してください');
  }

  Future<void> dispose() async {
    _retired = true;
    await _subscription?.cancel();
    await _retirements.close();
  }

  Future<void> initialize() async {
    requireCurrent();
    final session = _client.auth.currentSession!;
    final rows = await _client
        .from('company_members')
        .select('company_id,role')
        .eq('user_id', _binding!.actorId)
        .setHeader('Authorization', 'Bearer ${session.accessToken}')
        .retry(enabled: false);
    requireCurrent();
    if (rows.length != 1 ||
        rows.single['company_id'] is! String ||
        !_uuid.hasMatch(rows.single['company_id'] as String) ||
        !['owner', 'admin'].contains(rows.single['role'])) {
      throw StateError('会社を一意に確認できません。管理者の所属会社を確認してください');
    }
    _company = rows.single['company_id'] as String;
    _preferences = await SharedPreferences.getInstance();
    requireCurrent();
    final saved = _preferences!.getString(_pendingKey);
    if (saved != null) {
      try {
        final row = jsonDecode(saved);
        if (row is! Map ||
            row.length != 7 ||
            row['version'] != 1 ||
            row['actor'] != _binding!.actorId ||
            row['company'] != _company ||
            row['operation'] is! String ||
            !_uuid.hasMatch(row['operation'] as String) ||
            row['session'] is! String ||
            !_uuid.hasMatch(row['session'] as String) ||
            row['fingerprint'] is! String ||
            !RegExp(r'^[0-9a-f]{64}$').hasMatch(row['fingerprint'] as String) ||
            !['set_enabled', 'request', 'respond'].contains(row['command'])) {
          throw const FormatException();
        }
        _pendingOperation = row['operation'] as String;
        _pendingCommand = row['command'] as String;
        _originalSession = row['session'] as String;
        _pendingFingerprint = row['fingerprint'] as String;
      } catch (_) {
        _corruptPending = true;
      }
    }
  }

  static String _operationId() {
    final random = Random.secure();
    final bytes = List.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 15) | 64;
    bytes[8] = (bytes[8] & 63) | 128;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  static String _fingerprint(String command, Map<String, dynamic> payload) {
    final keys = payload.keys.toList()..sort();
    return sha256
        .convert(
          utf8.encode(
            jsonEncode({
              'command': command,
              'payload': {for (final key in keys) key: payload[key]},
            }),
          ),
        )
        .toString();
  }

  static bool _validResult(String command, Map payload, dynamic value) {
    if (value is! Map || value['state'] != 'committed') return false;
    if (command == 'set_enabled') {
      return value.length == 2 &&
          value['enabled'] is bool &&
          value['enabled'] == payload['enabled'];
    }
    if (value.length != 3 ||
        value['request_id'] is! String ||
        !_uuid.hasMatch(value['request_id'] as String)) {
      return false;
    }
    if (command == 'request') return value['status'] == 'pending';
    return command == 'respond' &&
        value['request_id'] == payload['request_id'] &&
        value['status'] ==
            {
              'accept': 'accepted',
              'reject': 'rejected',
              'cancel': 'cancelled',
            }[payload['action']];
  }

  Future<dynamic> _call(
    String command,
    Map<String, dynamic> payload, {
    String? operation,
  }) async {
    requireCurrent();
    if (_company == null) throw StateError('会社の確認が必要です');
    final session = _client.auth.currentSession!;
    final raw = await _client
        .rpc(
          'company_link_bound_v1',
          params: {
            'p_company': _company,
            'p_session': _binding!.sessionId,
            'p_operation': operation,
            'p_command': command,
            'p_payload': payload,
          },
        )
        .setHeader('Authorization', 'Bearer ${session.accessToken}')
        .retry(enabled: false);
    requireCurrent();
    const keys = {
      'version',
      'actor_id',
      'company_id',
      'session_id',
      'operation_id',
      'command',
      'value',
    };
    if (raw is! Map ||
        raw.length != keys.length ||
        !raw.keys.every(keys.contains) ||
        raw['version'] is! int ||
        raw['version'] != 1 ||
        raw['actor_id'] != _binding!.actorId ||
        raw['company_id'] != _company ||
        raw['session_id'] != _binding!.sessionId ||
        raw['operation_id'] != operation ||
        raw['command'] != command) {
      throw StateError('処理結果を照合できません。再送せず状態を確認してください');
    }
    return raw['value'];
  }

  Future<Map<String, dynamic>> workspace() async {
    final value = await _call('workspace', const {});
    if (value is! Map ||
        value.length != 4 ||
        value['available'] is! bool ||
        value['writes_enabled'] is! bool ||
        value['enabled'] is! bool ||
        value['requests'] is! List) {
      throw StateError('会社連携の状態を確認できません');
    }
    return Map<String, dynamic>.from(value);
  }

  Future<List<Map<String, dynamic>>> search(String query) async {
    final value = await _call('search', {'query': query.trim()});
    if (value is! List ||
        value.any(
          (r) =>
              r is! Map ||
              r['company_id'] is! String ||
              !_uuid.hasMatch(r['company_id'] as String),
        )) {
      throw StateError('検索結果を確認できません');
    }
    return [for (final row in value) Map<String, dynamic>.from(row as Map)];
  }

  Future<Map<String, dynamic>> mutate(
    String command,
    Map<String, dynamic> payload,
  ) async {
    requireCurrent();
    if (!['set_enabled', 'request', 'respond'].contains(command)) {
      throw StateError('操作を確認できません');
    }
    if (_preferences!.getString(_pendingKey) != null) {
      throw StateError('前の処理記録があります。画面を開き直して結果を確認してください');
    }
    if (hasUnknownResult) throw StateError('前の処理結果が不明です。再送せず状態を確認してください');
    if (!_activeMutations.add(_pendingKey)) {
      throw StateError('この会社の処理結果を確認中です');
    }
    try {
      _pendingOperation = _operationId();
      _pendingCommand = command;
      _originalSession = _binding!.sessionId;
      _pendingPayload = Map<String, dynamic>.unmodifiable(payload);
      _pendingFingerprint = _fingerprint(command, payload);
      // Only lookup identifiers are persisted, never bearer tokens or business payloads.
      final saved = await _preferences!.setString(
        _pendingKey,
        jsonEncode({
          'actor': _binding!.actorId,
          'company': _company,
          'operation': _pendingOperation,
          'session': _originalSession,
          'command': command,
          'version': 1,
          'fingerprint': _pendingFingerprint,
        }),
      );
      if (!saved) throw StateError('処理記録を保存できません。送信していません');
      requireCurrent();
      final value = await _call(
        command,
        _pendingPayload!,
        operation: _pendingOperation,
      );
      if (!_validResult(command, payload, value)) {
        throw StateError('保存結果が不明です。再送しないでください');
      }
      if (!await _preferences!.remove(_pendingKey)) {
        throw StateError('結果記録の更新が必要です。再送しないでください');
      }
      requireCurrent();
      _pendingOperation = null;
      _pendingCommand = null;
      _pendingPayload = null;
      return Map<String, dynamic>.from(value);
    } finally {
      _activeMutations.remove(_pendingKey);
    }
  }

  Future<Map<String, dynamic>> inspectUnknownResult() async {
    requireCurrent();
    if (_pendingOperation == null || _pendingCommand == null) {
      throw StateError('照会対象がありません');
    }
    final value = await _call('result', const {}, operation: _pendingOperation);
    if (value is! Map ||
        !['committed', 'unobserved'].contains(value['state'])) {
      throw StateError('処理結果を確認できません');
    }
    if (value['state'] == 'committed' &&
        value['command'] == _pendingCommand &&
        value['original_session_id'] == _originalSession &&
        value.length == 5 &&
        value['payload'] is Map &&
        _fingerprint(
              _pendingCommand!,
              Map<String, dynamic>.from(value['payload'] as Map),
            ) ==
            _pendingFingerprint &&
        _validResult(
          _pendingCommand!,
          value['payload'] as Map,
          value['result'],
        )) {
      if (!await _preferences!.remove(_pendingKey)) {
        throw StateError('結果記録を更新できません');
      }
      requireCurrent();
      _pendingOperation = null;
      _pendingCommand = null;
      _pendingPayload = null;
    } else if (value['state'] == 'committed' || value.length != 1) {
      throw StateError('以前の処理結果と一致しません。未解決のため再送しないでください');
    }
    return Map<String, dynamic>.from(value);
  }
}

class TradeCompanyCalculationConflict {
  const TradeCompanyCalculationConflict({
    required this.siteId,
    required this.siteName,
    required this.outputType,
    required this.siteSettingConfigured,
    required this.tradeCompanySettingConfigured,
    required this.conflict,
    required this.selectedSource,
  });

  final String siteId;
  final String siteName;
  final String outputType;
  final bool siteSettingConfigured;
  final bool tradeCompanySettingConfigured;
  final bool conflict;
  final String? selectedSource;

  String get outputLabel => switch (outputType) {
    'invoice' => '請求書',
    'payment_certificate' => '支払証明書',
    'payroll' => '給料明細',
    _ => outputType,
  };

  factory TradeCompanyCalculationConflict.fromJson(Map<String, dynamic> row) {
    return TradeCompanyCalculationConflict(
      siteId: row['site_id']?.toString() ?? '',
      siteName: row['site_name']?.toString() ?? '',
      outputType: row['output_type']?.toString() ?? '',
      siteSettingConfigured: row['site_setting_configured'] == true,
      tradeCompanySettingConfigured:
          row['trade_company_setting_configured'] == true,
      conflict: row['conflict'] == true,
      selectedSource: row['selected_source']?.toString(),
    );
  }
}

extension TradeCompanyConflictRepository on TradeCompanyRepository {
  Future<List<TradeCompanyCalculationConflict>> calculationConflicts(
    String tradeCompanyId,
  ) async {
    final raw = await _client.rpc(
      'trade_company_calculation_conflicts',
      params: {'p_trade_company_id': tradeCompanyId},
    );
    if (raw is! List) return const [];
    return [
      for (final item in raw)
        if (item is Map)
          TradeCompanyCalculationConflict.fromJson(
            Map<String, dynamic>.from(item),
          ),
    ];
  }
}

