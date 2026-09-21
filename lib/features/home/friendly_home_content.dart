import 'package:flutter/material.dart';

import 'home_attention_repository.dart';
import 'home_membership_repository.dart';

class FriendlyHomeContent extends StatelessWidget {
  const FriendlyHomeContent({
    super.key,
    required this.identity,
    required this.requiredDocumentAttention,
    required this.moduleEnabled,
    required this.onOpen,
    required this.onRefresh,
  });

  final HomeIdentity identity;
  final RequiredDocumentAttention requiredDocumentAttention;
  final bool Function(String key) moduleEnabled;
  final Future<void> Function(String key) onOpen;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 32),
        children: [
          _GreetingCard(identity: identity),
          if (requiredDocumentAttention.hasMissing) ...[
            const SizedBox(height: 12),
            _RequiredDocumentAttentionCard(
              attention: requiredDocumentAttention,
              onOpen: onOpen,
            ),
          ],
          if (moduleEnabled('attendance')) ...[
            const SizedBox(height: 12),
            _PersonalAttendanceCard(onOpen: onOpen),
          ],
          const SizedBox(height: 14),
          if (identity.isAdmin)
            _AdminHome(
              identity: identity,
              moduleEnabled: moduleEnabled,
              onOpen: onOpen,
            )
          else
            _WorkerHome(
              moduleEnabled: moduleEnabled,
              onOpen: onOpen,
            ),
        ],
      ),
    );
  }
}

class _GreetingCard extends StatelessWidget {
  const _GreetingCard({required this.identity});

  final HomeIdentity identity;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              identity.companyName,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'おはようございます、${identity.displayName}さん',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Text(
                    identity.roleLabel,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '${now.year}年${now.month}月${now.day}日',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
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
    final preview = attention.missingNames.take(3).join('・');
    final extra = attention.missingCount > 3
        ? ' ほか${attention.missingCount - 3}件'
        : '';
    final guidance = <String>[
      if (attention.needsLicense) '運転免許証',
      if (attention.needsQualification) '資格証',
    ];

    return Card(
      color: Theme.of(context).colorScheme.errorContainer,
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        leading: const CircleAvatar(
          child: Icon(Icons.priority_high),
        ),
        title: const Text(
          '大事なお知らせ：必要書類が未登録です',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        subtitle: Text(
          [
            '未登録 ${attention.missingCount}件',
            if (preview.isNotEmpty) '$preview$extra',
            if (guidance.isNotEmpty)
              '${guidance.join('・')}の登録も確認してください',
            'すべて登録するとこの通知は自動で消えます',
          ].join('\n'),
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => onOpen('documents'),
      ),
    );
  }
}

class _PersonalAttendanceCard extends StatelessWidget {
  const _PersonalAttendanceCard({required this.onOpen});

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
              '自分の本日の勤務',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
            ),
            const SizedBox(height: 8),
            const Text(
              '一般ユーザー・サブ管理者・管理者の全員が、自分自身の出勤・退勤を登録できます。'
              '位置情報は登録ボタンを押した時だけ取得します。',
            ),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: () => onOpen('footer_sites'),
              icon: const Icon(Icons.business_outlined),
              label: const Text('自分の現場を選ぶ・確認する'),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => onOpen('clock_in'),
                    icon: const Icon(Icons.login),
                    label: const Text('本日の出勤'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: () => onOpen('clock_out'),
                    icon: const Icon(Icons.logout),
                    label: const Text('本日の退勤'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _WorkerHome extends StatelessWidget {
  const _WorkerHome({
    required this.moduleEnabled,
    required this.onOpen,
  });

  final bool Function(String key) moduleEnabled;
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
            const _HomeAction(
              'payroll',
              '給与明細',
              Icons.payments_outlined,
            ),
            const _HomeAction(
              'profile',
              'プロフィール',
              Icons.account_circle_outlined,
            ),
            if (moduleEnabled('sites'))
              const _HomeAction(
                'site_register',
                '現場登録',
                Icons.add_business_outlined,
              ),
            const _HomeAction(
              'settings',
              '設定',
              Icons.settings_outlined,
            ),
            const _HomeAction(
              'help',
              'ヘルプ',
              Icons.help_outline,
            ),
          ],
          onOpen: onOpen,
        ),
        const SizedBox(height: 18),
        Card(
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
      ],
    );
  }
}

class _AdminHome extends StatelessWidget {
  const _AdminHome({
    required this.identity,
    required this.moduleEnabled,
    required this.onOpen,
  });

  final HomeIdentity identity;
  final bool Function(String key) moduleEnabled;
  final Future<void> Function(String key) onOpen;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (moduleEnabled('attendance') &&
            identity.can('can_manage_attendance'))
          Card(
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
                  onPressed: () => onOpen('attendance'),
                  icon: const Icon(Icons.groups_outlined),
                  label: const Text('出勤状況を確認'),
                ),
              ],
            ),
          ),
        ),
        if (moduleEnabled('attendance') &&
            identity.can('can_manage_attendance'))
          const SizedBox(height: 12),
        if (identity.can('can_approve_daily_report_edits')) ...[
          Card(
            child: ListTile(
              leading: const CircleAvatar(
                child: Icon(Icons.approval_outlined),
              ),
              title: const Text(
                '承認待ち',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
              subtitle: const Text('日報の修正申請など、対応が必要なものを確認'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => onOpen('approvals'),
            ),
          ),
          const SizedBox(height: 18),
        ],
        const _SectionTitle('管理'),
        const SizedBox(height: 9),
        _ActionGrid(
          items: [
            if (moduleEnabled('attendance') &&
                identity.can('can_manage_attendance'))
              const _HomeAction(
                'attendance',
                '出勤・人区管理',
                Icons.calendar_month_outlined,
              ),
            if (identity.can('can_manage_people'))
              const _HomeAction(
                'people',
                '人員管理',
                Icons.groups_2_outlined,
              ),
            if (moduleEnabled('invoices') &&
                identity.can('can_view_invoices'))
              const _HomeAction(
                'invoices',
                '請求書',
                Icons.receipt_long_outlined,
              ),
            if (identity.can('can_view_admin_site_data'))
              const _HomeAction(
                'admin_sites',
                '管理者用現場データ',
                Icons.admin_panel_settings_outlined,
              ),
            const _HomeAction(
              'settings',
              '設定',
              Icons.settings_outlined,
            ),
          ],
          onOpen: onOpen,
        ),
        const SizedBox(height: 18),
        Card(
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
      ],
    );
  }
}

class _ActionGrid extends StatelessWidget {
  const _ActionGrid({
    required this.items,
    required this.onOpen,
  });

  final List<_HomeAction> items;
  final Future<void> Function(String key) onOpen;

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 1.55,
      children: [
        for (final item in items)
          Material(
            color: Theme.of(context).colorScheme.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(20),
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () => onOpen(item.key),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  children: [
                    CircleAvatar(child: Icon(item.icon)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        item.label,
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    const Icon(Icons.chevron_right),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _HomeAction {
  const _HomeAction(this.key, this.label, this.icon);

  final String key;
  final String label;
  final IconData icon;
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
