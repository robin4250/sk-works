import 'package:flutter/material.dart';

enum PersonalVaultAction { preview, save, print }

class PersonalVaultEntry {
  const PersonalVaultEntry({required this.id, required this.label,
    required this.sourceCompanyLabel, required this.periodLabel});
  final String id, label, sourceCompanyLabel, periodLabel;
}

/// Read-only candidate page. The supplied gateway must authenticate every list
/// and action and return only completed own PDFs; it must not trust this page.
class PersonalVaultPage extends StatefulWidget {
  const PersonalVaultPage({super.key, required this.loadMine,
    required this.openOwnPdf});
  final Future<List<PersonalVaultEntry>> Function() loadMine;
  final Future<void> Function(PersonalVaultEntry, PersonalVaultAction) openOwnPdf;
  @override
  State<PersonalVaultPage> createState() => _PersonalVaultPageState();
}

class _PersonalVaultPageState extends State<PersonalVaultPage> {
  late Future<List<PersonalVaultEntry>> _entries;
  String? _busyId;
  @override
  void initState() { super.initState(); _entries = widget.loadMine(); }
  Future<void> _open(PersonalVaultEntry entry, PersonalVaultAction action) async {
    if (_busyId != null) { return; }
    setState(() => _busyId = entry.id);
    try {
      await widget.openOwnPdf(entry, action);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('書類を開けませんでした。通信とログイン状態を確認して再試行してください。')));
      }
    } finally {
      if (mounted) { setState(() => _busyId = null); }
    }
  }
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('書類保管倉庫')),
    body: FutureBuilder<List<PersonalVaultEntry>>(
      future: _entries,
      builder: (context, state) {
        if (state.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (state.hasError) {
          return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('書類一覧を確認できませんでした。'),
            TextButton(onPressed: () => setState(() { _entries = widget.loadMine(); }),
              child: const Text('再読み込み')),
          ]));
        }
        final entries = state.data ?? const [];
        if (entries.isEmpty) { return const Center(child: Text('保管済みの本人書類はありません。')); }
        return ListView(children: [
          const Padding(padding: EdgeInsets.all(16),child: Text(
            '本人の出勤表・給与明細です。元の会社の正式記録は元の会社に残ります。')),
          for (final entry in entries) Card(child: ListTile(
            title: Text(entry.label),
            subtitle: Text('${entry.periodLabel}\n${entry.sourceCompanyLabel}'),
            isThreeLine: true,
            onTap: _busyId == null ? () => _open(entry, PersonalVaultAction.preview) : null,
            trailing: _busyId == entry.id ? const SizedBox(width: 24,height: 24,
              child: CircularProgressIndicator()) : PopupMenuButton<PersonalVaultAction>(
                enabled: _busyId == null,
                tooltip: '閲覧・保存・印刷',
                onSelected: (action) => _open(entry, action),
                itemBuilder: (_) => const [
                  PopupMenuItem(value: PersonalVaultAction.preview, child: Text('閲覧')),
                  PopupMenuItem(value: PersonalVaultAction.save, child: Text('端末に保存')),
                  PopupMenuItem(value: PersonalVaultAction.print, child: Text('印刷')),
                ]),
          )),
        ]);
      },
    ),
  );
}
