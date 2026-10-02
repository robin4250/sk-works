import 'package:flutter/material.dart';

import '../common/japanese_phone.dart';
import 'employee_directory_pdf_service.dart';
import 'people_page.dart';
import 'personnel_bundle_send_page.dart';

class EmployeeDetailPage extends StatelessWidget {
  const EmployeeDetailPage({
    super.key,
    required this.record,
    required this.allEmployees,
    required this.companyName,
  });

  final PersonRecord record;
  final List<PersonRecord> allEmployees;
  final String companyName;

  Future<bool?> _chooseScope(
    BuildContext context, {
    required String title,
  }) {
    return showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 10),
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.table_rows_outlined),
              title: const Text('社員一覧'),
              subtitle: const Text('社員一覧を対象にします'),
              onTap: () => Navigator.pop(context, true),
            ),
            ListTile(
              leading: const Icon(Icons.person_outline),
              title: const Text('個別'),
              subtitle: Text(record.name + 'だけを対象にします'),
              onTap: () => Navigator.pop(context, false),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _send(BuildContext context) async {
    final all = await _chooseScope(
      context,
      title: '送信する対象を選択',
    );
    if (all == null || !context.mounted) return;

    final ids = all
        ? allEmployees.map((item) => item.id).toSet()
        : <String>{record.id};

    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => PersonnelBundleSendPage(workerIds: ids),
      ),
    );
  }

  Future<void> _print(BuildContext context) async {
    final all = await _chooseScope(
      context,
      title: '印刷する対象を選択',
    );
    if (all == null || !context.mounted) return;

    final records = all ? allEmployees : <PersonRecord>[record];
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => EmployeeDirectoryPrintPreviewPage(
          companyName: companyName,
          records: records,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          '社員情報',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        actions: [
          IconButton(
            tooltip: '送信',
            onPressed: () => _send(context),
            icon: const Icon(Icons.send_outlined),
          ),
          IconButton(
            tooltip: '印刷',
            onPressed: () => _print(context),
            icon: const Icon(Icons.print_outlined),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          _row('名前', record.name),
          _row('区分', record.kind.label),
          _row('血液型', record.bloodType),
          _row('職種', record.role),
          _row('電話番号', japaneseDomesticPhone(record.phone)),
          _row('住所', record.address),
          const SizedBox(height: 14),
          const Text(
            '緊急連絡先',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          _row('氏名', record.emergencyName),
          _row('続柄', record.emergencyRelation),
          _row(
            '電話番号',
            japaneseDomesticPhone(record.emergencyPhone),
          ),
          _row('住所', record.emergencyAddress),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => _send(context),
                  icon: const Icon(Icons.send_outlined),
                  label: const Text('送信'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _print(context),
                  icon: const Icon(Icons.print_outlined),
                  label: const Text('印刷'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _row(String label, String value) {
    return Card(
      child: ListTile(
        title: Text(label),
        subtitle: Text(
          value.trim().isEmpty ? '未登録' : value,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
    );
  }
}
