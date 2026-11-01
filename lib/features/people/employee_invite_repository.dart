import 'dart:async';
import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../auth/apple_session_navigation_binding.dart';

import '../../data/supabase_backend.dart';

class ApprovalAssigneeOption {
  const ApprovalAssigneeOption({
    required this.userId,
    required this.displayName,
    required this.role,
  });

  final String userId;
  final String displayName;
  final String role;
}

class EmployeeInviteResult {
  const EmployeeInviteResult({
    required this.inviteId,
    required this.name,
    required this.phone,
    required this.temporaryPassword,
    required this.qrPayload,
    this.smsSent = false,
    this.testFlightUrl,
    this.deliveryMessage,
  });

  final String inviteId;
  final String name;
  final String phone;
  final String temporaryPassword;
  final String qrPayload;
  final bool smsSent;
  final String? testFlightUrl;
  final String? deliveryMessage;
}

class InitialRegistrationEmployee {
  const InitialRegistrationEmployee({
    required this.id,
    required this.name,
    required this.phone,
    required this.invited,
  });

  final String id;
  final String name;
  final String phone;
  final bool invited;
}

class EmployeeInviteRepository {
  EmployeeInviteRepository(SupabaseClient client)
    : this._withTracking(client, client.auth.onAuthStateChange);

  EmployeeInviteRepository.forTesting(
    SupabaseClient client, {
    required Stream<AuthState>? authEvents,
  }) : this._withTracking(client, authEvents);

  EmployeeInviteRepository._withTracking(this._client, this._authEvents) {
    _trackingHealthy = _authEvents != null;
    _observedBinding = binding;
    try {
      _subscription = _authEvents?.listen(
        (event) => _observe(event.session),
        onError: (Object _) => _retireTracking(),
        onDone: _retireTracking,
      );
    } catch (_) {
      _retireTracking();
    }
  }

  final SupabaseClient _client;
  final Stream<AuthState>? _authEvents;
  late bool _trackingHealthy;
  StreamSubscription<AuthState>? _subscription;
  void _retireTracking() {
    if (!_trackingHealthy) return;
    _trackingHealthy = false;
    _generation++;
  }
  AppleSessionNavigationBinding? _observedBinding;
  int _generation = 0;
  bool _disposed = false;
  void _observe(Session? session) {
    AppleSessionNavigationBinding? value;
    try {
      value = AppleSessionNavigationBinding.fromSession(session);
    } catch (_) {
      value = null;
    }
    if (value != _observedBinding) {
      _generation++;
      _observedBinding = value;
    }
  }

  Future<void> dispose() async {
    _disposed = true;
    _generation++;
    await _subscription?.cancel();
  }

  final Set<String> _attempted = {};
  String? get currentActorId => binding?.actorId;
  Stream<AuthState> get authChanges => _authEvents ?? const Stream.empty();
  AppleSessionNavigationBinding? get binding {
    if (!_trackingHealthy || _disposed) return null;
    try {
      return AppleSessionNavigationBinding.fromSession(
        _client.auth.currentSession,
      );
    } catch (_) {
      return null;
    }
  }

  Future<EmployeeInviteRequest> beginRequest({String? companyId}) async {
    final session = _client.auth.currentSession;
    _observe(session);
    final generation = _generation;
    final captured = binding;
    if (session == null || captured == null) {
      throw StateError('ログイン情報を確認してください。');
    }
    final Object raw;
    try {
      raw = await _client
          .from('company_members')
          .select('company_id,role')
          .eq('user_id', captured.actorId)
          .setHeader('Authorization', 'Bearer ${session.accessToken}')
          .retry(enabled: false);
    } catch (_) {
      throw StateError('対象会社の登録情報を取得できません。');
    }
    if (_disposed || _generation != generation || binding != captured) {
      throw StateError('ログイン状態が変わりました。画面を開き直してください。');
    }
    Map row;
    try {
      if (raw is! List || raw.length != 1 || raw.single is! Map) {
        throw const FormatException();
      }
      row = raw.single as Map;
      if ((companyId != null && row['company_id'] != companyId) ||
          !_uuid.hasMatch(row['company_id']?.toString() ?? '') ||
          !const {
            'owner',
            'admin',
            'manager',
            'viewer',
          }.contains(row['role'])) {
        throw const FormatException();
      }
    } catch (_) {
      throw StateError('対象会社を一意に確認できません。会社を選び直してください。');
    }
    final request = EmployeeInviteRequest._(
      captured,
      row['company_id'] as String,
      session.accessToken,
      () => !_disposed && _generation == generation && binding == captured,
    );
    request.check();
    return request;
  }

  static final _uuid = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );

  Future<EmployeeInviteResult> _create(
    Map<String, dynamic> body, {
    EmployeeInviteRequest? request,
  }) async {
    final context = request ?? await beginRequest();
    context.check();
    final rawPhone = body['phone']?.toString().replaceAll(
      RegExp(r'[\s()\-]'),
      '',
    );
    final recipient =
        body['workerId'] ??
        (rawPhone?.startsWith('0') == true
            ? '+81${rawPhone!.substring(1)}'
            : rawPhone);
    final key = '${context.actorId}:${context.companyId}:$recipient';
    if (_attempted.contains(key)) {
      throw StateError('作成結果が未解決です。再作成せず管理者に確認してください。');
    }
    // No recipient fields: a legacy issuer rejects this before Auth creation.
    final inspection = await _client.functions.invoke(
      'create-employee-invite',
      headers: {'Authorization': context.authorization},
      body: {
        'operation': 'inspect_context',
        'companyId': context.companyId,
        'sessionId': context.sessionId,
      },
    );
    context.check();
    final capability = inspection.data;
    if (inspection.status != 200 ||
        capability is! Map ||
        capability.length != 5 ||
        !capability.keys.every(
          (key) => const {
            'version',
            'capability',
            'actorId',
            'companyId',
            'sessionId',
          }.contains(key),
        ) ||
        capability['version'] is! int ||
        capability['version'] != 1 ||
        capability['capability'] != 'employee_invite_bound_v1' ||
        capability['actorId'] != context.actorId ||
        capability['companyId'] != context.companyId ||
        capability['sessionId'] != context.sessionId) {
      throw StateError('招待機能の更新を確認できません。作成は開始していません。');
    }
    if (!_attempted.add(key)) {
      throw StateError('作成結果が未解決です。再作成せず管理者に確認してください。');
    }
    try {
      final response = await _client.functions.invoke(
        'create-employee-invite',
        headers: {'Authorization': context.authorization},
        body: {
          ...body,
          'companyId': context.companyId,
          'sessionId': context.sessionId,
          'operation': 'create_bound_v1',
        },
      );
      context.check();
      return _resultFromResponse(
        response,
        request: context,
        expectedWorker: body['workerId'] as String?,
        expectedPhone: (body['expectedPhone'] ?? body['phone']) as String?,
      );
    } catch (_) {
      // No credentials or password journal. This process retains only the intent
      // block; no receipt exists to safely recreate an uncertain remote result.
      throw StateError('作成結果を確認できません。結果未解決のため再作成せず管理者に確認してください。');
    }
  }

  static EmployeeInviteRepository? maybeCreate() {
    if (!SupabaseBackend.isInitialized) return null;
    if (SupabaseBackend.client.auth.currentUser == null) return null;
    return EmployeeInviteRepository(SupabaseBackend.client);
  }

  Future<List<ApprovalAssigneeOption>> loadCurrentApprovalAssignees({
    EmployeeInviteRequest? request,
  }) async {
    final context = request ?? await beginRequest();
    context.check();
    final value = await _client
        .rpc('company_approval_assignee_rows')
        .setHeader('Authorization', context.authorization)
        .retry(enabled: false);
    context.check();
    if (value is! List) return const [];

    return [
      for (final raw in value)
        if (raw is Map && raw['is_assignee'] == true)
          ApprovalAssigneeOption(
            userId: raw['user_id']?.toString() ?? '',
            displayName: raw['display_name']?.toString() ?? 'SKOユーザー',
            role: raw['role']?.toString() ?? 'manager',
          ),
    ].where((item) => item.userId.isNotEmpty).toList(growable: false);
  }

  Future<void> registerEmployee({
    required String name,
    required String phone,
  }) async {
    final trimmedName = name.trim();
    final trimmedPhone = phone.trim();
    if (trimmedName.isEmpty || trimmedPhone.isEmpty) {
      throw StateError('名前と電話番号を入力してください。');
    }

    try {
      await _client.rpc(
        'register_employee_preregistration',
        params: {'p_name': trimmedName, 'p_phone': trimmedPhone},
      );
    } on PostgrestException catch (error) {
      if (error.message.contains('employee phone already registered')) {
        throw StateError('この電話番号の従業員はすでに登録されています。');
      }
      rethrow;
    }
  }

  Future<String> loadTestFlightUrl({EmployeeInviteRequest? request}) async {
    final context = request ?? await beginRequest();
    context.check();
    final raw = await _client
        .rpc('initial_registration_distribution_settings')
        .setHeader('Authorization', context.authorization)
        .retry(enabled: false);
    context.check();
    final map = raw is Map
        ? Map<String, dynamic>.from(raw)
        : const <String, dynamic>{};
    return map['testflight_url']?.toString() ?? '';
  }

  Future<void> saveTestFlightUrl(
    String value, {
    EmployeeInviteRequest? request,
  }) async {
    final context = request ?? await beginRequest();
    context.check();
    await _client
        .rpc(
          'save_initial_registration_distribution_settings',
          params: {'p_testflight_url': value.trim()},
        )
        .setHeader('Authorization', context.authorization)
        .retry(enabled: false);
    context.check();
  }

  Future<List<InitialRegistrationEmployee>> loadRegisteredEmployees({
    EmployeeInviteRequest? request,
  }) async {
    final context = request ?? await beginRequest();
    context.check();
    final value = await _client
        .rpc('initial_registration_employee_rows')
        .setHeader('Authorization', context.authorization)
        .retry(enabled: false);
    context.check();
    final rows = value is List ? value : const <dynamic>[];

    return [
      for (final raw in rows)
        if ((raw['phone']?.toString().trim() ?? '').isNotEmpty)
          InitialRegistrationEmployee(
            id: raw['id']?.toString() ?? '',
            name: raw['name']?.toString() ?? '名前未登録',
            phone: raw['phone']?.toString() ?? '',
            invited: (raw['user_id']?.toString().trim() ?? '').isNotEmpty,
          ),
    ].where((item) => item.id.isNotEmpty).toList(growable: false);
  }

  Future<EmployeeInviteResult> createInviteForWorker(
    String workerId, {
    required String expectedPhone,
    bool deliverSms = true,
    EmployeeInviteRequest? request,
  }) => _create({
    'workerId': workerId,
    'expectedPhone': expectedPhone,
    'deliverSms': deliverSms,
  }, request: request);

  Future<EmployeeInviteResult> createInvite({
    required String name,
    required String phone,
    String requestedRole = 'viewer',
    bool requestedApprovalAssignee = false,
    String? replaceApprovalAssigneeUserId,
    EmployeeInviteRequest? request,
  }) => _create({
    'name': name.trim(),
    'phone': phone.trim(),
    'requestedRole': requestedRole,
    'requestedApprovalAssignee': requestedApprovalAssignee,
    'replaceApprovalAssigneeUserId': replaceApprovalAssigneeUserId,
    'deliverSms': false,
  }, request: request);

  EmployeeInviteResult _resultFromResponse(
    FunctionResponse response, {
    required EmployeeInviteRequest request,
    String? expectedWorker,
    String? expectedPhone,
  }) {
    final raw = response.data;
    if (response.status < 200 || response.status >= 300 || raw is! Map) {
      throw const FormatException('Unconfirmed invitation result');
    }
    final map = Map<String, dynamic>.from(raw);
    if (map.containsKey('error') || map.containsKey('code')) {
      throw const FormatException('Unconfirmed invitation result');
    }
    final id = map['inviteId'],
        phone = map['phone'],
        password = map['temporaryPassword'];
    final qr = map['qrPayload'];
    if (!_uuid.hasMatch(id is String ? id : '') ||
        phone is! String ||
        !RegExp(r'^\+81(?:70|80|90)\d{8}$').hasMatch(phone) ||
        password is! String ||
        password.isEmpty ||
        qr is! String ||
        map['name'] is! String ||
        map['name'].toString().trim().isEmpty ||
        map['smsSent'] is! bool ||
        map['companyId'] != request.companyId ||
        map['actorId'] != request.actorId ||
        map['sessionId'] != request.sessionId ||
        !_uuid.hasMatch(map['workerId']?.toString() ?? '') ||
        !_uuid.hasMatch(map['authUserId']?.toString() ?? '') ||
        (expectedWorker != null && map['workerId'] != expectedWorker)) {
      throw const FormatException('Unconfirmed invitation result');
    }
    if (expectedPhone != null) {
      var normalized = expectedPhone.replaceAll(RegExp(r'[\s()\-]'), '');
      if (normalized.startsWith('0')) {
        normalized = '+81${normalized.substring(1)}';
      }
      if (normalized != phone) {
        throw const FormatException('Invitation recipient changed');
      }
    }
    final decoded = jsonDecode(qr);
    if (decoded is! Map ||
        decoded.length != 4 ||
        decoded['type'] != 'sko_employee_invite' ||
        decoded['inviteId'] != id ||
        decoded['phone'] != phone ||
        decoded['password'] != password) {
      throw const FormatException('Unconfirmed invitation QR');
    }
    return EmployeeInviteResult(
      inviteId: id as String,
      name: map['name'] as String,
      phone: phone,
      temporaryPassword: password,
      qrPayload: qr,
      smsSent: map['smsSent'] as bool,
      testFlightUrl: map['testFlightUrl'] as String?,
      deliveryMessage: map['deliveryMessage'] as String?,
    );
  }
}

class EmployeeInviteRequest {
  EmployeeInviteRequest._(
    this._binding,
    this.companyId,
    this._token,
    this._current,
  );
  final AppleSessionNavigationBinding _binding;
  final String companyId;
  final String _token;
  final bool Function() _current;
  String get actorId => _binding.actorId;
  String get sessionId => _binding.sessionId;
  String get authorization => 'Bearer $_token';
  bool _retired = false;
  bool get isCurrent {
    if (!_current()) _retired = true;
    return !_retired;
  }

  void observeSession(Session? session) {
    try {
      if (AppleSessionNavigationBinding.fromSession(session) != _binding) {
        _retired = true;
      }
    } catch (_) {
      _retired = true;
    }
  }

  void check() {
    if (!isCurrent) throw StateError('ログイン状態が変わりました。画面を開き直してください。');
  }
}

