import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart' as legacy;
import 'branding/product_brand.dart';
import 'data/supabase_backend.dart';
import 'features/albums/albums_cloud_page.dart';
import 'features/attendance/attendance_cloud_page.dart';
import 'features/attendance/attendance_page.dart';
import 'features/attendance/attendance_verification_page.dart';
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
import 'features/home/home_membership_repository.dart';
import 'features/invoices/invoice_cloud_page.dart';
import 'features/invoices/invoice_page.dart';
import 'features/notes/notes_cloud_page.dart';
import 'features/notifications/notification_bell.dart';
import 'features/payroll/payroll_statements_page.dart';
import 'features/people/employee_invite_page.dart';
import 'features/people/people_cloud_page.dart';
import 'features/people/people_page.dart';
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
import 'features/sites/site_page.dart';

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
    const seed = Color(0xFF173B57);
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: ProductBrand.displayName,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: seed),
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF4F6F8),
        cardTheme: CardThemeData(
          elevation: 0,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            minimumSize: const Size(0, 48),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
      ),
      home: SupabaseBackend.isInitialized
          ? SupabaseAuthGate(
              homeBuilder: (onSignOut) => HomePage(onSignOut: onSignOut),
            )
          : allowLocalFallback
              ? const HomePage()
              : const _BackendUnavailableScreen(),
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

  Map<String, bool> _moduleStates = const {};
  Map<String, int> _usage = const {};
  HomeIdentity _identity = const HomeIdentity(
    role: 'viewer',
    companyName: 'SKO',
    displayName: 'ユーザー',
  );
  int _selectedIndex = 0;
  bool _canReviewEmployeeOnboarding = false;
  RequiredDocumentAttention _requiredDocumentAttention =
      const RequiredDocumentAttention(
        missingCount: 0,
        missingNames: [],
        needsLicense: false,
        needsQualification: false,
      );

  bool get _isAdmin => _identity.isAdmin;

  @override
  void initState() {
    super.initState();
    _loadHomeData();
  }

  Future<void> _loadHomeData() async {
    await Future.wait([
      _loadModuleSettings(),
      _loadIdentity(),
      _loadUsage(),
      _loadEmployeeOnboardingCapability(),
      _loadRequiredDocumentAttention(),
    ]);
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
      'footer_sites' || 'site_register' || 'sites' => 'sites',
      'chat' => 'chat',
      'invoices' => 'invoices',
      'qualifications' || 'qualification_certificates' => 'qualifications',
      'documents' => 'documents',
      'notes' => 'notes',
      'albums' => 'albums',
      'today_line' || 'line_history' => 'line_bridge',
      _ => null,
    };
    if (requiredModule != null && !_moduleEnabled(requiredModule)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('この機能は会社設定でOFFになっています')),
      );
      return;
    }

    final restricted = <String, String>{
      'approvals': 'can_approve_daily_report_edits',
      'invoices': 'can_view_invoices',
      'admin_sites': 'can_view_admin_site_data',
      'people': 'can_manage_people',
    };
    final permission = restricted[key];
    if (permission != null && !_identity.can(permission)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('この機能を利用する権限がありません')),
      );
      return;
    }

    if (key == 'footer_home') {
      setState(() => _selectedIndex = 0);
      return;
    }
    if (key == 'attendance') {
      setState(() => _selectedIndex = 1);
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
        page = const AttendanceVerificationPage();
        break;
      case 'daily_report':
        page = const DailyReportPage();
        break;
      case 'employee_register':
        page = const EmployeeInvitePage();
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
      case 'profile':
        page = ProfilePage(
          role: ManualContent.fromMembershipRole(_identity.role),
        );
        break;
      case 'help':
        page = HelpPage(
          role: ManualContent.fromMembershipRole(_identity.role),
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

    if (key == 'settings') {
      await _loadModuleSettings();
    }
    if (key == 'profile') {
      await _loadIdentity();
    }
  }

  List<_MenuAction> get _menuItems {
    final items = <_MenuAction>[
      const _MenuAction(
        key: 'daily_report',
        label: '日報',
        icon: Icons.description_outlined,
      ),
      const _MenuAction(
        key: 'employee_register',
        label: '従業員登録',
        icon: Icons.person_add_alt_1,
      ),
      if (_canReviewEmployeeOnboarding)
        const _MenuAction(
          key: 'employee_onboarding_approvals',
          label: '本登録承認',
          icon: Icons.verified_user_outlined,
        ),
      if (!_isAdmin)
        const _MenuAction(
          key: 'payroll',
          label: '給与明細',
          icon: Icons.payments_outlined,
        ),
      const _MenuAction(
        key: 'profile',
        label: 'プロフィール',
        icon: Icons.account_circle_outlined,
      ),
      if (_moduleEnabled('qualifications'))
        const _MenuAction(
          key: 'qualifications',
          label: '資格',
          icon: Icons.badge_outlined,
        ),
      if (_moduleEnabled('documents'))
        const _MenuAction(
          key: 'documents',
          label: '必要書類',
          icon: Icons.fact_check_outlined,
        ),
      if (_moduleEnabled('notes'))
        const _MenuAction(
          key: 'notes',
          label: 'ノート',
          icon: Icons.sticky_note_2_outlined,
        ),
      if (_moduleEnabled('albums'))
        const _MenuAction(
          key: 'albums',
          label: 'アルバム',
          icon: Icons.photo_album_outlined,
        ),
      if (_isAdmin && _identity.can('can_approve_daily_report_edits'))
        const _MenuAction(
          key: 'approvals',
          label: '承認待ち',
          icon: Icons.approval_outlined,
        ),
      if (_isAdmin &&
          _identity.can('can_manage_attendance') &&
          _moduleEnabled('line_bridge'))
        const _MenuAction(
          key: 'today_line',
          label: '本日のLINE出勤候補',
          icon: Icons.today_outlined,
        ),
      if (_isAdmin)
        const _MenuAction(
          key: 'rollout',
          label: '運用準備チェック',
          icon: Icons.checklist_rtl_outlined,
        ),
      const _MenuAction(
        key: 'settings',
        label: '設定',
        icon: Icons.settings_outlined,
      ),
      const _MenuAction(
        key: 'help',
        label: 'ヘルプ',
        icon: Icons.help_outline,
      ),
    ];

    items.sort((a, b) {
      final byUsage = (_usage[b.key] ?? 0).compareTo(_usage[a.key] ?? 0);
      if (byUsage != 0) return byUsage;
      return a.label.compareTo(b.label);
    });
    return items;
  }

  Widget _homeDashboard() {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _identity.companyName,
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        actions: [
          const SkoNotificationBell(),
          if (widget.onSignOut != null)
            IconButton(
              tooltip: 'ログアウト',
              onPressed: widget.onSignOut,
              icon: const Icon(Icons.logout),
            ),
        ],
      ),
      body: SafeArea(
        child: FriendlyHomeContent(
          identity: _identity,
          requiredDocumentAttention: _requiredDocumentAttention,
          moduleEnabled: _moduleEnabled,
          onOpen: _openHomeAction,
          onRefresh: _loadHomeData,
        ),
      ),
    );
  }

  Widget _menuPage() {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'メニュー',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        actions: const [SkoNotificationBell()],
      ),
      body: SafeArea(
        child: ListView.separated(
          padding: const EdgeInsets.all(12),
          itemCount: _menuItems.length + 1,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            if (index == 0) {
              return const Padding(
                padding: EdgeInsets.fromLTRB(6, 4, 6, 6),
                child: Text(
                  'よく使う機能ほど上に表示されます',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              );
            }

            final item = _menuItems[index - 1];
            return Card(
              child: ListTile(
                leading: CircleAvatar(child: Icon(item.icon)),
                title: Text(
                  item.label,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _openHomeAction(item.key),
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
          ? (_identity.can('can_manage_attendance')
              ? const AttendanceCloudPage()
              : const WorkerAttendanceSheetPage())
          : const _ModuleDisabledPage(label: '出勤表'),
      _moduleEnabled('sites')
          ? const SiteCloudPage()
          : const _ModuleDisabledPage(label: '現場'),
      _moduleEnabled('chat')
          ? const ChatCloudPage()
          : const _ModuleDisabledPage(label: 'チャット'),
      _menuPage(),
    ];

    return Scaffold(
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
      bottomNavigationBar: NavigationBar(
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
              const SnackBar(content: Text('この機能は会社設定でOFFになっています')),
            );
            return;
          }
          setState(() => _selectedIndex = index);
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'ホーム',
          ),
          NavigationDestination(
            icon: Icon(Icons.calendar_month_outlined),
            selectedIcon: Icon(Icons.calendar_month),
            label: '出勤表',
          ),
          NavigationDestination(
            icon: Icon(Icons.business_outlined),
            selectedIcon: Icon(Icons.business),
            label: '現場',
          ),
          NavigationDestination(
            icon: Icon(Icons.chat_bubble_outline),
            selectedIcon: Icon(Icons.chat_bubble),
            label: 'チャット',
          ),
          NavigationDestination(
            icon: Icon(Icons.menu),
            label: 'メニュー',
          ),
        ],
      ),
    );
  }
}

class _MenuAction {
  const _MenuAction({
    required this.key,
    required this.label,
    required this.icon,
  });

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
