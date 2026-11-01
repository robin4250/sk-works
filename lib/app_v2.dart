import 'features/attendance/checkout_report_gate.dart';
import 'features/auth/authenticated_navigation_boundary.dart';
import 'features/payroll/company_common_allowance_entry_page.dart';
import 'features/chat/line_release_access.dart';
import 'features/referrals/app_referral_page.dart';
import 'features/referrals/app_referral_repository.dart';
import 'features/settings/master_feature_controls_repository.dart';
import 'features/shared/trade_documents_hub_page.dart';
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart' as legacy;
import 'branding/product_brand.dart';
import 'branding/sko_theme.dart';
import 'data/supabase_backend.dart';
import 'features/albums/albums_cloud_page.dart';
import 'features/analytics/usage_analytics_repository.dart';
import 'features/attendance/attendance_cloud_page.dart';
import 'features/attendance/attendance_page.dart';
import 'features/attendance/attendance_selection_page.dart';
import 'features/attendance/attendance_protected_routes.dart';
import 'features/attendance/work_destination_selection_page.dart';
import 'features/attendance/route_journey_capture_page.dart';
import 'features/attendance/attendance_verification_page.dart';
import 'features/attendance/attendance_verification_repository.dart';
import 'features/attendance/gps_auto_attendance_service.dart';
import 'features/attendance/today_attendance_page.dart';
import 'features/attendance/worker_attendance_sheet_page.dart';
import 'features/auth/auth_gate.dart';
import 'features/approvals/approvals_hub_page.dart';
import 'features/auth/secondary_protected_page.dart';
import 'features/chat/chat_cloud_page.dart';
import 'features/chat/line_history_preview_page.dart';
import 'features/chat/line_talk_hub_page.dart';
import 'features/chat/today_line_attendance_page.dart';
import 'features/companies/trade_company_page.dart';
import 'features/companies/trade_company_repository.dart';
import 'features/daily_reports/daily_report_month_page.dart';
import 'features/expenses/expense_home_page.dart';
import 'features/home/company_payroll_rates_home_entry.dart';
import 'features/help/help_page.dart';
import 'features/help/floating_help_controller.dart';
import 'features/help/floating_help_overlay.dart';
import 'features/help/manual_content.dart';
import 'features/home/friendly_home_content.dart';
import 'features/home/home_route_action_state.dart';
import 'features/home/employee_resources_page.dart';
import 'features/attendance/route_journey_capture_repository.dart';
import 'features/home/home_attention_repository.dart';
import 'features/home/attendance_update_badge_repository.dart';
import 'features/home/home_weather_location_repository.dart';
import 'features/home/weather_forecast_home_card.dart';
import 'features/home/weather_forecast_gateway.dart';
import 'package:url_launcher/url_launcher.dart';
import 'features/traffic/traffic_home_card.dart';
import 'features/traffic/traffic_shortcut_store.dart';
import 'features/traffic/traffic_link_policy.dart';
import 'features/home/home_action_order_policy.dart';
import 'features/home/weather_forecast_policy.dart';
import 'features/home/home_appearance.dart';
import 'features/home/home_membership_repository.dart';
import 'features/invoices/invoice_cloud_page.dart';
import 'features/invoices/invoice_page.dart';
import 'features/notes/notes_cloud_page.dart';
import 'features/notifications/notification_bell.dart';
import 'features/notifications/notifications_page.dart';
import 'features/tutorial/tutorial_home_card.dart';
import 'features/tutorial/tutorial_page.dart';
import 'features/operations/vehicle_route_page.dart';
import 'features/operations/vehicle_route_selection_page.dart';
import 'features/payroll/individual_payroll_settings_page.dart';
import 'features/payroll/payroll_adjustment_page.dart';
import 'features/payroll/payroll_adjustment_repository.dart';
import 'features/payroll/payroll_review_page.dart';
import 'features/payroll/payroll_statements_page.dart';
import 'features/payroll/payment_certificates_page.dart';
import 'features/people/company_submitted_documents_page.dart';
import 'features/people/company_delivery_inbox_page.dart';
import 'features/people/employee_registration_page.dart';
import 'features/people/employee_initial_registration_page.dart';
import 'features/people/people_cloud_page.dart';
import 'features/people/people_page.dart';
import 'features/people/worker_document_page.dart';
import 'features/people/own_document_registration_page.dart';
import 'features/profile/profile_page.dart';
import 'features/qualifications/qualification_certificate_page.dart';
import 'features/qualifications/qualification_cloud_page.dart';
import 'features/qualifications/own_qualification_registration_page.dart';
import 'features/qualifications/qualification_page.dart';
import 'features/settings/company_module_settings_repository.dart';
import 'features/settings/rollout_readiness_page.dart';
import 'features/settings/settings_page.dart';
import 'features/sites/admin_site_financial_page.dart';
import 'features/sites/site_cloud_page.dart';
import 'features/sites/site_map_page.dart';
import 'features/sites/site_page.dart';
import 'international/language_controller.dart';
import 'widgets/sko_scroll_chrome.dart';

class SkWorksApp extends StatelessWidget {
  const SkWorksApp({
    super.key,
    this.allowLocalFallback = false,
  });

  /// Development/test-only escape hatch for the legacy local prototype.
  /// Production launches must fail closed when Supabase is unavailable.
  final bool allowLocalFallback;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: SkoLanguageController.pack,
      builder: (context, language, _) {
        return ValueListenableBuilder<SkoPalette>(
          valueListenable: SkoThemeController.palette,
          builder: (context, palette, _) {
            return AuthenticatedNavigationBoundary(child: CheckoutReportBackBoundary(child: MaterialApp(
              navigatorKey: SkoScrollChromeController.navigatorKey,
              debugShowCheckedModeBanner: false,
              title: ProductBrand.displayName,
              locale: Locale(language.languageCode),
              supportedLocales: const [Locale('ja'), Locale('en')],
              localizationsDelegates: GlobalMaterialLocalizations.delegates,
              theme: SkoTheme.light(palette),
              builder: (context, child) => CheckoutReportGate(child: Stack(
                fit: StackFit.expand,
                children: [
                  SkoGlobalScrollChrome(
                    child: child ?? const SizedBox.shrink(),
                  ),
                  const FloatingHelpOverlay(),
                ],
              )),
              home: SupabaseBackend.isInitialized
                  ? SupabaseAuthGate(
                      homeBuilder: (onSignOut) => HomePage(onSignOut: onSignOut),
                    )
                  : allowLocalFallback
                      ? const HomePage()
                      : const _BackendUnavailableScreen(),
            )));
          },
        );
      },
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key, this.onSignOut});

  final VoidCallback? onSignOut;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  static const _usagePrefix = 'sko_menu_usage_';

  final _moduleSettingsRepository =
      CompanyModuleSettingsRepository.maybeCreate();
  final _membershipRepository = HomeMembershipRepository.maybeCreate();
  final _homeAttentionRepository = HomeAttentionRepository.maybeCreate();
  final _attendanceVerificationRepository =
      AttendanceVerificationRepository.maybeCreate();
  final _payrollAdjustmentRepository =
      PayrollAdjustmentRepository.maybeCreate();
  final _usageAnalyticsRepository = UsageAnalyticsRepository.maybeCreate();

  Map<String, bool> _moduleStates = const {};
  int _friendsRequest = 0;
  int? _friendsReturnIndex;
  String? _friendsReturnActor;
  String? _friendHomeActor;
  bool _friendHomeVisible = true;
  String? get _currentHomeActor => SupabaseBackend.isInitialized
      ? SupabaseBackend.client.auth.currentUser?.id : 'local';
  bool _homeActionHidden(String key) => key == 'friends'
      ? _friendHomeActor != _currentHomeActor || !_friendHomeVisible
      : _hiddenHomeActionKeys.contains(key);
  Map<String, bool> _subAdminHomeStates = const {};
  Map<String, int> _usage = const {};
  int _homeGridColumns = 2;
  List<String> _homeActionOrder = const [];
  Set<String> _hiddenHomeActionKeys = <String>{};
  Map<String, String> _homeLabelOverrides = const {};
  HomeAppearance _homeAppearance = const HomeAppearance();
  HomeIdentity _identity = const HomeIdentity(
    role: 'viewer',
    companyName: 'SKO',
    displayName: 'ユーザー',
  );
  int _tutorialRefreshToken = 0;
  int _homeDocumentAttentionGeneration = 0;
  String? _tutorialCompanyId;
  String? _tutorialUserId;
  int _selectedIndex = 0;
  // A newly created Home starts with usable navigation, then follows every
  // global scroll update without rebuilding the page shell.
  final _homeChromeVisible = ValueNotifier<bool>(true);
  void _syncHomeChrome() {
    _homeChromeVisible.value = SkoScrollChromeController.visible.value;
  }
  String _payrollAdjustmentLabel = '給与調整';
  RequiredDocumentAttention _requiredDocumentAttention =
      const RequiredDocumentAttention(
        missingCount: 0,
        missingNames: [],
        needsLicense: false,
        needsQualification: false,
      );
  HomeAttendanceStatus _homeAttendanceStatus = const HomeAttendanceStatus();
  HomeRouteActionState _homeRouteActionState = HomeRouteActionState.unavailable;
  int _homeAttendanceGeneration = 0;
  AttendanceBadgeSnapshot? _attendanceBadge;
  bool _attendanceBadgeUnavailable = false;
  int _attendanceBadgeGeneration = 0;
  bool _attendanceBadgeOpening = false;
  AttendanceBadgeScope? get _attendanceBadgeScope {
    final actor = SupabaseBackend.isInitialized
        ? SupabaseBackend.client.auth.currentUser?.id : null;
    final company = _tutorialCompanyId;
    if (actor == null || actor != _tutorialUserId || company == null) return null;
    return AttendanceBadgeScope(actor, company, attendanceBadgeJstDate(DateTime.now()));
  }
  int? get _attendanceBadgeCount {
    final scope = _attendanceBadgeScope;
    final snapshot = _attendanceBadge;
    return scope != null && snapshot != null && snapshot.scope.same(scope)
        ? snapshot.count : null;
  }

  Future<void> _loadAttendanceUpdateBadge() async {
    final request = ++_attendanceBadgeGeneration;
    final scope = _attendanceBadgeScope;
    final repository = AttendanceUpdateBadgeRepository.maybeCreate();
    if (scope == null || repository == null) {
      if (mounted) {
        setState(() {
          _attendanceBadge = null;
          _attendanceBadgeUnavailable = true;
        });
      }
      return;
    }
    bool current() {
      final value = _attendanceBadgeScope;
      return mounted && request == _attendanceBadgeGeneration &&
          value != null && value.same(scope);
    }
    try {
      final snapshot = await repository.load(scope);
      if (!current()) return;
      setState(() {
        _attendanceBadge = snapshot;
        _attendanceBadgeUnavailable = false;
      });
    } catch (_) {
      if (!current()) return;
      setState(() => _attendanceBadgeUnavailable = true);
    }
  }

  Future<void> _acknowledgeAttendanceBadge(
      AttendanceBadgeSnapshot? snapshot, DateTime openedAt) async {
    final scope = _attendanceBadgeScope;
    final repository = AttendanceUpdateBadgeRepository.maybeCreate();
    if (snapshot == null || scope == null || !snapshot.scope.same(scope) ||
        repository == null) {
      return;
    }
    ++_attendanceBadgeGeneration;
    try {
      await repository.acknowledge(snapshot, openedAt);
      final current = _attendanceBadgeScope;
      if (!mounted || current == null || !current.same(scope)) return;
      await _loadAttendanceUpdateBadge();
    } catch (_) {
      final current = _attendanceBadgeScope;
      if (!mounted || current == null || !current.same(scope)) return;
      setState(() => _attendanceBadgeUnavailable = true);
    }
  }

  bool _homeOptionalClockInAllowed = false;
  TrafficAvailability _homeTrafficAvailability = TrafficAvailability.unavailable;
  List<String> _homePendingRouteSourceIds = const [];
  bool _homeHasPendingRouteReports = false;
  final _weatherViewState = ValueNotifier<WeatherForecastViewData>(
    WeatherForecastViewData(loading: true, baseDate: DateTime.now()),
  );
  int _homeWeatherGeneration = 0;
  String? _weatherSnapshotActor;

  final _lineRelease = LineReleaseAccess.maybeCreate();
  void _lineReleaseChanged() { if (mounted) setState(() {}); }

  bool get _isAdmin => _identity.isAdmin;
  bool get _isViewer => _identity.role == 'viewer';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _lineRelease?.addListener(_lineReleaseChanged);
    _loadHomeData();
    SkoScrollChromeController.visible.addListener(_syncHomeChrome);
    // The old route may have hidden global chrome. Restore a fresh Home after
    // its first build, so ancestor Theme listeners are never changed in init.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) SkoScrollChromeController.visible.value = true;
    });
    GpsAutoAttendanceService.instance.startIfConfigured();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    SkoScrollChromeController.visible.removeListener(_syncHomeChrome);
    _homeChromeVisible.dispose();
    _lineRelease?.removeListener(_lineReleaseChanged);
    _weatherViewState.dispose();
    GpsAutoAttendanceService.instance.stop();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || !mounted) return;
    // The gateway owns the registered region's calendar, including day changes.
    _loadWeatherLocation();
    _loadAttendanceUpdateBadge();
    _refreshRequiredDocumentScope();
  }

  Future<void> _refreshRequiredDocumentScope() async {
    await _loadIdentity();
    await _loadRequiredDocumentAttention();
  }

  Future<void> _loadHomeData() async {
    await Future.wait([
      _loadModuleSettings(),
      _loadIdentity(),
      _loadUsage(),
      _loadHomeLayout(),
      _loadHomeAppearance(),
      _loadHomeAttendanceStatus(),
      _loadPayrollAdjustmentAccess(),
      _syncLanguage(),
    ]);
    await Future.wait([_loadRequiredDocumentAttention(), _loadWeatherLocation(), _loadAttendanceUpdateBadge()]);
  }

  Future<void> _loadWeatherLocation() async {
    final generation = ++_homeWeatherGeneration;
    final previous = _weatherViewState.value;
    final previousActor = _weatherSnapshotActor;
    final now = DateTime.now();
    final baseDate = previous.baseDate ?? DateTime(now.year, now.month, now.day);
    final actor = SupabaseBackend.isInitialized ? SupabaseBackend.client.auth.currentUser?.id : null;
    final repository = HomeWeatherLocationRepository.maybeCreate();
    bool current() => mounted && generation == _homeWeatherGeneration &&
        SupabaseBackend.isInitialized && SupabaseBackend.client.auth.currentUser?.id == actor;
    if (!mounted) return;
    _weatherViewState.value = WeatherForecastViewData(loading: true,
      selectedDay: previous.selectedDay, baseDate: baseDate);
    if (repository == null) {
      _weatherViewState.value = WeatherForecastViewData(addressFailed: true,
        selectedDay: previous.selectedDay, baseDate: baseDate);
      return;
    }
    try {
      final result = await repository.load(_homeAttendanceStatus);
      if (!current()) return;
      final latest = _weatherViewState.value;
      _weatherViewState.value = WeatherForecastViewData(
        locationLabel: result.selection.address,
        regionLabel: SkoLanguageController.tr(switch (result.selection.kind) {
          WeatherAddressKind.company => '会社周辺',
          WeatherAddressKind.home => '自宅周辺',
          WeatherAddressKind.site => '現場周辺',
          WeatherAddressKind.unavailable => '地域未設定',
        }),
        companyAddressMissing: result.companyAddressMissing,
        selectedDay: latest.selectedDay, baseDate: latest.baseDate,
        loading: result.selection.kind != WeatherAddressKind.unavailable,
      );
      if (result.selection.kind == WeatherAddressKind.unavailable) {
        return;
      }
      final requestedDay = latest.selectedDay;
      try {
        final forecast = await WeatherForecastGateway(SupabaseBackend.client).fetchDay(requestedDay);
        if (!current()) return;
        _weatherSnapshotActor = actor;
        _weatherViewState.value = WeatherForecastViewData(
          snapshot: forecast.snapshot, attribution: forecast.attribution,
          radarUri: forecast.radarUri,
          locationLabel: result.selection.address,
          regionLabel: forecast.snapshot.locationLabel,
          selectedDay: requestedDay, baseDate: forecast.baseDate,
        );
      } catch (_) {
        if (!current()) return;
        final pending = _weatherViewState.value;
        final keepPrevious = previousActor == actor &&
            previous.locationLabel == pending.locationLabel &&
            previous.selectedDay == pending.selectedDay && previous.forecast != null;
        _weatherViewState.value = WeatherForecastViewData(
          failed: true, locationLabel: pending.locationLabel,
          regionLabel: pending.regionLabel,
          snapshot: keepPrevious ? previous.snapshot : null,
          attribution: keepPrevious ? previous.attribution : const {},
          radarUri: keepPrevious ? previous.radarUri : null,
          selectedDay: pending.selectedDay, baseDate: pending.baseDate,
        );
      }
    } catch (_) {
      if (!current()) return;
      final latest = _weatherViewState.value;
      _weatherViewState.value = WeatherForecastViewData(addressFailed: true,
        selectedDay: latest.selectedDay, baseDate: latest.baseDate);
    }
  }

  void _selectWeatherDay(int day) {
    if (day < 0 || day > 2) return;
    final previous = _weatherViewState.value;
    _weatherViewState.value = WeatherForecastViewData(
      selectedDay: day, baseDate: previous.baseDate, locationLabel: previous.locationLabel, regionLabel: previous.regionLabel,
      addressFailed: previous.addressFailed, companyAddressMissing: previous.companyAddressMissing,
      loading: true,
    );
    _loadWeatherLocation();
  }

  Future<void> _openWeatherReference(Uri uri) async {
    if (uri.scheme != 'https' || uri.userInfo.isNotEmpty ||
        !{'weather.yahoo.co.jp', 'weatherkit.apple.com', 'openweathermap.org'}.contains(uri.host)) {
      return;
    }
    var opened = false;
    try {
      opened = await launchUrl(uri, mode: LaunchMode.inAppBrowserView);
    } catch (_) {
      opened = false;
    }
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(
        SkoLanguageController.tr('外部サービスを開けませんでした。もう一度お試しください。'),
      )));
    }
  }

  void _openWeatherRadar() {
    final data = _weatherViewState.value;
    if (data.forecast?.radarSupported != true || data.radarUri == null) {
      return;
    }
    _openWeatherReference(data.radarUri!);
  }

  Widget _weatherHomeCard() => WeatherForecastHomeCard(
    state: _weatherViewState,
    onRefresh: _loadWeatherLocation,
    onSelectDay: _selectWeatherDay,
    onOpenRadar: _openWeatherRadar,
    onOpenAttribution: _openWeatherReference,
  );

  Future<void> _syncLanguage() async {
    try {
      await SkoLanguageController.syncFromCloud();
    } catch (_) {
      // Language sync is supplemental and must never block the home screen.
    }
  }

  Future<void> _loadHomeAppearance() async {
    final value = await HomeAppearanceRepository.load();
    if (!mounted) return;
    setState(() => _homeAppearance = value);
  }

  Future<void> _openHomeAppearanceSettings() async {
    final value = await Navigator.of(context).push<HomeAppearance>(
      MaterialPageRoute(
        builder: (_) => HomeAppearanceSettingsPage(
          initial: _homeAppearance,
        ),
      ),
    );
    if (!mounted) return;
    final latest = value ?? await HomeAppearanceRepository.load();
    if (!mounted) return;
    setState(() => _homeAppearance = latest);
  }

  TrafficShortcutScope? get _trafficShortcutScope {
    final actor = SupabaseBackend.isInitialized
        ? SupabaseBackend.client.auth.currentUser?.id : null;
    final company = _tutorialCompanyId;
    if (actor == null || actor != _tutorialUserId || company == null) return null;
    return TrafficShortcutScope(actorId: actor, companyId: company);
  }

  Future<void> _loadIdentity() async {
    final repository = _membershipRepository;
    if (repository == null) {
      if (!mounted) return;
      setState(() {
        _identity = const HomeIdentity(
          role: 'owner',
          companyName: 'SKO',
          displayName: '管理者',
        );
      });
      return;
    }

    try {
      final identity = await repository.loadIdentity();
      if (!mounted) return;
      final companyId = identity.companyId;
      final userId = SupabaseBackend.isInitialized
          ? SupabaseBackend.client.auth.currentUser?.id : null;
      if (!mounted) return;
      setState(() {
        if (_tutorialUserId != userId || _tutorialCompanyId != companyId) {
          _homeDocumentAttentionGeneration++;
          _requiredDocumentAttention = const RequiredDocumentAttention(missingCount: 0,
            missingNames: [], needsLicense: false, needsQualification: false, documentEvidenceUnavailable: true);
        }
        _identity = identity;
        _tutorialUserId = userId;
        _tutorialCompanyId = companyId;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _tutorialCompanyId = null; _tutorialUserId = null;
        _homeDocumentAttentionGeneration++;
        _requiredDocumentAttention = const RequiredDocumentAttention(missingCount: 0,
          missingNames: [], needsLicense: false, needsQualification: false, documentEvidenceUnavailable: true);
        _identity = const HomeIdentity(role: 'viewer', companyName: 'SKO', displayName: 'ユーザー');
      });
    }
  }

  Future<void> _loadRequiredDocumentAttention() async {
    final request = ++_homeDocumentAttentionGeneration;
    final repository = _homeAttentionRepository;
    final company = _tutorialCompanyId;
    final actor = _tutorialUserId;
    if (repository == null || company == null || actor == null) {
      if (mounted && repository != null) {
        setState(() => _requiredDocumentAttention = const RequiredDocumentAttention(
          missingCount: 0, missingNames: [], needsLicense: false, needsQualification: false,
          documentEvidenceUnavailable: true));
      }
      return;
    }
    try {
      final value = await repository.loadRequiredDocumentAttention(companyId: company,
        currentCompany: () => _tutorialCompanyId);
      if (!mounted || request != _homeDocumentAttentionGeneration || company != _tutorialCompanyId || actor != _tutorialUserId) return;
      setState(() {
        _requiredDocumentAttention = value;
        _tutorialRefreshToken++;
      });
    } catch (_) {
      // Missing-document attention must not block the home screen.
    }
  }

  Future<void> _loadHomeAttendanceStatus() async {
    // Bind all responses to the account that initiated the request, including
    // the first attendance read, before any asynchronous work starts.
    final requestActor = SupabaseBackend.isInitialized
        ? SupabaseBackend.client.auth.currentUser?.id : null;
    final generation = ++_homeAttendanceGeneration;
    bool acceptsResponse() => mounted &&
        generation == _homeAttendanceGeneration &&
        requestActor != null &&
        SupabaseBackend.isInitialized &&
        SupabaseBackend.client.auth.currentUser?.id == requestActor;
    if (mounted) {
      setState(() {
        _homeAttendanceStatus = const HomeAttendanceStatus(phase: HomeAttendancePhase.unknown);
        _homeOptionalClockInAllowed = false;
        _homeTrafficAvailability = TrafficAvailability.unavailable;
        _homeRouteActionState = HomeRouteActionState.unavailable;
        _homePendingRouteSourceIds = const [];
        _homeHasPendingRouteReports = false;
      });
    }
    final masterFlags = requestActor == null
        ? Future<MasterFeatureAvailability?>.value(null)
        : loadTrafficMasterFlags(
            fetch: () => MasterFeatureControlsRepository.loadForClient(SupabaseBackend.client),
            isCurrent: acceptsResponse,
            onLoaded: (availability) => setState(() => _homeTrafficAvailability = availability),
          );
    final repository = _attendanceVerificationRepository;
    if (repository == null || requestActor == null) {
      return;
    }
    final routeRepository = RouteJourneyCaptureRepository.maybeCreate();
    var recoveryLoaded = false;
    if (routeRepository != null && routeRepository.userId == requestActor) {
      var capturesLoaded = false;
      var reportsLoaded = false;
      try {
        final pending = await routeRepository.allPending();
        if (!acceptsResponse()) return;
        setState(() => _homePendingRouteSourceIds =
            pending.map((row) => row.sourceId).toSet().toList());
        capturesLoaded = true;
      } catch (_) {
        // Optional recovery must not prevent the ordinary attendance read.
      }
      try {
        final reports = await routeRepository.allPendingReports();
        if (!acceptsResponse()) return;
        setState(() {
          _homePendingRouteSourceIds = {
            ..._homePendingRouteSourceIds,
            ...reports.map((row) => row.sourceId),
          }.toList();
          _homeHasPendingRouteReports = reports.isNotEmpty;
        });
        reportsLoaded = true;
      } catch (_) {
        // Keep any capture recovery that was successfully read above.
      }
      recoveryLoaded = capturesLoaded && reportsLoaded;
    }
    try {
      final value = await repository.loadHomeAttendanceStatus();
      if (!acceptsResponse()) return;
      setState(() => _homeAttendanceStatus = value);
      var optionalAllowed = (value.selectedVehicleId?.trim().isEmpty ?? true) &&
          (value.selectedRouteId?.trim().isEmpty ?? true);
      if (!optionalAllowed && value.phase != HomeAttendancePhase.working) {
        final flags = await masterFlags;
        if (!acceptsResponse()) return;
        optionalAllowed = flags?.permitsClockIn(
          vehicleId: value.selectedVehicleId, routeId: value.selectedRouteId,
        ) ?? false;
      }
      setState(() => _homeOptionalClockInAllowed = optionalAllowed);

      if (!recoveryLoaded || routeRepository == null ||
          routeRepository.userId != requestActor ||
          value.phase != HomeAttendancePhase.working || value.openShifts.length != 1 || value.openShifts.single.routeId == null) {
        return;
      }
      final shift = value.openShifts.single;
      final workspace = await routeRepository.workspace(shift.id);
      if (!acceptsResponse()) return;
      setState(() => _homeRouteActionState = _homePendingRouteSourceIds.isNotEmpty
          ? HomeRouteActionState.unavailable
          : homeRouteActionState(workspace, shift.id));
    } catch (_) {
      // Unknown or stale route state never enables an arrival/move action.
    }
  }

  Future<void> _loadPayrollAdjustmentAccess() async {
    final repository = _payrollAdjustmentRepository;
    if (repository == null) return;
    try {
      final access = await repository.loadAccess();
      if (!mounted) return;
      setState(() => _payrollAdjustmentLabel = access.pageLabel);
    } catch (_) {
      // Keep the standard label until the payroll adjustment migration is ready.
    }
  }

  Future<void> _loadModuleSettings() async {
    final repository = _moduleSettingsRepository;
    if (repository == null) return;
    try {
      final values = await Future.wait([
        repository.loadOptionalModuleStates(),
        repository.loadSubAdminHomeStates(),
      ]);
      if (!mounted) return;
      setState(() {
        _moduleStates = Map<String, bool>.from(values[0]);
        _subAdminHomeStates = Map<String, bool>.from(values[1]);
      });
    } catch (_) {
      // Keep modules visible if settings cannot be loaded.
    }
  }

  Future<void> _loadUsage() async {
    final prefs = await SharedPreferences.getInstance();
    final usage = <String, int>{};
    for (final key in prefs.getKeys()) {
      if (!key.startsWith(_usagePrefix)) continue;
      usage[key.substring(_usagePrefix.length)] = prefs.getInt(key) ?? 0;
    }
    if (!mounted) return;
    setState(() => _usage = usage);
  }

  Future<void> _recordUsage(String key) async {
    final next = (_usage[key] ?? 0) + 1;
    setState(() => _usage = {..._usage, key: next});
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('$_usagePrefix$key', next);
  }

  Future<void> _loadHomeLayout() async {
    final actor = _currentHomeActor;
    final prefs = await SharedPreferences.getInstance();
    final friendVisible = actor != null &&
        (prefs.getBool('sko_friend_home_visible_$actor') ?? true);
    final columns = (prefs.getInt('sko_home_grid_columns') ?? 2).clamp(1, 4);
    final order = prefs.getStringList('sko_home_action_order') ?? const <String>[];
    final hidden = prefs.getStringList('sko_home_hidden_actions') ?? const <String>[];
    final labelOverrides = <String, String>{};
    for (final key in prefs.getKeys()) {
      const prefix = 'sko_home_label_override_';
      if (!key.startsWith(prefix)) continue;
      final value = prefs.getString(key)?.trim();
      if (value != null && value.isNotEmpty) {
        labelOverrides[key.substring(prefix.length)] = value;
      }
    }
    if (!mounted || actor != _currentHomeActor) return;
    setState(() {
      _friendHomeActor = actor;
      _friendHomeVisible = friendVisible;
      _homeGridColumns = columns;
      _homeActionOrder = List<String>.from(order);
      _hiddenHomeActionKeys = hidden.toSet();
      _homeLabelOverrides = labelOverrides;
    });
  }

  Future<void> _setHomeGridColumns(int value) async {
    final next = value.clamp(1, 4);
    setState(() => _homeGridColumns = next);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('sko_home_grid_columns', next);
  }

  Future<void> _setHomeActionVisible(String key, bool visible) async {
    if (key == 'friends') {
      final actor = _currentHomeActor;
      if (actor == null || actor != _friendHomeActor) return;
      final prefs = await SharedPreferences.getInstance();
      if (!mounted || actor != _currentHomeActor) return;
      await prefs.setBool('sko_friend_home_visible_$actor', visible);
      if (!mounted || actor != _currentHomeActor) return;
      setState(() => _friendHomeVisible = visible);
      return;
    }
    final next = <String>{..._hiddenHomeActionKeys};
    if (visible) {
      next.remove(key);
    } else {
      next.add(key);
    }
    setState(() => _hiddenHomeActionKeys = next);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('sko_home_hidden_actions', next.toList()..sort());
  }

  Future<void> _setHomeLabelOverride(String key, String? value) async {
    final prefs = await SharedPreferences.getInstance();
    final normalized = value?.trim() ?? '';
    final next = <String, String>{..._homeLabelOverrides};
    if (normalized.isEmpty) {
      next.remove(key);
      await prefs.remove('sko_home_label_override_$key');
    } else {
      next[key] = normalized;
      await prefs.setString('sko_home_label_override_$key', normalized);
    }
    if (!mounted) return;
    setState(() => _homeLabelOverrides = next);
  }

  Future<void> _editHomeLabel(_MenuAction item) async {
    final current = _homeLabelOverrides[item.key] ?? item.label;
    final parts = current.split('\n');
    final first = TextEditingController(text: parts.isNotEmpty ? parts.first : item.label);
    final second = TextEditingController(text: parts.length > 1 ? parts.sublist(1).join(' ') : '');
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('2行表示時の改行位置'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(item.label, style: const TextStyle(fontWeight: FontWeight.w900)),
            const SizedBox(height: 12),
            TextField(
              controller: first,
              maxLines: 1,
              decoration: const InputDecoration(labelText: '1行目'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: second,
              maxLines: 1,
              decoration: const InputDecoration(labelText: '2行目（不要なら空欄）'),
            ),
            const SizedBox(height: 8),
            const Text('1行で収まる時は1行表示のままです。2行表示が必要な時だけ、この改行位置を使います。'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(''),
            child: const Text('標準に戻す'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () {
              final line1 = first.text.trim();
              final line2 = second.text.trim();
              final value = [
                if (line1.isNotEmpty) line1,
                if (line2.isNotEmpty) line2,
              ].join('\n');
              Navigator.of(dialogContext).pop(value);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
    first.dispose();
    second.dispose();
    if (result == null) return;
    await _setHomeLabelOverride(item.key, result);
  }

  Future<void> _reorderHomeAction(int oldIndex, int newIndex) async {
    final items = _menuItems;
    if (oldIndex < 0 ||
        oldIndex >= items.length ||
        newIndex < 0 ||
        newIndex > items.length) {
      return;
    }
    final ordered = reorderHomeMenuActions(_homeActionOrder,
      items.map((item) => item.key).toList(), oldIndex, newIndex);
    setState(() => _homeActionOrder = ordered);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('sko_home_action_order', ordered);
  }

  Future<void> _reorderHomeActionByKey(
    String draggedKey,
    String targetKey,
  ) async {
    if (draggedKey == targetKey) return;

    final available = [..._menuItems.map((item) => item.key), 'home_attention'];
    if (!available.contains(draggedKey) || !available.contains(targetKey)) {
      return;
    }

    final ordered = normalizeHomeActionOrder(_homeActionOrder, [
      if (available.contains('attendance_verify')) 'attendance_verify',
      if (available.contains('attendance_today')) 'attendance_today',
      ...available,
    ]);

    final oldIndex = ordered.indexOf(draggedKey);
    final targetIndex = ordered.indexOf(targetKey);
    if (oldIndex < 0 || targetIndex < 0) return;

    final moved = ordered.removeAt(oldIndex);
    final insertIndex = ordered.indexOf(targetKey);
    ordered.insert(insertIndex < 0 ? ordered.length : insertIndex, moved);

    setState(() => _homeActionOrder = ordered);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('sko_home_action_order', ordered);
  }

  void _recordCloudUsageForAction(String key) {
    final repository = _usageAnalyticsRepository;
    if (repository == null) return;

    final surfaceKey = switch (key) {
      'footer_home' => 'home',
      'attendance' || 'attendance_list' => 'attendance_sheet',
      'footer_sites' || 'site_register' || 'site_map' => 'sites',
      'chat' => 'chat',
      'friends' => 'chat',
      'clock_in' || 'clock_out' || 'attendance_verify' || 'workplace_select' || 'attendance_method_vehicle' => 'attendance',
      'daily_report' || 'approvals' => 'daily_report',
      'employee_register' ||
      'initial_registration' ||
      'people' ||
      'company_deliveries' => 'people',
      'company_documents' => 'documents',
      'payroll' || 'payroll_adjustments' => 'payroll',
      'profile' => 'profile',
      'help' => 'help',
      'admin_sites' => 'sites',
      'qualification_certificates' ||
      'qualification_register' ||
      'employee_qualifications' ||
      'qualifications' => 'qualifications',
      'documents' || 'document_register' => 'documents',
      'vehicle_routes' => 'vehicle_routes',
      'settings' || 'appearance' || 'rollout' => 'settings',
      'invoices' => 'invoice',
      _ => null,
    };

    final featureKey = switch (key) {
      'clock_in' => 'clock_in',
      'clock_out' => 'clock_out',
      'attendance' || 'attendance_list' || 'attendance_verify' || 'workplace_select' || 'attendance_method_vehicle' => 'attendance',
      'daily_report' || 'approvals' => 'daily_report',
      'payroll' || 'payroll_adjustments' => 'payroll',
      'invoices' => 'invoice',
      'chat' => 'chat',
      'friends' => 'chat',
      'people' || 'employee_register' || 'initial_registration' => 'people',
      'qualification_certificates' ||
      'qualification_register' ||
      'employee_qualifications' ||
      'qualifications' => 'qualifications',
      'documents' => 'documents',
      'company_deliveries' || 'trade_companies' || 'subcontractors' =>
        'company_connection',
      'company_documents' => 'documents',
      _ => null,
    };

    if (surfaceKey == null && featureKey == null) return;
    unawaited(
      repository.record(
        eventKey: 'page_open',
        surfaceKey: surfaceKey,
        featureKey: featureKey,
      ),
    );
  }

  bool _moduleEnabled(String key) {
    if (!SupabaseBackend.isInitialized) return true;
    if (key == 'people' || key == 'settings') return true;
    return _moduleStates[key] ?? true;
  }

  bool _subAdminFeatureEnabled(String key) {
    if (!_identity.isSubAdmin) return true;
    if (!CompanyModuleSettingsRepository.subAdminHomeKeys.contains(key)) {
      return true;
    }
    return _subAdminHomeStates[key] ?? false;
  }

  Widget _pageFor(legacy.ModuleDefinition module) {
    return switch (module.storageKey) {
      'people' => SupabaseBackend.isInitialized
          ? const PeopleCloudPage()
          : const PeoplePage(),
      'qualifications' => SupabaseBackend.isInitialized
          ? const QualificationCloudPage()
          : const QualificationPage(),
      'sites' => SupabaseBackend.isInitialized
          ? const SiteCloudPage()
          : const SitePage(),
      'attendance' => SupabaseBackend.isInitialized
          ? (_identity.can('can_manage_attendance')
              ? const AttendanceCloudPage()
              : const WorkerAttendanceSheetPage())
          : const AttendancePage(),
      'invoices' => SupabaseBackend.isInitialized
          ? const SecondaryProtectedPage(
              title: '請求書',
              child: InvoiceCloudPage(),
            )
          : const InvoicePage(),
      'settings' => const SettingsPage(),
      _ => legacy.ModulePage(module: module),
    };
  }

  Future<void> _openHomeAction(String key) async {
    FloatingHelpController.setContext(
      featureKey: key,
      currentRole: ManualContent.fromMembershipRole(_identity.role),
      visibleKeys: _availableActionKeys,
    );
    unawaited(_recordUsage(key));
    if (!mounted) return;

    if (const {
          'attendance_management',
          'payment_certificate_settings',
          'site_map',
          'approvals',
        }.contains(key) &&
        !_nestedActionKeys.contains(key)) {
      return;
    }

    // Ignore retired shortcut keys retained in older home preferences.
    if (key == 'signatures') return;

    if (key == 'friends' && SupabaseBackend.isInitialized) {
      final actor = _currentHomeActor;
      if (actor == null || actor != _tutorialUserId) return;
      try {
        final states = await _moduleSettingsRepository?.loadOptionalModuleStates();
        if (!mounted || actor != _currentHomeActor || states == null) return;
        setState(() => _moduleStates = states);
      } catch (_) {
        if (mounted && actor == _currentHomeActor) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('チャットの利用設定を確認できません。再度お試しください。')),
          );
        }
        return;
      }
    }

    final requiredModule = switch (key) {
      'attendance' ||
      'attendance_list' ||
      'attendance_today' ||
      'attendance_management' ||
      'attendance_method_vehicle' ||
      'workplace_select' ||
      'attendance_verify' ||
      'clock_in' ||
      'clock_out' =>
        'attendance',
      'footer_sites' || 'site_register' || 'site_map' || 'admin_sites' || 'sites' => 'sites',
      'chat' => 'chat',
      'friends' => 'chat',
      'invoices' => 'invoices',
      'qualifications' || 'qualification_certificates' || 'qualification_register' || 'employee_qualifications' => 'qualifications',
      'documents' || 'document_register' => 'documents',
      'notes' => 'notes',
      'albums' => 'albums',
      'today_line' || 'line_history' => 'line_bridge',
      'vehicle_routes' || 'vehicle_select' || 'route_select' => 'vehicle_routes',
      _ => null,
    };
    if (requiredModule != null && !_moduleEnabled(requiredModule)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(SkoLanguageController.tr('この機能は会社設定でOFFになっています'))),
      );
      return;
    }

    if (key == 'people' && !_identity.isManagement && !_isViewer) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(SkoLanguageController.tr('社員情報は管理者・閲覧者・サブ管理者が閲覧できます'))),
      );
      return;
    }

    if (key == 'company_modules') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('利用機能のON／OFFはMaster側に保管しています')),
      );
      return;
    }

    if (key == 'company_documents' && !_isAdmin) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(SkoLanguageController.tr('この機能は管理者のみ利用できます'))),
      );
      return;
    }
    if ((key == 'company_deliveries' || key == 'company_delivery_inbox' || key == 'trade_documents') && !_identity.isManagement) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(SkoLanguageController.tr('この機能は管理者・サブ管理者のみ利用できます'))),
      );
      return;
    }

    final restricted = <String, String>{
      'approvals': 'can_approve_daily_report_edits',
      'invoices': 'can_view_invoices',
      'admin_sites': 'can_view_admin_site_data',
      // 社員一覧・個人ページは管理者/サブ管理者だけ。

      'payroll_adjustments': 'can_view_payroll_adjustments',
    };
    final permission = restricted[key];
    if (permission != null && !_identity.can(permission)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(SkoLanguageController.tr('この機能を利用する権限がありません'))),
      );
      return;
    }

    if (!_subAdminFeatureEnabled(key == 'company_delivery_inbox' ? 'company_deliveries' : key)) return;
    _recordCloudUsageForAction(key);

    if (key == 'footer_home') {
      setState(() => _selectedIndex = 0);
      return;
    }
    if (key == 'attendance') {
      setState(() => _selectedIndex = 1);
      return;
    }
    if (key == 'attendance_list') {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => attendanceWorkerListDestination(
            onOpenManagement:
                _nestedActionKeys.contains('attendance_management')
                ? () => _openHomeAction('attendance_management')
                : null,
          ),
        ),
      );
      return;
    }
    if (key == 'attendance_today') {
      if (_attendanceBadgeOpening) return;
      _attendanceBadgeOpening = true;
      final snapshot = _attendanceBadge;
      final openedAt = DateTime.now();
      final route = MaterialPageRoute<void>(
        builder: (_) => const TodayAttendancePage(),
      );
      try {
        final closed = Navigator.of(context).push(route);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          // A failed push or a route displaced before its first frame is not an open.
          if (mounted && route.isCurrent) {
            _acknowledgeAttendanceBadge(snapshot, openedAt);
          }
        });
        await closed;
      } finally {
        _attendanceBadgeOpening = false;
      }
      return;
    }
    if (key == 'footer_sites' || key == 'site_register') {
      setState(() => _selectedIndex = 2);
      return;
    }
    if (key == 'chat' || key == 'friends') {
      if (key == 'friends') {
        // A fresh ON response may have just replaced the disabled chat page.
        // Mount that existing surface before delivering its one-time request.
        final actor = _currentHomeActor;
        await WidgetsBinding.instance.endOfFrame;
        if (!mounted || actor != _currentHomeActor || !_moduleEnabled('chat')) {
          return;
        }
      }
      if (key == 'friends' && SupabaseBackend.isInitialized &&
          SupabaseBackend.client.auth.currentUser?.id != _tutorialUserId) {
        return;
      }
      setState(() {
        if (key == 'friends') {
          _friendsReturnIndex = _selectedIndex;
          _friendsReturnActor = _currentHomeActor;
          _friendsRequest++;
        }
        _selectedIndex = 3;
      });
      return;
    }
    if (key == 'menu') {
      setState(() => _selectedIndex = 4);
      return;
    }

    Widget? page;

    switch (key) {
      case 'app_invite':
        if (!SupabaseBackend.isInitialized) return;
        page = AppReferralPage(
          repository: AppReferralRepository(SupabaseBackend.client),
        );
        break;
      case 'clock_in':
        page = const AttendanceVerificationPage(
          initialEventType: 'clock_in',
        );
        break;
      case 'clock_out':
        page = const AttendanceVerificationPage(
          initialEventType: 'clock_out',
        );
        break;
      case 'route_visit_recover':
        final pendingActor = SupabaseBackend.isInitialized
            ? SupabaseBackend.client.auth.currentUser?.id : null;
        final sources = List<String>.from(_homePendingRouteSourceIds);
        if (sources.isEmpty) return;
        final pendingSource = sources.length == 1
            ? sources.single
            : await showDialog<String>(
                context: context,
                builder: (context) => SimpleDialog(
                  title: const Text('再開する勤務を選択'),
                  children: [
                    for (var index = 0; index < sources.length; index++)
                      SimpleDialogOption(
                        onPressed: () => Navigator.pop(context, sources[index]),
                        child: Text('保留中の勤務 ${index + 1}'),
                      ),
                  ],
                ),
              );
        if (!mounted ||
            pendingSource == null ||
            pendingActor == null ||
            !SupabaseBackend.isInitialized ||
            SupabaseBackend.client.auth.currentUser?.id != pendingActor ||
            !_homePendingRouteSourceIds.contains(pendingSource)) {
          return;
        }
        page = RouteJourneyCapturePage(sourceId: pendingSource);
        break;
      case 'route_visit':
      case 'route_visit_arrive':
      case 'route_visit_move':
        final shifts = _homeAttendanceStatus.openShifts;
        if (shifts.length != 1 || shifts.single.routeId == null) return;
        if (key == 'route_visit_arrive' && _homeRouteActionState != HomeRouteActionState.arrive) return;
        if (key == 'route_visit_move' && _homeRouteActionState != HomeRouteActionState.move) return;
        setState(() => _homeRouteActionState = HomeRouteActionState.unavailable);
        page = RouteJourneyCapturePage(
          sourceId: shifts.single.id,
          initialAction: key == 'route_visit_arrive' ? 'arrive' : key == 'route_visit_move' ? 'move' : null,
        );
        break;
      case 'attendance_verify':
      case 'attendance_method_vehicle':
        page = const AttendanceSelectionPage();
        break;
      case 'workplace_select':
        page = const WorkDestinationSelectionPage();
        break;
      case 'employee_resources':
        page = EmployeeResourcesPage(availableKeys: _employeeResourceKeys, onOpen: _openHomeAction);
        break;
      case 'daily_report':
        page = const DailyReportMonthPage();
        break;
      case 'expense_claims':
        page = const ExpenseHomePage();
        break;
      case 'company_common_allowances':
        if (!_nestedActionKeys.contains('company_common_allowances')) return;
        page = const SecondaryProtectedPage(
          title: '社内共通手当',
          child: CompanyCommonAllowanceEntryPage(),
        );
        break;
      case 'company_tax_rates':
        if (!_nestedActionKeys.contains('company_tax_rates')) return;
        page = const CompanyPayrollRatesHomePage();
        break;
      case 'vehicle_select':
        page = const VehicleRouteSelectionPage(
          mode: VehicleRouteSelectionMode.vehicle,
        );
        break;
      case 'route_select':
        page = const VehicleRouteSelectionPage(
          mode: VehicleRouteSelectionMode.route,
        );
        break;
      case 'employee_register':
      case 'initial_registration':
        page = _isAdmin ? const EmployeeInitialRegistrationPage() : const EmployeeRegistrationPage();
        break;
      case 'approvals':
        page = const ApprovalsHubPage();
        break;
      case 'payroll':
        page = const SecondaryProtectedPage(
          title: '給与明細',
          child: PayrollStatementsPage(),
        );
        break;
      case 'payroll_settings':
        page = const SecondaryProtectedPage(
          title: '個別給与設定',
          child: IndividualPayrollSettingsPage(),
        );
        break;
      case 'payroll_adjustments':
        page = SecondaryProtectedPage(
          title: _payrollAdjustmentLabel,
          child: const PayrollAdjustmentPage(),
        );
        break;
      case 'payroll_review':
        page = SecondaryProtectedPage(
          title: '給料一覧',
          child: PayrollReviewPage(onOpenSettings: (_identity.isAdmin || _isViewer) ? () => _openHomeAction('payroll_settings') : null,
            onOpenTaxRates: (_identity.isAdmin || _isViewer) ? () => _openHomeAction('company_tax_rates') : null,
            onOpenCommonAllowances: (_identity.isAdmin || _isViewer) ? () => _openHomeAction('company_common_allowances') : null),
        );
        break;
      case 'payment_certificates':
        page = SecondaryProtectedPage(
          title: '支払証明書',
          child: PaymentCertificatesPage(
            onOpenSettings:
                _nestedActionKeys.contains('payment_certificate_settings')
                ? () => _openHomeAction('payment_certificate_settings')
                : null,
          ),
        );
        break;
      case 'payment_certificate_settings':
        page = const SecondaryProtectedPage(
          title: '支払証明書設定',
          child: PartnerPaymentSettingsPage(),
        );
        break;
      case 'traffic_guidance':
        page = Scaffold(
          appBar: AppBar(title: Text(SkoLanguageController.tr('交通案内'))),
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: Align(alignment: Alignment.topCenter,
              child: TrafficHomeCard(availability: _homeTrafficAvailability, shortcutScope: _trafficShortcutScope)),
          ),
        );
        break;
      case 'weather_forecast':
        page = WeatherForecastDetailPage(state: _weatherViewState,
          onRefresh: _loadWeatherLocation, onSelectDay: _selectWeatherDay,
          onOpenRadar: _openWeatherRadar, onOpenAttribution: _openWeatherReference);
        break;
      case 'notifications':
        page = NotificationsPage(companyId: _tutorialCompanyId, currentCompany: () => _tutorialCompanyId);
        break;
      case 'profile':
        page = ProfilePage(
          role: ManualContent.fromMembershipRole(_identity.role),
        );
        break;
      case 'tutorial':
        final userId = _tutorialUserId;
        final companyId = _tutorialCompanyId;
        if (userId == null || companyId == null) return;
        page = TutorialPage(userId: userId, companyId: companyId,
          availableActionKeys: _availableActionKeys,
          onOpenAction: _openHomeAction);
        break;
      case 'help':
        page = HelpPage(
          role: ManualContent.fromMembershipRole(_identity.role),
          visibleFeatureKeys: _availableActionKeys,
        );
        break;
      case 'site_map':
        page = const AdminSiteMapPage();
        break;
      case 'admin_sites':
        page = SecondaryProtectedPage(
          title: '現場管理',
          child: AdminSiteFinancialPage(
            onOpenMap: _nestedActionKeys.contains('site_map')
                ? () => _openHomeAction('site_map')
                : null,
          ),
        );
        break;
      case 'qualification_certificates':
        page = const QualificationCertificatePage();
        break;
      case 'qualification_register':
        page = const OwnQualificationRegistrationPage();
        break;
      case 'employee_qualifications':
        page = const QualificationCloudPage();
        break;
      case 'documents':
        page = const WorkerDocumentPage();
        break;
      case 'document_register':
        page = const OwnDocumentRegistrationPage();
        break;
      case 'company_delivery_inbox':
        page = const CompanyDeliveryInboxPage();
        break;
      case 'company_deliveries':
        page = TradeCompanyPage(mode: TradeCompanyPageMode.subcontractor, onOpenDeliveries: () => _openHomeAction('company_delivery_inbox'));
        break;
      case 'trade_companies':
        page = const TradeCompanyPage(
          mode: TradeCompanyPageMode.customer,
        );
        break;
      case 'trade_documents':
        if (!_identity.isManagement) return;
        page = const SecondaryProtectedPage(
          title: '注文・請書', child: TradeDocumentsHubPage());
        break;
      case 'subcontractors':
        page = TradeCompanyPage(
          mode: TradeCompanyPageMode.subcontractor,
          onOpenDeliveries: _subAdminFeatureEnabled('company_deliveries') ? () => _openHomeAction('company_delivery_inbox') : null,
        );
        break;
      case 'company_documents':
        page = const CompanySubmittedDocumentsPage();
        break;
      case 'attendance_management':
        page = attendanceManagementDestination();
        break;
      case 'line_talk':
        page = const LineTalkHubPage();
        break;
      case 'today_line':
        page = const TodayLineAttendancePage();
        break;
      case 'line_history':
        page = const LineHistoryPreviewPage();
        break;
      case 'rollout':
        page = const RolloutReadinessPage();
        break;
      case 'notes':
        page = const NotesCloudPage();
        break;
      case 'albums':
        page = const AlbumsCloudPage();
        break;
      case 'vehicle_routes':
        page = const VehicleRoutePage();
        break;
      case 'appearance':
        await _openHomeAppearanceSettings();
        return;
      case 'settings':
        page = const SettingsPage();
        break;
      default:
        for (final module in legacy.HomePage.modules) {
          if (module.storageKey == key) {
            page = _pageFor(module);
            break;
          }
        }
    }

    if (page == null || !mounted) return;

    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => page!),
    );

    if (!mounted) return;
    if (const {'profile', 'settings', 'company_documents', 'company_modules', 'payroll_adjustments'}.contains(key)) {
      await _loadIdentity();
    }
    if (!mounted) return;
    setState(() => _tutorialRefreshToken++);
    await _loadRequiredDocumentAttention();

    if (key == 'clock_in' ||
        key == 'clock_out' ||
        key == 'daily_report' ||
        key == 'attendance_verify' ||
        key == 'attendance_method_vehicle' ||
        key == 'workplace_select' ||
        key == 'vehicle_select' ||
        key == 'route_select' ||
        key == 'route_visit' ||
        key == 'route_visit_arrive' ||
        key == 'route_visit_move' ||
        key == 'route_visit_recover') {
      await _loadHomeAttendanceStatus();
      await _loadWeatherLocation();
    }
    if (key == 'settings' || key == 'company_documents' || key == 'company_modules') {
      await _loadModuleSettings();
      await _loadHomeAttendanceStatus();
      await _loadWeatherLocation();
    }
    if (key == 'profile') {
      await _loadWeatherLocation();
    }
    if (key == 'payroll_adjustments') {
      await _loadPayrollAdjustmentAccess();
    }
  }

  Set<String> get _employeeResourceKeys => {
    if ((_identity.isManagement || _isViewer) && _subAdminFeatureEnabled('people')) 'people',
    if (_identity.isManagement && _moduleEnabled('qualifications') && _subAdminFeatureEnabled('employee_qualifications')) 'employee_qualifications',
    if (_identity.isManagement && _moduleEnabled('documents') && _subAdminFeatureEnabled('documents')) 'documents',
  };

  Set<String> get _nestedActionKeys => {
    if (_identity.isAdmin || _isViewer) 'company_tax_rates',
    if (_identity.isAdmin || _isViewer) 'company_common_allowances',
    if (_moduleEnabled('attendance') &&
        _identity.isManagement &&
        _identity.can('can_manage_attendance') &&
        _subAdminFeatureEnabled('attendance_management'))
      'attendance_management',
    if (_identity.isManagement &&
        _subAdminFeatureEnabled('payment_certificate_settings'))
      'payment_certificate_settings',
    if (_moduleEnabled('sites') &&
        _identity.isManagement &&
        _subAdminFeatureEnabled('site_map'))
      'site_map',
    if (_identity.can('can_approve_daily_report_edits') &&
        _subAdminFeatureEnabled('approvals'))
      'approvals',
  };

  Set<String> get _availableActionKeys => {
    ..._menuItems.map((item) => item.key), ..._employeeResourceKeys,
    ..._nestedActionKeys,
    if (_isAdmin) 'initial_registration',
    if (_identity.isAdmin || _isViewer) 'payroll_settings',
    if (_identity.isManagement && _subAdminFeatureEnabled('company_deliveries')) 'company_deliveries',
  };

  List<_MenuAction> get _menuItems {
    final items = <_MenuAction>[
      _MenuAction(
        key: 'app_invite',
        label: SkoLanguageController.tr('SKO招待'),
        icon: Icons.person_add_alt_1_outlined,
        homeEligible: true,
        accessLabel: SkoLanguageController.tr('管理者・サブ管理者・一般・閲覧権限'),
      ),
      if (_moduleEnabled('chat'))
        _MenuAction(
          key: 'friends',
          label: SkoLanguageController.tr('友達一覧'),
          icon: Icons.people_outline,
          homeEligible: true,
          accessLabel: SkoLanguageController.tr('管理者・サブ管理者・一般・閲覧権限'),
        ),
      _MenuAction(key: 'traffic_guidance', label: SkoLanguageController.tr('交通案内'),
        icon: Icons.train_rounded, homeEligible: false,
        accessLabel: SkoLanguageController.tr('管理者・サブ管理者・一般・閲覧権限')),
      _MenuAction(key: 'weather_forecast', label: SkoLanguageController.tr('天気予報'),
        icon: Icons.cloud_outlined, homeEligible: false,
        accessLabel: SkoLanguageController.tr('管理者・サブ管理者・一般・閲覧権限')),
      _MenuAction(key: 'expense_claims', label: SkoLanguageController.tr('経費申請'), icon: Icons.receipt_long_outlined, homeEligible: true, accessLabel: SkoLanguageController.tr('管理者・サブ管理者・一般・閲覧権限')),
      _MenuAction(key: 'tutorial', label: SkoLanguageController.tr('準備ガイド'),
        icon: Icons.school_outlined, homeEligible: false,
        accessLabel: SkoLanguageController.tr('管理者・サブ管理者・一般・閲覧権限')),
      if (_moduleEnabled('attendance'))
        _MenuAction(
          key: 'attendance_verify',
          label: SkoLanguageController.tr('本日の勤怠報告'),
          icon: Icons.fact_check_outlined,
          homeEligible: false,
          accessLabel: SkoLanguageController.tr('管理者・サブ管理者・一般・閲覧権限'),
        ),
      if (_moduleEnabled('attendance'))
        _MenuAction(
          key: 'attendance_today',
          label: SkoLanguageController.tr('本日の出勤'),
          icon: Icons.groups_outlined,
          homeEligible: false,
          accessLabel: SkoLanguageController.tr('管理者・サブ管理者・一般・閲覧権限'),
        ),
      if (_moduleEnabled('attendance'))
        _MenuAction(
          key: 'attendance_list',
          label: SkoLanguageController.tr('出勤表一覧'),
          icon: Icons.calendar_month_outlined,
          homeEligible: true,
          accessLabel: SkoLanguageController.tr('閲覧者以上'),
        ),
      _MenuAction(
        key: 'daily_report',
        label: SkoLanguageController.tr('日報'),
        icon: Icons.description_outlined,
        homeEligible: true,
        accessLabel: SkoLanguageController.tr('管理者・サブ管理者・一般・閲覧権限'),
      ),
      if (_employeeResourceKeys.isNotEmpty)
        _MenuAction(key: 'employee_resources', label: SkoLanguageController.tr('社員資格書類'), icon: Icons.folder_shared_outlined, homeEligible: true, accessLabel: SkoLanguageController.tr('管理者・閲覧者・サブ管理者')),
      if (_identity.isManagement && _moduleEnabled('vehicle_routes'))
        _MenuAction(
          key: 'vehicle_routes',
          label: SkoLanguageController.tr('車両ルート'),
          icon: Icons.route_outlined,
          homeEligible: true,
          accessLabel: SkoLanguageController.tr('管理者・サブ管理者・一般・閲覧権限'),
        ),
      if (_identity.isManagement)
        _MenuAction(
          key: 'employee_register',
          label: SkoLanguageController.tr('従業員登録'),
          icon: Icons.person_add_alt_1,
          homeEligible: true,
          accessLabel: SkoLanguageController.tr('管理者・サブ管理者'),
        ),
      _MenuAction(
        key: 'payroll',
        label: SkoLanguageController.tr('給与明細'),
        icon: Icons.payments_outlined,
        homeEligible: true,
        accessLabel: SkoLanguageController.tr('本人'),
      ),
      if (_identity.isManagement || _identity.can('can_view_payroll_adjustments'))
        _MenuAction(
          key: 'payroll_adjustments',
          label: _payrollAdjustmentLabel,
          icon: Icons.price_change_outlined,
          accessLabel: SkoLanguageController.tr('管理者・給与閲覧権限'),
        ),
      if (_identity.isManagement || _isViewer || _identity.can('can_manage_payroll_adjustments'))
        _MenuAction(
          key: 'payroll_review',
          label: SkoLanguageController.tr('給料一覧'),
          icon: Icons.fact_check_outlined,
          homeEligible: true,
          accessLabel: SkoLanguageController.tr('管理者・サブ管理者・閲覧権限'),
        ),
      if (_identity.isManagement)
        _MenuAction(
          key: 'payment_certificates',
          label: SkoLanguageController.tr('支払証明書'),
          icon: Icons.receipt_long_outlined,
          homeEligible: true,
          accessLabel: SkoLanguageController.tr('管理者・サブ管理者'),
        ),
      _MenuAction(
        key: 'profile',
        label: SkoLanguageController.tr('プロフィール'),
        icon: Icons.account_circle_outlined,
        homeEligible: true,
        accessLabel: SkoLanguageController.tr('管理者・サブ管理者・一般・閲覧権限'),
      ),
      if (_moduleEnabled('qualifications'))
        _MenuAction(
          key: 'qualification_register',
          label: SkoLanguageController.tr('資格登録'),
          icon: Icons.add_card_outlined,
          homeEligible: true,
          accessLabel: SkoLanguageController.tr('管理者・サブ管理者・一般・閲覧権限'),
        ),
      if (_moduleEnabled('documents'))
        _MenuAction(
          key: 'document_register',
          label: SkoLanguageController.tr('書類登録'),
          icon: Icons.note_add_outlined,
          homeEligible: true,
          accessLabel: SkoLanguageController.tr('管理者・サブ管理者・一般・閲覧権限'),
        ),
      if (_moduleEnabled('notes'))
        _MenuAction(
          key: 'notes',
          label: SkoLanguageController.tr('ノート'),
          icon: Icons.sticky_note_2_outlined,
          accessLabel: SkoLanguageController.tr('管理者・サブ管理者・一般・閲覧権限'),
        ),
      if (_moduleEnabled('albums'))
        _MenuAction(
          key: 'albums',
          label: SkoLanguageController.tr('アルバム'),
          icon: Icons.photo_album_outlined,
          accessLabel: SkoLanguageController.tr('管理者・サブ管理者・一般・閲覧権限'),
        ),
      if (_lineRelease?.visible == true)
        _MenuAction(
          key: 'line_talk',
          label: SkoLanguageController.tr('LINEトーク'),
          icon: Icons.chat_bubble_outline,
          homeEligible: true,
          accessLabel: SkoLanguageController.tr('管理者・サブ管理者・一般・閲覧権限'),
        ),
      if (_identity.isManagement)
        _MenuAction(
          key: 'trade_companies',
          label: SkoLanguageController.tr('取引会社登録'),
          icon: Icons.business_center_outlined,
          homeEligible: true,
          accessLabel: SkoLanguageController.tr('管理者・サブ管理者'),
        ),
      if (_identity.isManagement)
        _MenuAction(
          key: 'subcontractors',
          label: SkoLanguageController.tr('協力会社登録'),
          icon: Icons.handshake_outlined,
          homeEligible: true,
          accessLabel: SkoLanguageController.tr('管理者・サブ管理者'),
        ),
      if (_isAdmin)
        _MenuAction(
          key: 'company_documents',
          label: SkoLanguageController.tr('会社データ'),
          icon: Icons.business_center_outlined,
          homeEligible: true,
          accessLabel: SkoLanguageController.tr('管理者'),
        ),
      if (_moduleEnabled('invoices') &&
          (_identity.isManagement || _identity.can('can_view_invoices')))
        _MenuAction(
          key: 'invoices',
          label: SkoLanguageController.tr('請求書'),
          icon: Icons.receipt_long_outlined,
          homeEligible: true,
          accessLabel: SkoLanguageController.tr('管理者・請求書閲覧権限'),
        ),
      if (_identity.isManagement)
        _MenuAction(key: 'trade_documents', label: SkoLanguageController.tr('注文・請書'),
          icon: Icons.description_outlined, homeEligible: true,
          accessLabel: SkoLanguageController.tr('管理者・サブ管理者')),
      if (_moduleEnabled('sites') && _identity.can('can_view_admin_site_data'))
        _MenuAction(
          key: 'admin_sites',
          label: SkoLanguageController.tr('現場管理'),
          icon: Icons.admin_panel_settings_outlined,
          homeEligible: true,
          accessLabel: SkoLanguageController.tr('管理者・現場閲覧権限'),
        ),
      if (!_identity.isManagement && _moduleEnabled('sites'))
        _MenuAction(
          key: 'site_register',
          label: SkoLanguageController.tr('現場登録'),
          icon: Icons.add_business_outlined,
          homeEligible: true,
          accessLabel: SkoLanguageController.tr('一般・閲覧権限'),
        ),
      _MenuAction(
        key: 'appearance',
        label: SkoLanguageController.tr('背景'),
        icon: Icons.wallpaper_outlined,
        homeEligible: true,
        accessLabel: SkoLanguageController.tr('本人のみ'),
      ),
      _MenuAction(
        key: 'settings',
        label: SkoLanguageController.tr('設定'),
        icon: Icons.settings_outlined,
        homeEligible: false,
        accessLabel: SkoLanguageController.tr('管理者・サブ管理者・一般・閲覧権限'),
      ),
      _MenuAction(
        key: 'help',
        label: SkoLanguageController.tr('ヘルプ'),
        icon: Icons.help_outline,
        homeEligible: true,
        accessLabel: SkoLanguageController.tr('表示中の権限に合わせて案内'),
      ),
    ];

    if (_identity.isSubAdmin) {
      items.removeWhere(
        (item) =>
            CompanyModuleSettingsRepository.subAdminHomeKeys.contains(item.key) &&
            !_subAdminFeatureEnabled(item.key),
      );
    }

    final defaults = List<_MenuAction>.from(items)..sort((a, b) => a.label.compareTo(b.label));
    final keys = items.map((item) => item.key).toSet();
    final normalized = normalizeHomeActionOrder(_homeActionOrder, [
      if (keys.contains('attendance_verify')) 'attendance_verify',
      if (keys.contains('attendance_today')) 'attendance_today',
      ...defaults.map((item) => item.key),
      'home_attention',
    ]);
    final rank = <String, int>{for (var i = 0; i < normalized.length; i++) normalized[i]: i};
    items.sort((a, b) {
      final ai = rank[a.key] ?? 100000;
      final bi = rank[b.key] ?? 100000;
      if (ai != bi) return ai.compareTo(bi);
      return a.label.compareTo(b.label);
    });
    return items;
  }

  Widget _homeDashboard() => Builder(builder: _buildHomeDashboard);

  Widget _buildHomeDashboard(BuildContext context) {
    FloatingHelpController.setContext(
      featureKey: 'home',
      currentRole: ManualContent.fromMembershipRole(_identity.role),
      visibleKeys: _availableActionKeys,
    );
    final now = DateTime.now();
    final dateLabel = SkoLanguageController.isEnglish
        ? '${now.month}/${now.day}/${now.year}'
        : '${now.year}年${now.month}月${now.day}日';
    final wallpaperPath = _homeAppearance.wallpaperPath;
    final bodyAppearance = _homeAppearance.copyWith(clearWallpaper: true);
    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(
          color: Theme.of(context).scaffoldBackgroundColor,
        ),
        if (wallpaperPath != null && File(wallpaperPath).existsSync())
          Opacity(
            opacity: _homeAppearance.wallpaperOpacity,
            child: Image.file(
              File(wallpaperPath),
              fit: BoxFit.cover,
            ),
          ),
        ValueListenableBuilder<bool>(
          valueListenable: _homeChromeVisible,
          child: FriendlyHomeContent(
          identity: _identity,
          requiredDocumentAttention: _requiredDocumentAttention,
          weatherCard: _weatherHomeCard(),
          trafficCard: TrafficHomeCard(key: const ValueKey('home-traffic-card'), availability: _homeTrafficAvailability, shortcutScope: _trafficShortcutScope),
          showTrafficGuidance: !_hiddenHomeActionKeys.contains('traffic_guidance'),
          showWeatherForecast: !_hiddenHomeActionKeys.contains('weather_forecast'),
          tutorialCard: _tutorialUserId != null && _tutorialCompanyId != null
              ? TutorialHomeCard(userId: _tutorialUserId!, companyId: _tutorialCompanyId!,
                  availableActionKeys: _availableActionKeys,
                  onOpenAction: _openHomeAction, refreshToken: _tutorialRefreshToken)
              : null,
          moduleEnabled: _moduleEnabled,
          gridColumns: _homeGridColumns,
          actionOrder: _homeActionOrder,
          visibleHomeKeys: {
            for (final item in _menuItems)
              if (!_homeActionHidden(item.key)) item.key,
          },
          shortcuts: [
            for (final item in _homeLayoutItems)
              HomeShortcut(
                item.key,
                item.label,
                item.icon,
                twoLineLabel: _homeLabelOverrides[item.key],
                access: item.access,
              ),
          ],
          showAttendanceReport:
              !_hiddenHomeActionKeys.contains('attendance_verify'),
          showTodayAttendance:
              !_hiddenHomeActionKeys.contains('attendance_today'),
          attendanceStatus: _homeAttendanceStatus,
          attendanceUpdateCount: _attendanceBadgeCount,
          attendanceUpdateUnavailable: _attendanceBadgeUnavailable,
          optionalClockInAllowed: _homeOptionalClockInAllowed,
          routeActionState: _homeRouteActionState,
          hasPendingRouteRecord: _homePendingRouteSourceIds.isNotEmpty,
          hasPendingRouteReports: _homeHasPendingRouteReports,
          appearance: bodyAppearance,
          // Keep scroll geometry stable when the overlay header hides or returns.
          contentTopInset: MediaQuery.paddingOf(context).top + 72,
          onOpen: _openHomeAction,
          onRefresh: _loadHomeData,
          onReorderAction: _reorderHomeActionByKey,
        ),
          builder: (context, chromeVisible, child) => Scaffold(
          extendBodyBehindAppBar: true,
          backgroundColor: Colors.transparent,
          appBar: PreferredSize(
            preferredSize: Size.fromHeight(chromeVisible ? 64 : 0),
            child: Stack(
              fit: StackFit.expand,
              children: [
                IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.white.withAlpha(
                        (_homeAppearance.headerOpacity * 255).round(),
                      ),
                    ),
                  ),
                ),
                AppBar(
                  toolbarHeight: chromeVisible ? 64 : 0,
                  backgroundColor: Colors.transparent,
                  forceMaterialTransparency: true,
                  surfaceTintColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                  elevation: 0,
                  titleSpacing: 12,
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _identity.companyName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                ),
              ),
              Text(
                '${_identity.displayName}　$dateLabel',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 10,
                ),
              ),
            ],
          ),
          actions: [
            IconButton(
              tooltip: SkoLanguageController.tr('背景・ヘッダー・フッター設定'),
              onPressed: _openHomeAppearanceSettings,
              icon: const Icon(Icons.wallpaper_outlined),
            ),
            const SkoNotificationBell(),
            if (widget.onSignOut != null)
              IconButton(
                tooltip: SkoLanguageController.tr('ログアウト'),
                onPressed: widget.onSignOut,
                icon: const Icon(Icons.logout),
              ),
          ],
                ),
              ],
            ),
          ),
          body: child,

      ),
      ),
      ],
    );
  }

  HomeShortcutAccess _shortcutAccessForMenuItem(_MenuAction item) {
    const general = <String>{
      'help',
      'appearance',
      'albums',
      'notes',
      'daily_report',
      'expense_claims',
      'profile',
      'qualification_register',
      'document_register',
    };
    const subAdmin = <String>{
      'employee_resources',
      'people',
      'company_deliveries',
      'vehicle_routes',
      'employee_register',
      'approvals',
      'documents',
      'employee_qualifications',
      'attendance_management',
      'payment_certificates',
      'trade_companies',
      'subcontractors',
    };
    const viewer = <String>{
      'employee_resources',
      'people',
      'invoices',
      'payroll_settings',
      'payroll_adjustments',
      'payroll_review',
      'company_tax_rates',
      'company_common_allowances',
      'attendance_list',
    };
    const admin = <String>{
      'admin_sites',
      'trade_documents',
      'company_modules',
      'company_documents',
      'site_map',
      'today_line',
      'payment_certificate_settings',
      'initial_registration',
    };
    if (admin.contains(item.key)) return HomeShortcutAccess.admin;
    if (viewer.contains(item.key)) return HomeShortcutAccess.viewer;
    if (subAdmin.contains(item.key)) return HomeShortcutAccess.subAdmin;
    if (general.contains(item.key)) return HomeShortcutAccess.general;
    return HomeShortcutAccess.general;
  }

  List<_HomeLayoutItem> get _homeLayoutItems {
    return [
      for (final item in _menuItems)
        if (item.homeEligible && !_homeActionHidden(item.key))
          _HomeLayoutItem(
            item.key,
            item.label,
            item.icon,
            _shortcutAccessForMenuItem(item),
          ),
    ];
  }

  Widget _menuPage() {
    final items = _menuItems;
    return ValueListenableBuilder<bool>(
      valueListenable: _homeChromeVisible,
      child: SafeArea(
        child: ReorderableListView.builder(
          padding: const EdgeInsets.all(12),
          buildDefaultDragHandles: true,
          header: Column(
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        SkoLanguageController.tr('ホーム表示・並び順・権限'),
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        SkoLanguageController.isEnglish
                            ? 'Manage Home and Menu in one list. Toggle visibility, drag to reorder, and choose 1–4 columns. Borders match Home: thick for administrators, double for viewers, single for sub-administrators.'
                            : 'ホームとメニューを同じ一覧で管理します。管理者メニューに表示される全項目をホームボタンにできます。スイッチで表示ON/OFF、項目を長押しして上下へドラッグ、1〜4列を選択できます。カードの枠はホームと共通で、管理者は太枠、閲覧権限は二重枠、サブ管理者は一本枠です。',
                      ),
                      const SizedBox(height: 12),
                      SegmentedButton<int>(
                        segments: [
                          ButtonSegment(value: 1, label: Text(SkoLanguageController.tr('1列'))),
                          ButtonSegment(value: 2, label: Text(SkoLanguageController.tr('2列'))),
                          ButtonSegment(value: 3, label: Text(SkoLanguageController.tr('3列'))),
                          ButtonSegment(value: 4, label: Text(SkoLanguageController.tr('4列'))),
                        ],
                        selected: {_homeGridColumns},
                        onSelectionChanged: (values) {
                          if (values.isEmpty) return;
                          _setHomeGridColumns(values.first);
                        },
                      ),
                      const SizedBox(height: 10),
                      FilledButton.tonalIcon(
                        onPressed: _openHomeAppearanceSettings,
                        icon: const Icon(Icons.wallpaper_outlined),
                        label: Text(SkoLanguageController.tr('背景・ヘッダー・フッター設定')),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
          ),
          itemCount: items.length,
          onReorderItem: _reorderHomeAction,
          itemBuilder: (context, i) {
            final item = items[i];
            final access = _shortcutAccessForMenuItem(item);
            final doubleBorder =
                (access == HomeShortcutAccess.viewer ||
                    item.key == 'payment_certificates') &&
                item.key != 'employee_resources';
            final borderWidth = access == HomeShortcutAccess.admin
                ? 4.0
                : (access == HomeShortcutAccess.subAdmin ||
                        access == HomeShortcutAccess.viewer || doubleBorder
                    ? 1.8
                    : 0.0);
            return Padding(
              key: ValueKey('menu_${item.key}'),
              padding: const EdgeInsets.only(bottom: 8),
              child: Container(
                decoration: doubleBorder
                    ? BoxDecoration(
                        border: Border.all(
                          color: Theme.of(context).colorScheme.primary,
                          width: 1.8,
                        ),
                        borderRadius: BorderRadius.circular(23),
                      )
                    : null,
                child: Card(
                  margin: doubleBorder
                      ? const EdgeInsets.all(3)
                      : null,
                  shape: borderWidth > 0
                      ? RoundedRectangleBorder(
                          side: BorderSide(
                            color: Theme.of(context).colorScheme.primary,
                            width: borderWidth,
                          ),
                          borderRadius: BorderRadius.circular(20),
                        )
                      : null,
                  child: ListTile(
                    leading: const Icon(Icons.drag_handle),
                    title: Text(
                      item.label,
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    subtitle: Text('${SkoLanguageController.tr('利用権限')}：${item.accessLabel}'),
                    onTap: () => _openHomeAction(item.key),
                    trailing: Wrap(
                      spacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (item.homeEligible)
                          IconButton(
                            tooltip: '2行表示時の改行位置',
                            onPressed: () => _editHomeLabel(item),
                            icon: const Icon(Icons.edit_note_outlined),
                          ),
                        Switch(
                          value: !_homeActionHidden(item.key),
                          onChanged: (value) =>
                              _setHomeActionVisible(item.key, value),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
      builder: (context, chromeVisible, child) => Scaffold(
      appBar: PreferredSize(
        preferredSize: Size.fromHeight(chromeVisible ? kToolbarHeight : 0),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          height: chromeVisible ? kToolbarHeight : 0,
          child: chromeVisible
              ? AppBar(
                  title: Text(
                    SkoLanguageController.tr('メニュー'),
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  actions: const [SkoNotificationBell()],
                )
              : const SizedBox.shrink(),
        ),
      ),
      body: child,

      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      _homeDashboard(),
      _moduleEnabled('attendance')
          ? WorkerAttendanceSheetPage(isActive: _selectedIndex == 1)
          : _ModuleDisabledPage(label: SkoLanguageController.tr('出勤表')),
      _moduleEnabled('sites')
          ? const SiteCloudPage()
          : _ModuleDisabledPage(label: SkoLanguageController.tr('現場')),
      _moduleEnabled('chat')
          ? ChatCloudPage(viewerOnlyFriends: _isViewer, friendsRequest: _friendsRequest,
              onFriendsDismissed: (request) {
                final previous = _friendsReturnIndex;
                if (!mounted || request != _friendsRequest || previous == null ||
                    _friendsReturnActor != _currentHomeActor) { return; }
                setState(() { _selectedIndex = previous; _friendsReturnIndex = null; });
              })
          : _ModuleDisabledPage(label: SkoLanguageController.tr('チャット')),
      _menuPage(),
    ];

    return Scaffold(
      extendBody: true,
      body: IndexedStack(
        index: _selectedIndex,
        children: [
          for (var i = 0; i < pages.length; i++)
            HeroMode(
              enabled: i == _selectedIndex,
              child: pages[i],
            ),
        ],
      ),
      bottomNavigationBar: ValueListenableBuilder<bool>(
        valueListenable: _homeChromeVisible,
        builder: (context, chromeVisible, _) => AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        height: chromeVisible ? 88 : 0,
        child: chromeVisible
            ? Builder(
                builder: (context) {
                  final pageIndexes = <int>[
                    0,
                    if (!_isViewer) 1,
                    if (!_isViewer) 2,
                    3,
                    4,
                  ];
                  final destinations = <NavigationDestination>[
                    NavigationDestination(
                      icon: const Icon(Icons.home_outlined),
                      selectedIcon: const Icon(Icons.home),
                      label: SkoLanguageController.tr('ホーム'),
                    ),
                    if (!_isViewer)
                      NavigationDestination(
                        icon: const Icon(Icons.calendar_month_outlined),
                        selectedIcon: const Icon(Icons.calendar_month),
                        label: SkoLanguageController.tr('出勤表'),
                      ),
                    if (!_isViewer)
                      NavigationDestination(
                        icon: const Icon(Icons.business_outlined),
                        selectedIcon: const Icon(Icons.business),
                        label: SkoLanguageController.tr('現場'),
                      ),
                    NavigationDestination(
                      icon: const Icon(Icons.chat_bubble_outline),
                      selectedIcon: const Icon(Icons.chat_bubble),
                      label: SkoLanguageController.tr('チャット'),
                    ),
                    NavigationDestination(
                      icon: const Icon(Icons.menu),
                      label: SkoLanguageController.tr('メニュー'),
                    ),
                  ];
                  final selectedPosition = pageIndexes.indexOf(_selectedIndex);
                  return NavigationBar(
                    backgroundColor: Theme.of(context)
                        .colorScheme
                        .surface
                        .withValues(alpha: _homeAppearance.footerOpacity),
                    surfaceTintColor: Colors.transparent,
                    selectedIndex: selectedPosition >= 0 ? selectedPosition : 0,
                    onDestinationSelected: (position) {
                      final pageIndex = pageIndexes[position];
                      final usageKey = switch (pageIndex) {
                        0 => 'footer_home',
                        1 => 'attendance',
                        2 => 'footer_sites',
                        3 => 'chat',
                        _ => null,
                      };
                      if (usageKey != null) {
                        _recordCloudUsageForAction(usageKey);
                      }
                      setState(() => _selectedIndex = pageIndex);
                    },
                    destinations: destinations,
                  );
                },
              )
            : const SizedBox.shrink(),
      ),
      ),
    );
  }
}

class _MenuAction {
  _MenuAction({
    required this.key,
    required this.label,
    required this.icon,
    required this.accessLabel,
    this.homeEligible = true,
  });

  final String key;
  final String label;
  final IconData icon;
  final String accessLabel;
  final bool homeEligible;
}

class _HomeLayoutItem {
  const _HomeLayoutItem(this.key, this.label, this.icon, this.access);

  final String key;
  final String label;
  final IconData icon;
  final HomeShortcutAccess access;
}

class _BackendUnavailableScreen extends StatelessWidget {
  const _BackendUnavailableScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.lock_outline, size: 52),
                SizedBox(height: 16),
                Text(
                  'SKOを安全に開始できません',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                SizedBox(height: 10),
                Text(
                  kIsWeb
                      ? '認証サーバーの設定を読み込めないため、ログインや管理機能は開いていません。管理者にWEB版の接続設定の確認を依頼し、設定が完了してからページを再読み込みしてください。'
                      : '認証サーバーの設定を読み込めないため、ログインや管理機能は開いていません。Macの実機準備スクリプトでSupabase設定を確認してから再起動してください。',
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}


class _ModuleDisabledPage extends StatelessWidget {
  const _ModuleDisabledPage({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.toggle_off_outlined, size: 52),
                const SizedBox(height: 12),
                Text(
                  '$labelは会社設定でOFFになっています',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}


