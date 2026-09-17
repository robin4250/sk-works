import 'package:flutter/material.dart';

import '../../domain/qualification.dart';

class QualificationPage extends StatefulWidget {
  const QualificationPage({super.key});

  @override
  State<QualificationPage> createState() => _QualificationPageState();
}

class _QualificationPageState extends State<QualificationPage> {
  final _queryController = TextEditingController();
  String _query = '';
  bool _showExpiringOnly = false;

  static const _masters = [
    QualificationMaster(
      id: 'foreman-safety',
      name: '職長・安全衛生責任者',
      issuer: '安全衛生教育',
    ),
    QualificationMaster(
      id: 'slinging',
      name: '玉掛け技能講習',
      issuer: '登録教習機関',
    ),
    QualificationMaster(
      id: 'aerial-lift',
      name: '高所作業車運転技能講習',
      issuer: '登録教習機関',
    ),
  ];

  static final _held = [
    WorkerQualification(
      workerId: '山田 太郎',
      qualificationId: 'foreman-safety',
      certificateNumber: 'SK-001',
      issueDate: DateTime(2024, 4, 1),
    ),
    WorkerQualification(
      workerId: '佐藤 次郎',
      qualificationId: 'slinging',
      certificateNumber: 'SK-002',
      issueDate: DateTime(2023, 5, 10),
    ),
  ];

  @override
  void dispose() {
    _queryController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final catalog = QualificationCatalog(_masters);
    final now = DateTime.now();
    final filtered = _held.where((item) {
      final master = catalog.findById(item.qualificationId);
      if (master == null) return false;
      final needle = _query.trim().toLowerCase();
      final matchesQuery = needle.isEmpty ||
          master.name.toLowerCase().contains(needle) ||
          item.workerId.toLowerCase().contains(needle) ||
          (item.certificateNumber?.toLowerCase().contains(needle) ?? false);
      final matchesExpiry = !_showExpiringOnly ||
          item.isExpiredOn(now) ||
          item.expiresWithin(now, const Duration(days: 90));
      return matchesQuery && matchesExpiry;
    }).toList(growable: false);

    return Scaffold(
      appBar: AppBar(title: const Text('資格管理')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showPrototypeNotice,
        icon: const Icon(Icons.add_card),
        label: const Text('資格登録'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: TextField(
                controller: _queryController,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: '資格名・保有者・証明書番号で検索',
                ),
                onChanged: (value) => setState(() => _query = value),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  FilterChip(
                    label: const Text('期限切れ・90日以内'),
                    selected: _showExpiringOnly,
                    onSelected: (value) => setState(() => _showExpiringOnly = value),
                  ),
                  const Spacer(),
                  Text('${filtered.length}件'),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: filtered.isEmpty
                  ? const Center(child: Text('該当する資格登録はありません'))
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
                      itemCount: filtered.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final item = filtered[index];
                        final master = catalog.findById(item.qualificationId)!;
                        final status = _expiryLabel(item, now);
                        return Card(
                          child: ListTile(
                            leading: const CircleAvatar(
                              child: Icon(Icons.badge_outlined),
                            ),
                            title: Text(
                              master.name,
                              style: const TextStyle(fontWeight: FontWeight.w700),
                            ),
                            subtitle: Text(
                              [
                                item.workerId,
                                if (item.certificateNumber != null) '証明書 ${item.certificateNumber}',
                                status,
                              ].join(' / '),
                            ),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => _showDetails(master, item, status),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  String _expiryLabel(WorkerQualification item, DateTime now) {
    final expiry = item.expiryDate;
    if (expiry == null) return '期限なし';
    if (item.isExpiredOn(now)) return '期限切れ';
    if (item.expiresWithin(now, const Duration(days: 90))) return '90日以内に期限';
    return '期限 ${expiry.year}/${expiry.month.toString().padLeft(2, '0')}/${expiry.day.toString().padLeft(2, '0')}';
  }

  void _showDetails(
    QualificationMaster master,
    WorkerQualification item,
    String status,
  ) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(master.name, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              Text('保有者: ${item.workerId}'),
              if (master.issuer != null) Text('発行・講習区分: ${master.issuer}'),
              if (item.certificateNumber != null) Text('証明書番号: ${item.certificateNumber}'),
              Text('状態: $status'),
            ],
          ),
        ),
      ),
    );
  }

  void _showPrototypeNotice() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('資格マスターから選択して作業員へ登録するフォームを次段階で接続します'),
      ),
    );
  }
}
