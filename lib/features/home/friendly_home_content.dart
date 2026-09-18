import 'package:flutter/material.dart';

class FriendlyHomeContent extends StatelessWidget {
  const FriendlyHomeContent({
    super.key,
    required this.role,
    required this.moduleEnabled,
    required this.onOpen,
    required this.onRefresh,
  });

  final String role;
  final bool Function(String key) moduleEnabled;
  final Future<void> Function(String key) onOpen;
  final Future<void> Function() onRefresh;

  bool get _isAdmin =>
      role == 'owner' || role == 'admin' || role == 'manager';

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 120),
        children: [
          _WelcomeCard(isAdmin: _isAdmin),
          const SizedBox(height: 14),
          if (_isAdmin)
            _AdminNextAction(
              attendanceEnabled: moduleEnabled('attendance'),
              onOpen: onOpen,
            )
          else
            _WorkerNextAction(
              attendanceEnabled: moduleEnabled('attendance'),
              onOpen: onOpen,
            ),
          const SizedBox(height: 20),
          _SectionTitle(_isAdmin ? 'よく使う管理' : '今日使うもの'),
          const SizedBox(height: 10),
          _QuickGrid(
            isAdmin: _isAdmin,
            moduleEnabled: moduleEnabled,
            onOpen: onOpen,
          ),
          const SizedBox(height: 20),
          if (moduleEnabled('chat')) ...[
            const _SectionTitle('連絡'),
            const SizedBox(height: 10),
            _LargeActionCard(
              icon: Icons.chat_bubble_outline,
              title: 'チャット',
              subtitle: 'LINEのような感覚で、現場や会社の連絡を見る',
              buttonLabel: 'チャットを開く',
              onTap: () => onOpen('chat'),
            ),
            const SizedBox(height: 20),
          ],
          const _SectionTitle('次にやることを迷わないために'),
          const SizedBox(height: 10),
          _SupportFlowCard(isAdmin: _isAdmin),
          const SizedBox(height: 20),
          if (_isAdmin) ...[
            const _SectionTitle('管理・準備'),
            const SizedBox(height: 10),
            _ManagementList(
              moduleEnabled: moduleEnabled,
              onOpen: onOpen,
            ),
          ] else ...[
            const _SectionTitle('自分の情報'),
            const SizedBox(height: 10),
            _WorkerInfoList(
              moduleEnabled: moduleEnabled,
              onOpen: onOpen,
            ),
          ],
        ],
      ),
    );
  }
}

class _WelcomeCard extends StatelessWidget {
  const _WelcomeCard({required this.isAdmin});

  final bool isAdmin;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 26,
            backgroundColor: colors.primaryContainer,
            child: Icon(
              isAdmin ? Icons.dashboard_outlined : Icons.person_outline,
              color: colors.onPrimaryContainer,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isAdmin ? '管理ホーム' : 'マイページ',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  isAdmin
                      ? '今日の確認と、よく使う管理をここにまとめました'
                      : '今日使うものを、迷わない順番でまとめました',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AdminNextAction extends StatelessWidget {
  const _AdminNextAction({
    required this.attendanceEnabled,
    required this.onOpen,
  });

  final bool attendanceEnabled;
  final Future<void> Function(String key) onOpen;

  @override
  Widget build(BuildContext context) {
    return _GuideCard(
      eyebrow: 'SKOサポート',
      title: 'まず今日の状況を確認',
      body: attendanceEnabled
          ? '出勤状況を確認してから、人員・現場・請求へ進むとスムーズです。'
          : '人員や現場の確認から始めるとスムーズです。',
      actionLabel: attendanceEnabled ? '出勤状況を見る' : '人員を見る',
      icon: Icons.auto_awesome_outlined,
      onTap: () => onOpen(attendanceEnabled ? 'attendance' : 'people'),
    );
  }
}

class _WorkerNextAction extends StatelessWidget {
  const _WorkerNextAction({
    required this.attendanceEnabled,
    required this.onOpen,
  });

  final bool attendanceEnabled;
  final Future<void> Function(String key) onOpen;

  @override
  Widget build(BuildContext context) {
    return _GuideCard(
      eyebrow: 'SKOサポート',
      title: attendanceEnabled ? '出勤・退勤を確認しましょう' : '今日の連絡を確認しましょう',
      body: attendanceEnabled
          ? '会社で設定された方法に合わせて、手動・位置情報・写真付きで確認できます。'
          : '必要な連絡や自分の登録情報をここから確認できます。',
      actionLabel: attendanceEnabled ? '出勤・退勤へ' : 'チャットへ',
      icon: Icons.waving_hand_outlined,
      onTap: () => onOpen(attendanceEnabled ? 'attendance_verify' : 'chat'),
    );
  }
}

class _GuideCard extends StatelessWidget {
  const _GuideCard({
    required this.eyebrow,
    required this.title,
    required this.body,
    required this.actionLabel,
    required this.icon,
    required this.onTap,
  });

  final String eyebrow;
  final String title;
  final String body;
  final String actionLabel;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colors.primaryContainer.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20),
              const SizedBox(width: 8),
              Text(
                eyebrow,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            title,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
          ),
          const SizedBox(height: 6),
          Text(body),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: onTap,
            icon: const Icon(Icons.arrow_forward),
            label: Text(actionLabel),
          ),
        ],
      ),
    );
  }
}

class _QuickGrid extends StatelessWidget {
  const _QuickGrid({
    required this.isAdmin,
    required this.moduleEnabled,
    required this.onOpen,
  });

  final bool isAdmin;
  final bool Function(String key) moduleEnabled;
  final Future<void> Function(String key) onOpen;

  @override
  Widget build(BuildContext context) {
    final items = isAdmin
        ? <_QuickItem>[
            const _QuickItem('people', '人員', Icons.groups_outlined),
            const _QuickItem('sites', '現場', Icons.business_outlined),
            const _QuickItem('attendance', '出勤表', Icons.calendar_month_outlined),
            const _QuickItem('invoices', '請求', Icons.receipt_long_outlined),
          ]
        : <_QuickItem>[
            const _QuickItem('attendance_verify', '出勤・退勤', Icons.how_to_reg_outlined),
            const _QuickItem('attendance', '出勤表', Icons.calendar_month_outlined),
            const _QuickItem('qualifications', '資格', Icons.badge_outlined),
            const _QuickItem('documents', '必要書類', Icons.fact_check_outlined),
          ];

    final visible = items.where((item) {
      if (item.key == 'attendance_verify') {
        return moduleEnabled('attendance');
      }
      return moduleEnabled(item.key);
    }).toList();

    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 1.55,
      children: [
        for (final item in visible)
          _QuickButton(
            item: item,
            onTap: () => onOpen(item.key),
          ),
      ],
    );
  }
}

class _QuickItem {
  const _QuickItem(this.key, this.label, this.icon);

  final String key;
  final String label;
  final IconData icon;
}

class _QuickButton extends StatelessWidget {
  const _QuickButton({required this.item, required this.onTap});

  final _QuickItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surfaceContainerLowest,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            border: Border.all(color: colors.outlineVariant),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: colors.secondaryContainer,
                child: Icon(item.icon, color: colors.onSecondaryContainer),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  item.label,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}

class _LargeActionCard extends StatelessWidget {
  const _LargeActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.buttonLabel,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String buttonLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            CircleAvatar(
              radius: 24,
              child: Icon(icon),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 17,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(subtitle),
                ],
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: onTap,
              child: Text(buttonLabel),
            ),
          ],
        ),
      ),
    );
  }
}

class _SupportFlowCard extends StatelessWidget {
  const _SupportFlowCard({required this.isAdmin});

  final bool isAdmin;

  @override
  Widget build(BuildContext context) {
    final steps = isAdmin
        ? const [
            ('1', '出勤状況を確認'),
            ('2', '人員・現場を確認'),
            ('3', '必要なら請求や書類へ'),
          ]
        : const [
            ('1', '出勤・退勤を記録'),
            ('2', '出勤表を確認'),
            ('3', '給与・書類など次の確認へ'),
          ];

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          children: [
            for (var i = 0; i < steps.length; i++) ...[
              Row(
                children: [
                  CircleAvatar(
                    radius: 16,
                    child: Text(steps[i].$1),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      steps[i].$2,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
              if (i != steps.length - 1)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 7),
                  child: Row(
                    children: [
                      SizedBox(width: 15),
                      Icon(Icons.keyboard_arrow_down, size: 18),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ManagementList extends StatelessWidget {
  const _ManagementList({
    required this.moduleEnabled,
    required this.onOpen,
  });

  final bool Function(String key) moduleEnabled;
  final Future<void> Function(String key) onOpen;

  @override
  Widget build(BuildContext context) {
    final items = <_ListItem>[
      if (moduleEnabled('documents'))
        const _ListItem('documents', '必要書類チェック', Icons.fact_check_outlined),
      if (moduleEnabled('qualifications'))
        const _ListItem('qualification_certificates', '資格証写真', Icons.document_scanner_outlined),
      if (moduleEnabled('line_bridge'))
        const _ListItem('today_line', '本日のLINE出勤候補', Icons.today_outlined),
      const _ListItem('rollout', '運用準備チェック', Icons.checklist_rtl_outlined),
      const _ListItem('settings', '設定', Icons.settings_outlined),
    ];
    return _ListCard(items: items, onOpen: onOpen);
  }
}

class _WorkerInfoList extends StatelessWidget {
  const _WorkerInfoList({
    required this.moduleEnabled,
    required this.onOpen,
  });

  final bool Function(String key) moduleEnabled;
  final Future<void> Function(String key) onOpen;

  @override
  Widget build(BuildContext context) {
    final items = <_ListItem>[
      if (moduleEnabled('qualifications'))
        const _ListItem('qualifications', '資格情報', Icons.badge_outlined),
      if (moduleEnabled('documents'))
        const _ListItem('documents', '必要書類', Icons.fact_check_outlined),
      if (moduleEnabled('notes'))
        const _ListItem('notes', 'ノート', Icons.sticky_note_2_outlined),
      if (moduleEnabled('albums'))
        const _ListItem('albums', 'アルバム', Icons.photo_album_outlined),
    ];
    return _ListCard(items: items, onOpen: onOpen);
  }
}

class _ListItem {
  const _ListItem(this.key, this.title, this.icon);

  final String key;
  final String title;
  final IconData icon;
}

class _ListCard extends StatelessWidget {
  const _ListCard({required this.items, required this.onOpen});

  final List<_ListItem> items;
  final Future<void> Function(String key) onOpen;

  @override
  Widget build(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Column(
        children: [
          for (var i = 0; i < items.length; i++) ...[
            ListTile(
              leading: Icon(items[i].icon),
              title: Text(
                items[i].title,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => onOpen(items[i].key),
            ),
            if (i != items.length - 1) const Divider(height: 1),
          ],
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
