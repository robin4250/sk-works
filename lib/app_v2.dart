import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
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
import 'features/attendance/work_destination_selection_page.dart';
import 'features/attendance/attendance_verification_page.dart';
import 'features/attendance/attendance_verification_repository.dart';
import 'features/attendance/gps_auto_attendance_service.dart';
import 'features/attendance/today_attendance_page.dart';
import 'features/attendance/worker_attendance_sheet_page.dart';
import 'features/auth/auth_gate.dart';
import 'features/auth/employee_onboarding_approvals_page.dart';
import 'features/auth/employee_onboarding_repository.dart';
import 'features/auth/secondary_protected_page.dart';
import 'features/chat/chat_cloud_page.dart';
import 'features/chat/line_history_preview_page.dart';
import 'features/chat/today_line_attendance_page.dart';
import 'features/daily_reports/daily_report_approvals_page.dart';
import 'features/daily_reports/daily_report_page.dart';
import 'features/help/help_page.dart';
import 'features/help/manual_content.dart';
import 'features/home/friendly_home_content.dart';
import 'features/home/home_attention_repository.dart';
import 'features/home/home_appearance.dart';
import 'features/home/home_membership_repository.dart';
import 'features/invoices/invoice_cloud_page.dart';
import 'features/invoices/invoice_page.dart';
import 'features/notes/notes_cloud_page.dart';
import 'features/notifications/notification_bell.dart';
import 'features/operations/vehicle_route_page.dart';
import 'features/operations/vehicle_route_selection_page.dart';
import 'features/payroll/individual_payroll_settings_page.dart';
import 'features/payroll/payroll_adjustment_page.dart';
import 'features/payroll/payroll_adjustment_repository.dart';
import 'features/payroll/payroll_statements_page.dart';
import 'features/people/company_delivery_inbox_page.dart';
import 'features/people/company_submitted_documents_page.dart';
import 'features/people/employee_invite_page.dart';
import 'features/people/people_cloud_page.dart';
import 'features/people/people_page.dart';
import 'features/people/signature_list_page.dart';
import 'features/people/worker_document_page.dart';
import 'features/profile/profile_page.dart';
import 'features/qualifications/qualification_certificate_page.dart';
import 'features/qualifications/qualification_cloud_page.dart';
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
            return MaterialApp(
              navigatorKey: SkoScrollChromeController.navigatorKey,
              debugShowCheckedModeBanner: false,
              title: ProductBrand.displayName,
              theme: SkoTheme.light(palette),
              builder: (context, child) => SkoGlobalScrollChrome(
                child: child ?? const SizedBox.shrink(),
              ),
              home: SupabaseBackend.isInitialized
                  ? SupabaseAuthGate(
                      homeBuilder: (onSignOut) => HomePage(onSignOut: onSignOut),
                    )
                  : allowLocalFallback
                      ? const HomePage()
                      : const _BackendUnavailableScreen(),
            );
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

class _HomePageState extends State<HomePage> {
  static const _usagePrefix = 'sko_menu_usage_';

  final _moduleSettingsRepository =
      CompanyModuleSettingsRepository.maybeCreate();
  final _membershipRepository = HomeMembershipRepository.maybeCreate();
  final _employeeOnboardingRepository =
      EmployeeOnboardingRepository.maybeCreate();
  final _homeAttentionRepository = HomeAttentionRepository.maybeCreate();
  final _attendanceVerificationRepository =
      AttendanceVerificationRepository.maybeCreate();
  final _payrollAdjustmentRepository =
      PayrollAdjustmentRepository.maybeCreate();
  final _usageAnalyticsRepository = UsageAnalyticsRepository.maybeCreate();

  Map<String, bool> _moduleStates = const {};
  Map<String, int> _usage = const {};
  int _homeGridColumns = 2;
  List<String> _homeActionOrder = const [];
  Set<String> _hiddenHomeActionKeys = <String>{};
  HomeAppearance _homeAppearance = const HomeAppearance();
  HomeIdentity _identity = const HomeIdentity(
    role: 'viewer',
    companyName: 'SKO',
    displayName: 'ユーザー',
  );
  int _selectedIndex = 0;
  bool _chromeVisible = true;
  VoidCallback? _chromeListener;
  bool _canReviewEmployeeOnboarding = false;
  String _payrollAdjustmentLabel = '給与調整';
  RequiredDocumentAttention _requiredDocumentAttention =
      const RequiredDocumentAttention(
        missingCount: 0,
        missingNames: [],
        needsLicense: false,
        needsQualification: false,
      );
  HomeAttendanceStatus _homeAttendanceStatus = const HomeAttendanceStatus();

  bool get _isAdmin => _identity.isAdmin;

  @override
  void initState() {
    super.initState();
    _loadHomeData();
    _chromeListener = () {
      if (!mounted) return;
      final next = SkoScrollChromeController.visible.value;
      if (_chromeVisible != next) setState(() => _chromeVisible = next);
    };
    SkoScrollChromeController.visible.addListener(_chromeListener!);
    GpsAutoAttendanceService.instance.startIfConfigured();
  }

  @override
  void dispose() {
    if (_chromeListener != null) {
      SkoScrollChromeController.visible.removeListener(_chromeListener!);
    }
    GpsAutoAttendanceService.instance.stop();
    super.dispose();
  }

  Future<void> _loadHomeData() async {
    await Future.wait([
      _loadModuleSettings(),
      _loadIdentity(),
      _loadUsage(),
      _loadHomeLayout(),
      _loadHomeAppearance(),
      _loadEmployeeOnboardingCapability(),
      _loadRequiredDocumentAttention(),
      _loadHomeAttendanceStatus(),
      _loadPayrollAdjustmentAccess(),
      _syncLanguage(),
    ]);
  }

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
    if (value == null || !mounted) return;
    setState(() => _homeAppearance = value);
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
      setState(() => _identity = identity);
    } catch (_) {
      // Keep the safest default if identity loading fails.
    }
  }

  Future<void> _loadRequiredDocumentAttention() async {
    final repository = _homeAttentionRepository;
    if (repository == null) return;
    try {
      final value = await repository.loadRequiredDocumentAttention();
      if (!mounted) return;
      setState(() => _requiredDocumentAttention = value);
    } catch (_) {
      // Missing-document attention must not block the home screen.
    }
  }

  Future<void> _loadHomeAttendanceStatus() async {
    final repository = _attendanceVerificationRepository;
    if (repository == null) return;
    try {
      final value = await repository.loadHomeAttendanceStatus();
      if (!mounted) return;
      setState(() => _homeAttendanceStatus = value);
    } catch (_) {
      // Attendance status is supplemental and must not block the home screen.
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

  Future<void> _loadEmployeeOnboardingCapability() async {
    final repository = _employeeOnboardingRepository;
    if (repository == null) return;
    try {
      final value = await repository.canReview();
      if (!mounted) return;
      setState(() => _canReviewEmployeeOnboarding = value);
    } catch (_) {
      if (!mounted) return;
      setState(() => _canReviewEmployeeOnboarding = false);
    }
  }

  Future<void> _loadModuleSettings() async {
    final repository = _moduleSettingsRepository;
    if (repository == null) return;
    try {
      final states = await repository.loadOptionalModuleStates();
      if (!mounted) return;
      setState(() => _moduleStates = states);
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
    final prefs = await SharedPreferences.getInstance();
    final columns = (prefs.getInt('sko_home_grid_columns') ?? 2).clamp(1, 4);
    final order = prefs.getStringList('sko_home_action_order') ?? const <String>[];
    final hidden = prefs.getStringList('sko_home_hidden_actions') ?? const <String>[];
    if (!mounted) return;
    setState(() {
      _homeGridColumns = columns;
      _homeActionOrder = List<String>.from(order);
      _hiddenHomeActionKeys = hidden.toSet();
    });
  }

  Future<void> _setHomeGridColumns(int value) async {
    final next = value.clamp(1, 4);
    setState(() => _homeGridColumns = next);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('sko_home_grid_columns', next);
  }

  Future<void> _setHomeActionVisible(String key, bool visible) async {
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

  Future<void> _reorderHomeAction(int oldIndex, int newIndex) async {
    final items = _menuItems;
    if (oldIndex < 0 ||
        oldIndex >= items.length ||
        newIndex < 0 ||
        newIndex > items.length) {
      return;
    }
    final ordered = items.map((item) => item.key).toList();
    if (newIndex > oldIndex) newIndex -= 1;
    final moved = ordered.removeAt(oldIndex);
    final insertIndex = newIndex.clamp(0, ordered.length);
    ordered.insert(insertIndex, moved);
    setState(() => _homeActionOrder = ordered);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('sko_home_action_order', ordered);
  }

  Future<void> _reorderHomeActionByKey(
    String draggedKey,
    String targetKey,
  ) async {
    if (draggedKey == targetKey) return;

    final available = _menuItems.map((item) => item.key).toList();
    if (!available.contains(draggedKey) || !available.contains(targetKey)) {
      return;
    }

    final ordered = <String>[
      for (final key in _homeActionOrder)
        if (available.contains(key)) key,
      for (final key in available)
        if (!_homeActionOrder.contains(key)) key,
    ];

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
      'attendance' => 'attendance_sheet',
      'footer_sites' || 'site_register' || 'site_map' => 'sites',
      'chat' => 'chat',
      'clock_in' || 'clock_out' || 'attendance_verify' || 'workplace_select' || 'attendance_method_vehicle' => 'attendance',
      'daily_report' || 'approvals' => 'daily_report',
      'employee_register' ||
      'employee_onboarding_approvals' ||
      'people' ||
      'company_deliveries' => 'people',
      'company_documents' => 'documents',
      'payroll' || 'payroll_adjustments' => 'payroll',
      'profile' => 'profile',
      'help' => 'help',
      'admin_sites' => 'sites',
      'qualification_certificates' || 'qualifications' => 'qualifications',
      'documents' => 'documents',
      'vehicle_routes' => 'vehicle_routes',
      'settings' || 'appearance' || 'rollout' => 'settings',
      'invoices' => 'invoice',
      _ => null,
    };

    final featureKey = switch (key) {
      'clock_in' => 'clock_in',
      'clock_out' => 'clock_out',
      'attendance' || 'attendance_verify' || 'workplace_select' || 'attendance_method_vehicle' => 'attendance',
      'daily_report' || 'approvals' => 'daily_report',
      'payroll' || 'payroll_adjustments' => 'payroll',
      'invoices' => 'invoice',
      'chat' => 'chat',
      'people' || 'employee_register' || 'employee_onboarding_approvals' =>
        'people',
      'qualification_certificates' || 'qualifications' => 'qualifications',
      'documents' => 'documents',
      'company_deliveries' => 'company_connection',
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
    unawaited(_recordUsage(key));
    if (!mounted) return;

    final requiredModule = switch (key) {
      'attendance' || 'attendance_verify' || 'clock_in' || 'clock_out' =>
        'attendance',
      'footer_sites' || 'site_register' || 'site_map' || 'sites' => 'sites',
      'chat' => 'chat',
      'invoices' => 'invoices',
      'qualifications' || 'qualification_certificates' => 'qualifications',
      'documents' => 'documents',
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

    if (key == 'people' && !_identity.isManagement) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(SkoLanguageController.tr('社員情報は管理者・サブ管理者のみ利用できます'))),
      );
      return;
    }

    if ((key == 'company_deliveries' || key == 'company_documents') &&
        !_isAdmin) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(SkoLanguageController.tr('この機能は管理者のみ利用できます'))),
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

    _recordCloudUsageForAction(key);

    if (key == 'footer_home') {
      setState(() => _selectedIndex = 0);
      return;
    }
    if (key == 'attendance') {
      setState(() => _selectedIndex = 1);
      return;
    }
    if (key == 'attendance_today') {
      if (!_identity.can('can_manage_attendance')) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('この機能を利用する権限がありません')),
        );
        return;
      }
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => const TodayAttendancePage(),
        ),
      );
      return;
    }
    if (key == 'footer_sites' || key == 'site_register') {
      setState(() => _selectedIndex = 2);
      return;
    }
    if (key == 'chat') {
      setState(() => _selectedIndex = 3);
      return;
    }
    if (key == 'menu') {
      setState(() => _selectedIndex = 4);
      return;
    }

    Widget? page;

    switch (key) {
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
      case 'attendance_verify':
      case 'attendance_method_vehicle':
        page = const AttendanceSelectionPage();
        break;
      case 'workplace_select':
        page = const WorkDestinationSelectionPage();
        break;
      case 'daily_report':
        page = const DailyReportPage();
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
        page = EmployeeInvitePage(
          canAssignManagementRole: _identity.isAdmin,
        );
        break;
      case 'employee_onboarding_approvals':
        page = const EmployeeOnboardingApprovalsPage();
        break;
      case 'approvals':
        page = const DailyReportApprovalsPage();
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
      case 'profile':
        page = ProfilePage(
          role: ManualContent.fromMembershipRole(_identity.role),
        );
        break;
      case 'help':
        page = HelpPage(
          role: ManualContent.fromMembershipRole(_identity.role),
          visibleFeatureKeys: _menuItems.map((item) => item.key).toSet(),
        );
        break;
      case 'site_map':
        page = const SiteMapPage(
          allowEmployeeHomes: true,
          title: '管理者用現場マップ',
        );
        break;
      case 'admin_sites':
        page = const SecondaryProtectedPage(
          title: '管理者用現場データ',
          child: AdminSiteFinancialPage(),
        );
        break;
      case 'qualification_certificates':
        page = const QualificationCertificatePage();
        break;
      case 'documents':
        page = const WorkerDocumentPage();
        break;
      case 'company_deliveries':
        page = const CompanyDeliveryInboxPage();
        break;
      case 'company_documents':
        page = const CompanySubmittedDocumentsPage();
        break;
      case 'signatures':
        page = const SignatureListPage();
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

    if (key == 'clock_in' ||
        key == 'clock_out' ||
        key == 'attendance_verify' ||
        key == 'attendance_method_vehicle' ||
        key == 'workplace_select' ||
        key == 'vehicle_select' ||
        key == 'route_select') {
      await _loadHomeAttendanceStatus();
    }
    if (key == 'settings') {
      await _loadModuleSettings();
    }
    if (key == 'profile') {
      await _loadIdentity();
    }
    if (key == 'payroll_adjustments') {
      await _loadPayrollAdjustmentAccess();
      await _loadIdentity();
    }
  }

  List<_MenuAction> get _menuItems {
    final items = <_MenuAction>[
      if (_moduleEnabled('attendance'))
        _MenuAction(
          key: 'attendance_verify',
          label: SkoLanguageController.tr('本日の勤務報告'),
          icon: Icons.fact_check_outlined,
          homeEligible: false,
          accessLabel: SkoLanguageController.tr('管理者・サブ管理者・一般・閲覧権限'),
        ),
      if (_moduleEnabled('attendance') &&
          _identity.can('can_manage_attendance'))
        _MenuAction(
          key: 'attendance_today',
          label: SkoLanguageController.tr('本日の出勤'),
          icon: Icons.groups_outlined,
          homeEligible: false,
          accessLabel: SkoLanguageController.tr('管理者・サブ管理者（勤怠権限）'),
        ),
      _MenuAction(
        key: 'daily_report',
        label: SkoLanguageController.tr('日報'),
        icon: Icons.description_outlined,
        homeEligible: true,
        accessLabel: SkoLanguageController.tr('管理者・サブ管理者・一般・閲覧権限'),
      ),
      if (_identity.isManagement)
        _MenuAction(
          key: 'people',
          label: SkoLanguageController.tr('社員'),
          icon: Icons.groups_2_outlined,
          homeEligible: true,
          accessLabel: SkoLanguageController.tr('管理者・サブ管理者・閲覧権限'),
        ),
      if (_moduleEnabled('vehicle_routes'))
        _MenuAction(
          key: 'vehicle_routes',
          label: SkoLanguageController.tr('車両・ルート'),
          icon: Icons.route_outlined,
          homeEligible: true,
          accessLabel: SkoLanguageController.tr('管理者・サブ管理者・一般・閲覧権限'),
        ),
      _MenuAction(
        key: 'employee_register',
        label: SkoLanguageController.tr('従業員登録'),
        icon: Icons.person_add_alt_1,
        accessLabel: SkoLanguageController.tr('管理者・サブ管理者'),
      ),
      if (_canReviewEmployeeOnboarding)
        _MenuAction(
          key: 'employee_onboarding_approvals',
          label: SkoLanguageController.tr('本登録承認'),
          icon: Icons.verified_user_outlined,
          accessLabel: SkoLanguageController.tr('管理者・サブ管理者（承認権限）'),
        ),
      if (!_isAdmin)
        _MenuAction(
          key: 'payroll',
          label: SkoLanguageController.tr('給与明細'),
          icon: Icons.payments_outlined,
          homeEligible: true,
          accessLabel: SkoLanguageController.tr('本人・閲覧権限'),
        ),
      if (_isAdmin || _identity.can('can_manage_payroll_adjustments'))
        _MenuAction(
          key: 'payroll_settings',
          label: SkoLanguageController.tr('個別給与設定'),
          icon: Icons.manage_accounts_outlined,
          accessLabel: SkoLanguageController.tr('管理者・給与編集権限'),
        ),
      if (_identity.can('can_view_payroll_adjustments'))
        _MenuAction(
          key: 'payroll_adjustments',
          label: _payrollAdjustmentLabel,
          icon: Icons.price_change_outlined,
          accessLabel: SkoLanguageController.tr('管理者・給与閲覧権限'),
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
          key: 'qualifications',
          label: SkoLanguageController.tr('資格'),
          icon: Icons.badge_outlined,
          accessLabel: SkoLanguageController.tr('管理者・サブ管理者・一般・閲覧権限'),
        ),
      if (_moduleEnabled('documents'))
        _MenuAction(
          key: 'documents',
          label: SkoLanguageController.tr('必要書類'),
          icon: Icons.fact_check_outlined,
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
      if (_identity.can('can_approve_daily_report_edits'))
        _MenuAction(
          key: 'approvals',
          label: SkoLanguageController.tr('承認待ち'),
          icon: Icons.approval_outlined,
          accessLabel: SkoLanguageController.tr('管理者・サブ管理者（承認権限）'),
        ),
      if (_identity.can('can_manage_attendance') &&
          _moduleEnabled('line_bridge'))
        _MenuAction(
          key: 'today_line',
          label: SkoLanguageController.tr('本日のLINE出勤候補'),
          icon: Icons.today_outlined,
          accessLabel: SkoLanguageController.tr('管理者・サブ管理者（勤怠権限）'),
        ),
      if (_isAdmin)
        _MenuAction(
          key: 'company_deliveries',
          label: SkoLanguageController.tr('協力会社'),
          icon: Icons.folder_shared_outlined,
          accessLabel: SkoLanguageController.tr('管理者'),
        ),
      if (_isAdmin)
        _MenuAction(
          key: 'company_documents',
          label: SkoLanguageController.tr('会社データ'),
          icon: Icons.business_center_outlined,
          homeEligible: true,
          accessLabel: SkoLanguageController.tr('管理者'),
        ),
      if (_moduleEnabled('invoices') && _identity.can('can_view_invoices'))
        _MenuAction(
          key: 'invoices',
          label: SkoLanguageController.tr('請求書'),
          icon: Icons.receipt_long_outlined,
          homeEligible: true,
          accessLabel: SkoLanguageController.tr('管理者・請求書閲覧権限'),
        ),
      if (_identity.can('can_view_admin_site_data'))
        _MenuAction(
          key: 'admin_sites',
          label: SkoLanguageController.tr('管理現場'),
          icon: Icons.admin_panel_settings_outlined,
          homeEligible: true,
          accessLabel: SkoLanguageController.tr('管理者・現場閲覧権限'),
        ),
      if (_identity.isManagement && _moduleEnabled('sites'))
        _MenuAction(
          key: 'site_map',
          label: SkoLanguageController.tr('現場マップ'),
          icon: Icons.map_outlined,
          homeEligible: true,
          accessLabel: SkoLanguageController.tr('管理者・サブ管理者'),
        ),
      if (!_identity.isManagement && _moduleEnabled('sites'))
        _MenuAction(
          key: 'site_register',
          label: SkoLanguageController.tr('現場登録'),
          icon: Icons.add_business_outlined,
          homeEligible: true,
          accessLabel: SkoLanguageController.tr('一般・閲覧権限'),
        ),
      if (_isAdmin)
        _MenuAction(
          key: 'signatures',
          label: SkoLanguageController.tr('サイン一覧'),
          icon: Icons.draw_outlined,
          accessLabel: SkoLanguageController.tr('管理者'),
        ),
      _MenuAction(
        key: 'appearance',
        label: SkoLanguageController.tr('背景・ヘッダー・フッター設定'),
        icon: Icons.wallpaper_outlined,
        homeEligible: true,
        accessLabel: SkoLanguageController.tr('本人のみ'),
      ),
      _MenuAction(
        key: 'settings',
        label: SkoLanguageController.tr('設定'),
        icon: Icons.settings_outlined,
        homeEligible: true,
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

    final rank = <String, int>{
      for (var i = 0; i < _homeActionOrder.length; i++)
        _homeActionOrder[i]: i,
    };
    items.sort((a, b) {
      final ai = rank[a.key] ?? 100000;
      final bi = rank[b.key] ?? 100000;
      if (ai != bi) return ai.compareTo(bi);
      return a.label.compareTo(b.label);
    });
    return items;
  }

  Widget _homeDashboard() {
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
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
        ),
        if (wallpaperPath != null && File(wallpaperPath).existsSync())
          Opacity(
            opacity: _homeAppearance.wallpaperOpacity,
            child: Image.file(
              File(wallpaperPath),
              fit: BoxFit.cover,
            ),
          ),
        Scaffold(
          extendBodyBehindAppBar: false,
          backgroundColor: Colors.transparent,
          appBar: PreferredSize(
        preferredSize: Size.fromHeight(_chromeVisible ? 64 : 0),
        child: AppBar(
          toolbarHeight: _chromeVisible ? 64 : 0,
          backgroundColor: Colors.transparent,
          forceMaterialTransparency: true,
          flexibleSpace: ColoredBox(
            color: Theme.of(context)
                .colorScheme
                .surface
                .withValues(alpha: _homeAppearance.headerOpacity),
          ),
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
      ),
      body: FriendlyHomeContent(
          identity: _identity,
          requiredDocumentAttention: _requiredDocumentAttention,
          moduleEnabled: _moduleEnabled,
          gridColumns: _homeGridColumns,
          actionOrder: _homeActionOrder,
          visibleHomeKeys: {
            for (final item in _menuItems)
              if (!_hiddenHomeActionKeys.contains(item.key)) item.key,
          },
          shortcuts: [
            for (final item in _homeLayoutItems)
              HomeShortcut(item.key, item.label, item.icon),
          ],
          showAttendanceReport:
              !_hiddenHomeActionKeys.contains('attendance_verify'),
          showTodayAttendance:
              !_hiddenHomeActionKeys.contains('attendance_today'),
          attendanceStatus: _homeAttendanceStatus,
          appearance: bodyAppearance,
          contentTopInset: 8,
          onOpen: _openHomeAction,
          onRefresh: _loadHomeData,
          onReorderAction: _reorderHomeActionByKey,
        ),
      ],
    );
  }

  List<_HomeLayoutItem> get _homeLayoutItems {
    return [
      for (final item in _menuItems)
        if (item.homeEligible && !_hiddenHomeActionKeys.contains(item.key))
          _HomeLayoutItem(item.key, item.label, item.icon),
    ];
  }

  Widget _menuPage() {
    final items = _menuItems;
    return Scaffold(
      appBar: PreferredSize(
        preferredSize: Size.fromHeight(_chromeVisible ? kToolbarHeight : 0),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          height: _chromeVisible ? kToolbarHeight : 0,
          child: _chromeVisible
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
      body: SafeArea(
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
                            ? 'Manage Home and Menu in one list. Toggle visibility, drag to reorder, and choose 1–4 columns.'
                            : 'ホームとメニューを同じ一覧で管理します。管理者メニューに表示される全項目をホームボタンにできます。スイッチで表示ON/OFF、項目を長押しして上下へドラッグ、1〜4列を選択できます。',
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
            return Padding(
              key: ValueKey('menu_${item.key}'),
              padding: const EdgeInsets.only(bottom: 8),
              child: Card(
                child: ListTile(
                  leading: const Icon(Icons.drag_handle),
                  title: Text(
                    item.label,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  subtitle: Text('${SkoLanguageController.tr('利用権限')}：${item.accessLabel}'),
                  onTap: () => _openHomeAction(item.key),
                  trailing: Switch(
                    value: !_hiddenHomeActionKeys.contains(item.key),
                    onChanged: (value) =>
                        _setHomeActionVisible(item.key, value),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      _homeDashboard(),
      _moduleEnabled('attendance')
          ? const WorkerAttendanceSheetPage()
          : _ModuleDisabledPage(label: SkoLanguageController.tr('出勤表')),
      _moduleEnabled('sites')
          ? const SiteCloudPage()
          : _ModuleDisabledPage(label: SkoLanguageController.tr('現場')),
      _moduleEnabled('chat')
          ? const ChatCloudPage()
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
      bottomNavigationBar: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        height: _chromeVisible ? 88 : 0,
        child: _chromeVisible
            ? NavigationBar(
                  backgroundColor: Theme.of(context)
                      .colorScheme
                      .surface
                      .withValues(alpha: _homeAppearance.footerOpacity),
                  surfaceTintColor: Colors.transparent,
                  selectedIndex: _selectedIndex,
                  onDestinationSelected: (index) {
                    final module = switch (index) {
                      1 => 'attendance',
                      2 => 'sites',
                      3 => 'chat',
                      _ => null,
                    };
                    if (module != null && !_moduleEnabled(module)) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(SkoLanguageController.tr('この機能は会社設定でOFFになっています')),
                        ),
                      );
                      return;
                    }
                    final usageKey = switch (index) {
                      0 => 'footer_home',
                      1 => 'attendance',
                      2 => 'footer_sites',
                      3 => 'chat',
                      _ => null,
                    };
                    if (usageKey != null) {
                      _recordCloudUsageForAction(usageKey);
                    }
                    setState(() => _selectedIndex = index);
                  },
                  destinations: [
                    NavigationDestination(
                      icon: Icon(Icons.home_outlined),
                      selectedIcon: Icon(Icons.home),
                      label: SkoLanguageController.tr('ホーム'),
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.calendar_month_outlined),
                      selectedIcon: Icon(Icons.calendar_month),
                      label: SkoLanguageController.tr('出勤表'),
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.business_outlined),
                      selectedIcon: Icon(Icons.business),
                      label: SkoLanguageController.tr('現場'),
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.chat_bubble_outline),
                      selectedIcon: Icon(Icons.chat_bubble),
                      label: SkoLanguageController.tr('チャット'),
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.menu),
                      label: SkoLanguageController.tr('メニュー'),
                    ),
                  ],
                )
            : const SizedBox.shrink(),
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
  const _HomeLayoutItem(this.key, this.label, this.icon);

  final String key;
  final String label;
  final IconData icon;
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
                  '認証サーバーの設定を読み込めないため、ログインや管理機能は開いていません。Macの実機準備スクリプトでSupabase設定を確認してから再起動してください。',
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
