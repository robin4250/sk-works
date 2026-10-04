import 'dart:io';

import 'package:flutter/material.dart';

import '../attendance/attendance_verification_repository.dart';
import '../../international/language_controller.dart';
import 'home_attention_repository.dart';
import 'home_appearance.dart';
import 'home_membership_repository.dart';

enum HomeShortcutAccess { general, subAdmin, viewer, admin }

class HomeShortcut {
  const HomeShortcut(
    this.key,
    this.label,
    this.icon, {
    this.twoLineLabel,
    this.access = HomeShortcutAccess.general,
  });

  final String key;
  final String label;
  final String? twoLineLabel;
  final IconData icon;
  final HomeShortcutAccess access;
}

class FriendlyHomeContent extends StatelessWidget {
  const FriendlyHomeContent({
    super.key,
    required this.identity,
    required this.requiredDocumentAttention,
    required this.moduleEnabled,
    this.gridColumns = 2,
    this.actionOrder = const <String>[],
    this.visibleHomeKeys = const <String>{},
    this.shortcuts = const <HomeShortcut>[],
    this.showAttendanceReport = true,
    this.showTodayAttendance = true,
    this.attendanceStatus = const HomeAttendanceStatus(),
    this.appearance = const HomeAppearance(),
    this.contentTopInset = 10,
    required this.onOpen,
    required this.onRefresh,
    this.onReorderAction,
  });

  final HomeIdentity identity;
  final RequiredDocumentAttention requiredDocumentAttention;
  final bool Function(String key) moduleEnabled;
  final int gridColumns;
  final List<String> actionOrder;
  final Set<String> visibleHomeKeys;
  final List<HomeShortcut> shortcuts;
  final bool showAttendanceReport;
  final bool showTodayAttendance;
  final HomeAttendanceStatus attendanceStatus;
  final HomeAppearance appearance;
  final double contentTopInset;
  final Future<void> Function(String key) onOpen;
  final Future<void> Function() onRefresh;
  final Future<void> Function(String draggedKey, String targetKey)?
      onReorderAction;

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
            padding: EdgeInsets.fromLTRB(16, contentTopInset, 16, 100),
            children: [
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
              const SizedBox(height: 14),
              _OrderedHomeContent(
                identity: identity,
                moduleEnabled: moduleEnabled,
                gridColumns: gridColumns,
                actionOrder: actionOrder,
                visibleHomeKeys: visibleHomeKeys,
                shortcuts: shortcuts,
                showAttendanceReport: showAttendanceReport,
                showTodayAttendance: showTodayAttendance,
                attendanceStatus: attendanceStatus,
                appearance: appearance,
                onOpen: onOpen,
                onReorderAction: onReorderAction,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _RequiredDocumentAttentionCard extends StatefulWidget {
  const _RequiredDocumentAttentionCard({
    required this.attention,
    required this.onOpen,
  });

  final RequiredDocumentAttention attention;
  final Future<void> Function(String key) onOpen;

  @override
  State<_RequiredDocumentAttentionCard> createState() =>
      _RequiredDocumentAttentionCardState();
}

class _RequiredDocumentAttentionCardState
    extends State<_RequiredDocumentAttentionCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
    )..repeat(reverse: true);
    _pulse = Tween<double>(begin: 0.45, end: 1).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return FadeTransition(
      opacity: _pulse,
      child: Card(
        margin: EdgeInsets.zero,
        color: scheme.surface,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: scheme.primary, width: 1.5),
          borderRadius: BorderRadius.circular(16),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => widget.onOpen(
            widget.attention.paidLeaveApprovalCount > 0
                ? 'approvals'
                : 'documents',
          ),
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
                        Expanded(
                          child: Text(
                            SkoLanguageController.tr('要対応'),
                            style: const TextStyle(fontWeight: FontWeight.w900),
                          ),
                        ),
                        Text(
                          '${SkoLanguageController.tr('未対応')} ${widget.attention.unresolvedCount}${SkoLanguageController.isEnglish ? '' : '件'}',
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
      ),
    );
  }
}

class _PersonalAttendanceCard extends StatelessWidget {
  const _PersonalAttendanceCard({
    required this.status,
    required this.vehicleRoutesEnabled,
    required this.buttonOpacity,
    required this.onOpen,
  });

  final HomeAttendanceStatus status;
  final bool vehicleRoutesEnabled;
  final double buttonOpacity;
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
                    SkoLanguageController.tr('本日の勤怠報告'),
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
            if (status.verificationMode == 'gps_auto' &&
                status.gpsTime?.trim().isNotEmpty == true) ...[
              const SizedBox(height: 3),
              Text(
                'GPS自動出勤：${_weekdayLabel(status.gpsWeekdays)} '
                '${_shortTime(status.gpsTime!)}',
                style: TextStyle(
                  color: colors.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
            ],
            if (status.siteName?.trim().isNotEmpty == true) ...[
              const SizedBox(height: 3),
              InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => onOpen('workplace_select'),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '選択中の現場：${status.siteName}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      const Icon(Icons.chevron_right, size: 18),
                    ],
                  ),
                ),
              ),
            ],
            if (vehicleRoutesEnabled &&
                status.selectedVehicleName?.trim().isNotEmpty == true) ...[
              const SizedBox(height: 3),
              InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => onOpen('attendance_method_vehicle'),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '選択中の車両：${status.selectedVehicleName}',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      const Icon(Icons.chevron_right, size: 18),
                    ],
                  ),
                ),
              ),
            ],
            if (vehicleRoutesEnabled &&
                status.selectedRouteName?.trim().isNotEmpty == true) ...[
              const SizedBox(height: 3),
              InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => onOpen('workplace_select'),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '選択中のルート：${status.selectedRouteName}',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      const Icon(Icons.chevron_right, size: 18),
                    ],
                  ),
                ),
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
            Opacity(
              opacity: buttonOpacity,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  OutlinedButton.icon(
                    onPressed: () => onOpen('workplace_select'),
                    icon: const Icon(Icons.place_outlined),
                    label: Text(SkoLanguageController.tr('現場の選択（1現場／複数現場）')),
                  ),
                  const SizedBox(height: 9),
                  OutlinedButton.icon(
                    onPressed: () => onOpen('attendance_method_vehicle'),
                    icon: const Icon(Icons.tune_outlined),
                    label: Text(SkoLanguageController.tr('出勤方法と車両を選択')),
                  ),
                  const SizedBox(height: 9),
                  Row(
                    children: [
                      Expanded(
                        child: isWorking || isFinished
                            ? OutlinedButton.icon(
                                onPressed: () => onOpen('clock_in'),
                                icon: const Icon(Icons.login),
                                label: Text(SkoLanguageController.tr('出勤')),
                              )
                            : FilledButton.icon(
                                onPressed: () => onOpen('clock_in'),
                                icon: const Icon(Icons.login),
                                label: Text(SkoLanguageController.tr('出勤')),
                              ),
                      ),
                      const SizedBox(width: 9),
                      Expanded(
                        child: isWorking
                            ? FilledButton.icon(
                                onPressed: () => onOpen('clock_out'),
                                icon: const Icon(Icons.logout),
                                label: Text(SkoLanguageController.tr('退勤')),
                              )
                            : OutlinedButton.icon(
                                onPressed: () => onOpen('clock_out'),
                                icon: const Icon(Icons.logout),
                                label: Text(SkoLanguageController.tr('退勤')),
                              ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _weekdayLabel(List<int> days) {
    const names = <int, String>{
      1: '月',
      2: '火',
      3: '水',
      4: '木',
      5: '金',
      6: '土',
      7: '日',
    };
    return days.map((day) => names[day] ?? '').where((v) => v.isNotEmpty).join('・');
  }

  String _shortTime(String value) {
    final parts = value.split(':');
    if (parts.length < 2) return value;
    return '${parts[0]}:${parts[1]}';
  }

  String _time(DateTime? value) {
    if (value == null) return '--:--';
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(value.hour)}:${two(value.minute)}';
  }
}


class _OrderedHomeContent extends StatelessWidget {
  const _OrderedHomeContent({
    required this.identity,
    required this.moduleEnabled,
    required this.gridColumns,
    required this.actionOrder,
    required this.visibleHomeKeys,
    required this.shortcuts,
    required this.showAttendanceReport,
    required this.showTodayAttendance,
    required this.attendanceStatus,
    required this.appearance,
    required this.onOpen,
    required this.onReorderAction,
  });

  final HomeIdentity identity;
  final bool Function(String key) moduleEnabled;
  final int gridColumns;
  final List<String> actionOrder;
  final Set<String> visibleHomeKeys;
  final List<HomeShortcut> shortcuts;
  final bool showAttendanceReport;
  final bool showTodayAttendance;
  final HomeAttendanceStatus attendanceStatus;
  final HomeAppearance appearance;
  final Future<void> Function(String key) onOpen;
  final Future<void> Function(String draggedKey, String targetKey)?
      onReorderAction;

  @override
  Widget build(BuildContext context) {
    final rank = <String, int>{
      for (var i = 0; i < actionOrder.length; i++) actionOrder[i]: i,
    };
    final keys = <String>[
      if (moduleEnabled('attendance') &&
          showAttendanceReport &&
          visibleHomeKeys.contains('attendance_verify'))
        'attendance_verify',
      if (moduleEnabled('attendance') &&
          showTodayAttendance &&
          visibleHomeKeys.contains('attendance_today'))
        'attendance_today',
      for (final shortcut in shortcuts)
        if (visibleHomeKeys.contains(shortcut.key) &&
            shortcut.key != 'attendance_verify' &&
            shortcut.key != 'attendance_today')
          shortcut.key,
    ];
    final fallbackRank = <String, int>{
      for (var i = 0; i < keys.length; i++) keys[i]: i,
    };
    keys.sort((a, b) {
      final ai = rank[a] ?? 100000;
      final bi = rank[b] ?? 100000;
      if (ai != bi) return ai.compareTo(bi);
      return (fallbackRank[a] ?? 0).compareTo(fallbackRank[b] ?? 0);
    });

    final shortcutByKey = <String, HomeShortcut>{
      for (final shortcut in shortcuts) shortcut.key: shortcut,
    };
    final children = <Widget>[];
    final pending = <_HomeAction>[];

    void flushGrid() {
      if (pending.isEmpty) return;
      children.add(
        _ActionGrid(
          items: List<_HomeAction>.from(pending),
          columns: gridColumns,
          actionOrder: actionOrder,
          opacity: appearance.buttonOpacity,
          onOpen: onOpen,
          onReorderAction: onReorderAction,
        ),
      );
      children.add(const SizedBox(height: 12));
      pending.clear();
    }

    for (final key in keys) {
      if (key == 'attendance_verify') {
        flushGrid();
        children.add(
          _DraggableHomeCard(
            keyName: 'attendance_verify',
            onReorderAction: onReorderAction,
            child: Opacity(
              opacity: appearance.cardOpacity,
              child: _PersonalAttendanceCard(
                status: attendanceStatus,
                vehicleRoutesEnabled: moduleEnabled('vehicle_routes'),
                buttonOpacity: appearance.cardButtonOpacity,
                onOpen: onOpen,
              ),
            ),
          ),
        );
        children.add(const SizedBox(height: 12));
        continue;
      }
      if (key == 'attendance_today') {
        flushGrid();
        children.add(
          _DraggableHomeCard(
            keyName: 'attendance_today',
            onReorderAction: onReorderAction,
            child: Opacity(
              opacity: appearance.cardOpacity,
              child: _TodayAttendanceHomeCard(
                buttonOpacity: appearance.cardButtonOpacity,
                onOpen: onOpen,
              ),
            ),
          ),
        );
        children.add(const SizedBox(height: 12));
        continue;
      }

      final shortcut = shortcutByKey[key];
      if (shortcut != null) {
        pending.add(
          _HomeAction(
            shortcut.key,
            shortcut.label,
            shortcut.icon,
            twoLineLabel: shortcut.twoLineLabel,
            access: shortcut.access,
          ),
        );
      }
    }
    flushGrid();

    if (children.isNotEmpty && children.last is SizedBox) {
      children.removeLast();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }
}


class _DraggableHomeCard extends StatelessWidget {
  const _DraggableHomeCard({
    required this.keyName,
    required this.child,
    required this.onReorderAction,
  });

  final String keyName;
  final Widget child;
  final Future<void> Function(String draggedKey, String targetKey)?
      onReorderAction;

  @override
  Widget build(BuildContext context) {
    final reorder = onReorderAction;
    if (reorder == null) return child;

    return DragTarget<String>(
      onWillAcceptWithDetails: (details) => details.data != keyName,
      onAcceptWithDetails: (details) {
        reorder(details.data, keyName);
      },
      builder: (context, candidateData, rejectedData) {
        final highlighted = candidateData.isNotEmpty;
        return AnimatedScale(
          scale: highlighted ? 1.015 : 1,
          duration: const Duration(milliseconds: 120),
          child: LongPressDraggable<String>(
            data: keyName,
            delay: const Duration(milliseconds: 320),
            feedback: SizedBox(
              width: MediaQuery.sizeOf(context).width - 32,
              child: Material(
                color: Colors.transparent,
                child: child,
              ),
            ),
            childWhenDragging: Opacity(
              opacity: 0.35,
              child: child,
            ),
            child: child,
          ),
        );
      },
    );
  }
}

class _TodayAttendanceHomeCard extends StatelessWidget {
  const _TodayAttendanceHomeCard({
    required this.buttonOpacity,
    required this.onOpen,
  });

  final double buttonOpacity;
  final Future<void> Function(String key) onOpen;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              SkoLanguageController.tr('本日の出勤'),
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
            ),
            const SizedBox(height: 6),
            Text(SkoLanguageController.isEnglish ? 'View attendance counts by site, separated between your company and partner companies.' : '自社と下請けを分けて、現場ごとの出勤人数を確認できます。'),
            const SizedBox(height: 12),
            Opacity(
              opacity: buttonOpacity,
              child: FilledButton.icon(
                onPressed: () => onOpen('attendance_today'),
                icon: const Icon(Icons.groups_outlined),
                label: Text(SkoLanguageController.tr('出勤状況を確認')),
              ),
            ),
          ],
        ),
      ),
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
    required this.onReorderAction,
  });

  final List<_HomeAction> items;
  final int columns;
  final List<String> actionOrder;
  final double opacity;
  final Future<void> Function(String key) onOpen;
  final Future<void> Function(String draggedKey, String targetKey)?
      onReorderAction;

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
      3 => 1.12,
      _ => 1.05,
    };

    return Opacity(
      opacity: opacity,
      child: GridView.count(
      crossAxisCount: columnCount,
      shrinkWrap: true,
      primary: false,
      padding: EdgeInsets.zero,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: ratio,
      children: [
        for (final item in ordered)
          _HomeActionTile(
            item: item,
            compact: columnCount >= 3,
            fourColumns: columnCount == 4,
            onOpen: onOpen,
            onReorderAction: onReorderAction,
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
    required this.fourColumns,
    required this.onOpen,
    required this.onReorderAction,
  });

  final _HomeAction item;
  final bool compact;
  final bool fourColumns;
  final Future<void> Function(String key) onOpen;
  final Future<void> Function(String draggedKey, String targetKey)?
      onReorderAction;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
      final isSubAdmin = item.access == HomeShortcutAccess.subAdmin;
    final isViewer = item.access == HomeShortcutAccess.viewer;
    final isAdmin = item.access == HomeShortcutAccess.admin;
    final background = scheme.surfaceContainerLowest;
    final borderColor = scheme.primary;
    final borderWidth = isAdmin ? 4.0 : (isSubAdmin || isViewer ? 1.8 : 0.0);

    final icon = CircleAvatar(
      radius: fourColumns ? 12 : (compact ? 16 : 20),
      child: Icon(item.icon, size: fourColumns ? 14 : (compact ? 18 : 24)),
    );

    final labelStyle = TextStyle(
      fontWeight: FontWeight.w900,
      fontSize: fourColumns ? 9.5 : (compact ? 11 : 14),
      height: 1.05,
    );

    Widget label = LayoutBuilder(
      builder: (context, constraints) {
        final painter = TextPainter(
          text: TextSpan(text: item.label, style: labelStyle),
          maxLines: 1,
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: double.infinity);
        final needsTwoLines = painter.width > constraints.maxWidth;
        final display = needsTwoLines &&
                item.twoLineLabel != null &&
                item.twoLineLabel!.trim().isNotEmpty
            ? item.twoLineLabel!
            : item.label;
        return Text(
          display,
          maxLines: needsTwoLines ? 2 : 1,
          overflow: TextOverflow.ellipsis,
          textAlign: fourColumns
              ? TextAlign.center
              : (compact ? TextAlign.center : TextAlign.start),
          style: labelStyle,
        );
      },
    );

    Widget content() => fourColumns
              ? Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    icon,
                    const SizedBox(height: 4),
                    Flexible(child: label),

                  ],
                )
              : compact
                  ? Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        icon,
                        const SizedBox(height: 6),
                        label,

                      ],
                    )
                  : Row(
                  children: [
                    icon,
                    const SizedBox(width: 10),
                    Expanded(child: label),

                    const Icon(Icons.chevron_right),
                  ],
                );

    Widget tile({bool dragging = false}) {
      Widget core = Material(
        color: background.withValues(alpha: dragging ? 0.88 : 1),
        elevation: dragging ? 8 : 0,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: dragging ? null : () => onOpen(item.key),
          child: Container(
            padding: EdgeInsets.all(compact ? 8 : 14),
            decoration: BoxDecoration(
              border: borderWidth > 0
                  ? Border.all(color: borderColor, width: borderWidth)
                  : null,
              borderRadius: BorderRadius.circular(20),
            ),
            child: content(),
          ),
        ),
      );

      if (isViewer) {
        core = Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            border: Border.all(color: borderColor, width: 1.8),
            borderRadius: BorderRadius.circular(23),
          ),
          child: core,
        );
      }
      return core;
    }

    final reorder = onReorderAction;
    if (reorder == null) return tile();

    return DragTarget<String>(
      onWillAcceptWithDetails: (details) => details.data != item.key,
      onAcceptWithDetails: (details) {
        reorder(details.data, item.key);
      },
      builder: (context, candidateData, rejectedData) {
        final highlighted = candidateData.isNotEmpty;
        return AnimatedScale(
          scale: highlighted ? 1.04 : 1,
          duration: const Duration(milliseconds: 120),
          child: LongPressDraggable<String>(
            data: item.key,
            delay: const Duration(milliseconds: 320),
            feedback: SizedBox(
              width: fourColumns ? 92 : (compact ? 120 : 220),
              child: Material(
                color: Colors.transparent,
                child: tile(dragging: true),
              ),
            ),
            childWhenDragging: Opacity(
              opacity: 0.35,
              child: tile(),
            ),
            child: tile(),
          ),
        );
      },
    );
  }
}

class _HomeAction {
  const _HomeAction(
    this.key,
    this.label,
    this.icon, {
    this.twoLineLabel,
    this.access = HomeShortcutAccess.general,
  });

  final String key;
  final String label;
  final String? twoLineLabel;
  final IconData icon;
  final HomeShortcutAccess access;
}


