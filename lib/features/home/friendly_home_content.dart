import 'dart:io';

import 'package:flutter/material.dart';

import '../attendance/attendance_verification_repository.dart';
import 'home_attention_repository.dart';
import 'home_appearance.dart';
import 'home_membership_repository.dart';

class FriendlyHomeContent extends StatelessWidget {
  const FriendlyHomeContent({
    super.key,
    required this.identity,
    required this.requiredDocumentAttention,
    required this.moduleEnabled,
    this.gridColumns = 2,
    this.actionOrder = const <String>[],
    this.visibleHomeKeys = const <String>{},
    this.attendanceStatus = const HomeAttendanceStatus(),
    this.appearance = const HomeAppearance(),
    required this.onOpen,
    required this.onRefresh,
  });

  final HomeIdentity identity;
  final RequiredDocumentAttention requiredDocumentAttention;
  final bool Function(String key) moduleEnabled;
  final int gridColumns;
  final List<String> actionOrder;
  final Set<String> visibleHomeKeys;
  final HomeAttendanceStatus attendanceStatus;
  final HomeAppearance appearance;
  final Future<void> Function(String key) onOpen;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final wallpaperPath = appearance.wallpaperPath;
    return Stack(
      fit: StackFit.expand,
      children: [
        if (wallpaperPath != null && File(wallpaperPath).existsSync())
          Opacity(
            opacity: appearance.wallpaperOpacity,
            child: Image.file(
              File(wallpaperPath),
              fit: BoxFit.cover,
            ),
          ),
        RefreshIndicator(
          onRefresh: onRefresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 32),
            children: [
              Opacity(
                opacity: appearance.headerOpacity,
                child: _GreetingCard(identity: identity),
              ),
              if (requiredDocumentAttention.hasMissing) ...[
                const SizedBox(height: 12),
                Opacity(
                  opacity: appearance.cardOpacity,
                  child: _RequiredDocumentAttentionCard(
                    attention: requiredDocumentAttention,
                    onOpen: onOpen,
                  ),
                ),
              ],
              if (moduleEnabled('attendance')) ...[
                const SizedBox(height: 12),
                Opacity(
                  opacity: appearance.cardOpacity,
                  child: _PersonalAttendanceCard(
                    status: attendanceStatus,
                    vehicleRoutesEnabled: moduleEnabled('vehicle_routes'),
                    onOpen: onOpen,
                  ),
                ),
              ],
              const SizedBox(height: 14),
              if (identity.isManagement)
                _AdminHome(
                  identity: identity,
                  moduleEnabled: moduleEnabled,
                  gridColumns: gridColumns,
                  actionOrder: actionOrder,
                  visibleHomeKeys: visibleHomeKeys,
                  appearance: appearance,
                  onOpen: onOpen,
                )
              else
                _WorkerHome(
                  moduleEnabled: moduleEnabled,
                  gridColumns: gridColumns,
                  actionOrder: actionOrder,
                  visibleHomeKeys: visibleHomeKeys,
                  appearance: appearance,
                  onOpen: onOpen,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _GreetingCard extends StatelessWidget {
  const _GreetingCard({required this.identity});

  final HomeIdentity identity;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Text(
                  identity.companyName,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text(
                  identity.roleLabel,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Row(
            children: [
              Expanded(
                child: Text(
                  identity.displayName,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
              ),
              Text(
                '${now.year}年${now.month}月${now.day}日',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RequiredDocumentAttentionCard extends StatelessWidget {
  const _RequiredDocumentAttentionCard({
    required this.attention,
    required this.onOpen,
  });

  final RequiredDocumentAttention attention;
  final Future<void> Function(String key) onOpen;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      color: scheme.surface,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: scheme.primary, width: 1.5),
        borderRadius: BorderRadius.circular(16),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => onOpen('documents'),
        child: IntrinsicHeight(
          child: Row(
            children: [
              Container(
                width: 50,
                decoration: BoxDecoration(
                  color: scheme.primary,
                  borderRadius: const BorderRadius.horizontal(
                    left: Radius.circular(14),
                  ),
                ),
                alignment: Alignment.center,
                child: Icon(
                  Icons.notifications_active_outlined,
                  color: scheme.onPrimary,
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text(
                          '要対応',
                          style: TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ),
                      Text(
                        '未対応 ${attention.missingCount}件',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(width: 4),
                      const Icon(Icons.chevron_right),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PersonalAttendanceCard extends StatelessWidget {
  const _PersonalAttendanceCard({
    required this.status,
    required this.vehicleRoutesEnabled,
    required this.onOpen,
  });

  final HomeAttendanceStatus status;
  final bool vehicleRoutesEnabled;
  final Future<void> Function(String key) onOpen;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final isWorking = status.phase == HomeAttendancePhase.working;
    final isFinished = status.phase == HomeAttendancePhase.finished;

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '本日の勤務報告',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(
                    color: isWorking
                        ? colors.primaryContainer
                        : colors.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Text(
                    status.phaseLabel,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 9),
            Text(
              '選択中の出勤方法：${status.verificationModeLabel}',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 3),
            Text(
              '選択中の現場：${status.siteName?.trim().isNotEmpty == true ? status.siteName : '未選択'}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            if (vehicleRoutesEnabled &&
                status.selectedVehicleName?.trim().isNotEmpty == true) ...[
              const SizedBox(height: 3),
              Text(
                '選択中の車両：${status.selectedVehicleName}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ],
            if (vehicleRoutesEnabled &&
                status.selectedRouteName?.trim().isNotEmpty == true) ...[
              const SizedBox(height: 3),
              Text(
                '選択中のルート：${status.selectedRouteName}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ],
            if (status.clockIn != null || status.clockOut != null) ...[
              const SizedBox(height: 5),
              Text(
                '出勤 ${_time(status.clockIn)}　退勤 ${_time(status.clockOut)}',
                style: TextStyle(
                  color: colors.onSurfaceVariant,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () => onOpen('attendance_verify'),
              icon: const Icon(Icons.tune_outlined),
              label: const Text('出勤方法と現場を選択'),
            ),
            if (vehicleRoutesEnabled) ...[
              const SizedBox(height: 9),
              OutlinedButton.icon(
                onPressed: () => onOpen('vehicle_route_select'),
                icon: const Icon(Icons.route_outlined),
                label: const Text('車両とルートの選択'),
              ),
            ],
            const SizedBox(height: 9),
            Row(
              children: [
                Expanded(
                  child: isWorking || isFinished
                      ? OutlinedButton.icon(
                          onPressed: () => onOpen('clock_in'),
                          icon: const Icon(Icons.login),
                          label: const Text('出勤'),
                        )
                      : FilledButton.icon(
                          onPressed: () => onOpen('clock_in'),
                          icon: const Icon(Icons.login),
                          label: const Text('出勤'),
                        ),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: isWorking
                      ? FilledButton.icon(
                          onPressed: () => onOpen('clock_out'),
                          icon: const Icon(Icons.logout),
                          label: const Text('退勤'),
                        )
                      : OutlinedButton.icon(
                          onPressed: () => onOpen('clock_out'),
                          icon: const Icon(Icons.logout),
                          label: const Text('退勤'),
                        ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _time(DateTime? value) {
    if (value == null) return '--:--';
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(value.hour)}:${two(value.minute)}';
  }
}

class _WorkerHome extends StatelessWidget {
  const _WorkerHome({
    required this.moduleEnabled,
    required this.gridColumns,
    required this.actionOrder,
    required this.visibleHomeKeys,
    required this.appearance,
    required this.onOpen,
  });

  final bool Function(String key) moduleEnabled;
  final int gridColumns;
  final List<String> actionOrder;
  final Set<String> visibleHomeKeys;
  final HomeAppearance appearance;
  final Future<void> Function(String key) onOpen;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SectionTitle('ホーム'),
        const SizedBox(height: 9),
        _ActionGrid(
          items: [
            if (visibleHomeKeys.contains('payroll'))
const _HomeAction(
              'payroll',
              '給与明細',
              Icons.payments_outlined,
            ),
            if (visibleHomeKeys.contains('profile'))
const _HomeAction(
              'profile',
              'プロフィール',
              Icons.account_circle_outlined,
            ),
            if (moduleEnabled('vehicle_routes') && visibleHomeKeys.contains('vehicle_routes'))
const _HomeAction(
              'vehicle_routes',
              '車両・ルート',
              Icons.route_outlined,
            ),
            if (moduleEnabled('sites') && visibleHomeKeys.contains('site_register'))
              const _HomeAction(
                'site_register',
                '現場登録',
                Icons.add_business_outlined,
              ),
            if (visibleHomeKeys.contains('settings'))
const _HomeAction(
              'settings',
              '設定',
              Icons.settings_outlined,
            ),
            if (visibleHomeKeys.contains('help'))
const _HomeAction(
              'help',
              'ヘルプ',
              Icons.help_outline,
            ),
          ],
          columns: gridColumns,
          actionOrder: actionOrder,
          opacity: appearance.buttonOpacity,
          onOpen: onOpen,
        ),
        const SizedBox(height: 18),
        Opacity(
          opacity: appearance.cardOpacity,
          child: Card(
          child: ListTile(
            leading: const CircleAvatar(
              child: Icon(Icons.auto_awesome_outlined),
            ),
            title: const Text(
              '仕事が終わったら日報へ',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
            subtitle: const Text(
              '朝の出勤メンバーは自動反映されます。作業内容・残業・手当を確認して責任者サインをもらいます。',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => onOpen('daily_report'),
          ),
        ),
        ),
      ],
    );
  }
}

class _AdminHome extends StatelessWidget {
  const _AdminHome({
    required this.identity,
    required this.moduleEnabled,
    required this.gridColumns,
    required this.actionOrder,
    required this.visibleHomeKeys,
    required this.appearance,
    required this.onOpen,
  });

  final HomeIdentity identity;
  final bool Function(String key) moduleEnabled;
  final int gridColumns;
  final List<String> actionOrder;
  final Set<String> visibleHomeKeys;
  final HomeAppearance appearance;
  final Future<void> Function(String key) onOpen;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (moduleEnabled('attendance') &&
            identity.can('can_manage_attendance'))
          Opacity(
            opacity: appearance.cardOpacity,
            child: Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '本日の出勤',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                ),
                const SizedBox(height: 6),
                const Text(
                  '自社と下請けを分けて、現場ごとの出勤人数を確認できます。',
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: () => onOpen('attendance_today'),
                  icon: const Icon(Icons.groups_outlined),
                  label: const Text('出勤状況を確認'),
                ),
              ],
            ),
          ),
        ),
          ),
        if (moduleEnabled('attendance') &&
            identity.can('can_manage_attendance'))
          const SizedBox(height: 12),
        const _SectionTitle('管理'),
        const SizedBox(height: 9),
        _ActionGrid(
          items: [
            if (identity.can('can_manage_people') && visibleHomeKeys.contains('people'))
              const _HomeAction(
                'people',
                '社員',
                Icons.groups_2_outlined,
                access: _HomeActionAccess.subAdmin,
              ),
            if (moduleEnabled('invoices') &&
                identity.can('can_view_invoices') &&
                visibleHomeKeys.contains('invoices'))
              const _HomeAction(
                'invoices',
                '請求書',
                Icons.receipt_long_outlined,
                access: _HomeActionAccess.professional,
              ),
            if (identity.can('can_view_admin_site_data') &&
                visibleHomeKeys.contains('admin_sites'))
              const _HomeAction(
                'admin_sites',
                '管理現場',
                Icons.admin_panel_settings_outlined,
                access: _HomeActionAccess.admin,
              ),
            if (identity.isAdmin && visibleHomeKeys.contains('company_documents'))
              const _HomeAction(
                'company_documents',
                '会社提出書類',
                Icons.business_center_outlined,
                access: _HomeActionAccess.admin,
              ),
            if (moduleEnabled('vehicle_routes') && visibleHomeKeys.contains('vehicle_routes'))
              const _HomeAction(
                'vehicle_routes',
                '車両・ルート',
                Icons.route_outlined,
              ),
            if (visibleHomeKeys.contains('settings'))
              const _HomeAction(
              'settings',
              '設定',
              Icons.settings_outlined,
            ),
          ],
          columns: gridColumns,
          actionOrder: actionOrder,
          opacity: appearance.buttonOpacity,
          onOpen: onOpen,
        ),
        const SizedBox(height: 18),
        Opacity(
          opacity: appearance.cardOpacity,
          child: Card(
          child: ListTile(
            leading: const CircleAvatar(
              child: Icon(Icons.description_outlined),
            ),
            title: const Text(
              '日報',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
            subtitle: const Text('日報の入力・サイン・印刷を確認'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => onOpen('daily_report'),
          ),
        ),
        ),
      ],
    );
  }
}

class _ActionGrid extends StatelessWidget {
  const _ActionGrid({
    required this.items,
    required this.columns,
    required this.actionOrder,
    required this.opacity,
    required this.onOpen,
  });

  final List<_HomeAction> items;
  final int columns;
  final List<String> actionOrder;
  final double opacity;
  final Future<void> Function(String key) onOpen;

  @override
  Widget build(BuildContext context) {
    final columnCount = columns.clamp(1, 4);
    final rank = <String, int>{
      for (var i = 0; i < actionOrder.length; i++) actionOrder[i]: i,
    };
    final ordered = List<_HomeAction>.from(items);
    ordered.sort((a, b) {
      final ai = rank[a.key] ?? 100000;
      final bi = rank[b.key] ?? 100000;
      if (ai != bi) return ai.compareTo(bi);
      return 0;
    });

    final ratio = switch (columnCount) {
      1 => 4.2,
      2 => 1.55,
      3 => 0.80,
      _ => 0.68,
    };

    return Opacity(
      opacity: opacity,
      child: GridView.count(
      crossAxisCount: columnCount,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: ratio,
      children: [
        for (final item in ordered)
          _HomeActionTile(
            item: item,
            compact: columnCount >= 3,
            onOpen: onOpen,
          ),
      ],
      ),
    );
  }
}

class _HomeActionTile extends StatelessWidget {
  const _HomeActionTile({
    required this.item,
    required this.compact,
    required this.onOpen,
  });

  final _HomeAction item;
  final bool compact;
  final Future<void> Function(String key) onOpen;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isSubAdmin = item.access == _HomeActionAccess.subAdmin;
    final isAdmin = item.access == _HomeActionAccess.admin ||
        item.access == _HomeActionAccess.professional;
    final isProfessional = item.access == _HomeActionAccess.professional;
    final background = scheme.surfaceContainerLowest;
    final borderColor =
        (isSubAdmin || isAdmin) ? scheme.primary : scheme.outlineVariant;
    final borderWidth = (isSubAdmin || isAdmin) ? 2.0 : 1.0;

    final icon = CircleAvatar(
      radius: compact ? 16 : 20,
      child: Icon(item.icon, size: compact ? 18 : 24),
    );

    final label = Text(
      item.label,
      maxLines: compact ? 2 : 1,
      overflow: TextOverflow.ellipsis,
      textAlign: compact ? TextAlign.center : TextAlign.start,
      style: TextStyle(
        fontWeight: FontWeight.w900,
        fontSize: compact ? 11 : 14,
      ),
    );

    return Material(
      color: background,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => onOpen(item.key),
        child: Container(
          padding: EdgeInsets.all(compact ? 8 : 14),
          decoration: BoxDecoration(
            border: Border.all(
              color: borderColor,
              width: borderWidth,
            ),
            borderRadius: BorderRadius.circular(20),
          ),
          child: compact
              ? Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    icon,
                    const SizedBox(height: 6),
                    label,
                    if (isProfessional) ...[
                      const SizedBox(height: 4),
                      const _ProfessionalAccessMark(),
                    ],
                  ],
                )
              : Row(
                  children: [
                    icon,
                    const SizedBox(width: 10),
                    Expanded(child: label),
                    if (isProfessional) ...[
                      const _ProfessionalAccessMark(),
                      const SizedBox(width: 4),
                    ],
                    const Icon(Icons.chevron_right),
                  ],
                ),
        ),
      ),
    );
  }
}

enum _HomeActionAccess {
  general,
  subAdmin,
  admin,
  professional,
}

class _HomeAction {
  const _HomeAction(
    this.key,
    this.label,
    this.icon, {
    this.access = _HomeActionAccess.general,
  });

  final String key;
  final String label;
  final IconData icon;
  final _HomeActionAccess access;
}

class _ProfessionalAccessMark extends StatelessWidget {
  const _ProfessionalAccessMark();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: 18,
      height: 18,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Icon(Icons.circle_outlined, size: 18, color: Colors.black),
          Icon(Icons.circle_outlined, size: 11, color: Colors.black),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w900,
          ),
    );
  }
}
