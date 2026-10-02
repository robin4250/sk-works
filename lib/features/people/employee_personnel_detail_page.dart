import 'package:flutter/material.dart';

import 'employee_personnel_edit_page.dart';
import 'employee_personnel_print_page.dart';
import 'people_page.dart';
import 'personnel_bundle_send_page.dart';
import 'phone_display.dart';

class EmployeePersonnelDetailPage extends StatelessWidget {
  const EmployeePersonnelDetailPage({
    super.key,
    required this.record,
    required this.allEmployees,
    required this.companyName,
  });

  final PersonRecord record;
  final List<PersonRecord> allEmployees;
  final String companyName;

  Future<bool?> _chooseScope(BuildContext context, String action) {
    return showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.groups_2_outlined),
              title: const Text('社員一覧'),
              subtitle: Text('社員一覧を$action'),
              onTap: () => Navigator.pop(sheetContext, true),
            ),
            ListTile(
              leading: const Icon(Icons.person_outline),
              title: const Text('個別'),
              subtitle: Text('${record.name}さんだけを$action'),
              onTap: () => Navigator.pop(sheetContext, false),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _send(BuildContext context) async {
    final all = await _chooseScope(context, '送信');
    if (all == null || !context.mounted) return;
    final targets = all ? allEmployees : [record];
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => PersonnelBundleSendPage(
          workerIds: targets.map((item) => item.id).toSet(),
        ),
      ),
    );
  }

  Future<void> _print(BuildContext context) async {
    final all = await _chooseScope(context, '印刷');
    if (all == null || !context.mounted) return;
    final targets = all ? allEmployees : [record];
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => EmployeePersonnelPrintPage(
          companyName: companyName,
          records: targets,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final rows = <(String, String)>[
      ('名前', record.name),
      ('区分', record.kind.label),
      ('血液型', record.bloodType),
      ('職種', record.role),
      ('電話番号', domesticPhoneDisplay(record.phone)),
      ('住所', record.address),
      ('緊急連絡先氏名', record.emergencyName),
      ('続柄', record.emergencyRelation),
      ('緊急連絡先電話番号', domesticPhoneDisplay(record.emergencyPhone)),
      ('緊急連絡先住所', record.emergencyAddress),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          '社員情報',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            for (final row in rows)
              Card(
                child: ListTile(
                  title: Text(row.$1),
                  subtitle: Text(
                    row.$2.trim().isEmpty ? '未登録' : row.$2,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ),
            const SizedBox(height: 18),
            const Text(
              '家族・扶養情報',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 6),
            const Text(
              '社員一覧には表示しません。社会保険など本人に関する手続きで使う個別情報です。',
            ),
            const SizedBox(height: 8),
            Card(
              child: ListTile(
                title: const Text('家族構成'),
                subtitle: Text(
                  record.familyComposition.trim().isEmpty
                      ? '未登録'
                      : record.familyComposition,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ),
            if (record.familyMembers.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('配偶者・子供・扶養家族は未登録です'),
                ),
              )
            else
              for (final member in record.familyMembers)
                Card(
                  child: ListTile(
                    leading: const CircleAvatar(
                      child: Icon(Icons.family_restroom_outlined),
                    ),
                    title: Text(
                      member.name + '（' + member.relation + '）',
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    subtitle: Text(
                      [
                        if (member.birthDate != null)
                          '誕生日 ' +
                              member.birthDate!.year.toString() +
                              '/' +
                              member.birthDate!.month.toString().padLeft(2, '0') +
                              '/' +
                              member.birthDate!.day.toString().padLeft(2, '0'),
                        if (member.ageOn() != null)
                          '現在 ' + member.ageOn().toString() + '歳',
                        member.isDependent ? '扶養対象' : '扶養対象外',
                      ].join(' / '),
                    ),
                  ),
                ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => Navigator.of(context).push<bool>(
                MaterialPageRoute(
                  builder: (_) => EmployeePersonnelEditPage(record: record),
                ),
              ),
              icon: const Icon(Icons.edit_outlined),
              label: const Text('編集'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => _send(context),
                    icon: const Icon(Icons.send_outlined),
                    label: const Text('送信'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _print(context),
                    icon: const Icon(Icons.print_outlined),
                    label: const Text('印刷'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                    ),
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
