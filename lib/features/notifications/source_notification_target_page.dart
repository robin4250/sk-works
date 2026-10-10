import 'package:flutter/material.dart';
import '../../data/supabase_backend.dart';
import '../../international/language_controller.dart';
import 'source_notification_target.dart';

/// Exact saved target, read only. Viewing never signs or approves a report.
class SourceNotificationTargetPage extends StatefulWidget {
  const SourceNotificationTargetPage({super.key, required this.target});
  final SourceNotificationTarget target;
  @override
  State<SourceNotificationTargetPage> createState() => _SourceNotificationTargetPageState();
}

class _SourceNotificationTargetPageState extends State<SourceNotificationTargetPage> {
  Map<String, dynamic>? _row;
  Object? _error;
  bool _loading = true;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final client = SupabaseBackend.client;
      final user = client.auth.currentUser?.id;
      if (user == null) {
        throw StateError('Account unavailable');
      }
      final target = widget.target;
      final report = target.eventKey == 'group_report_saved';
      final raw = await client.from(report ? 'daily_reports' : 'attendance_verifications')
        .select(report
          ? 'id,company_id,report_date,work_description,status,sites(name),daily_report_workers(workers(name))'
          : 'id,company_id,work_date,event_type,confirmed_at,workers(name),vehicles(display_name,registration_number)')
        .eq('id', target.sourceId).eq('company_id', target.companyId).single();
      final row = Map<String, dynamic>.from(raw);
      target.validateRow(row);
      if (client.auth.currentUser?.id != user) {
        throw StateError('Account changed');
      }
      if (mounted) {
        setState(() { _row = row; _loading = false; });
      }
    } catch (error) {
      if (mounted) {
        setState(() { _error = error; _loading = false; });
      }
    }
  }

  String _name(Object? value, String key) => value is Map ? value[key]?.toString() ?? '' : '';
  @override
  Widget build(BuildContext context) {
    SkoLanguageController.watch(context);
    final row = _row;
    final report = widget.target.eventKey == 'group_report_saved';
    return Scaffold(
      appBar: AppBar(title: Text(SkoLanguageController.tr(report ? '日報' : '車両'))),
      body: _loading ? const Center(child: CircularProgressIndicator())
        : _error != null ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(SkoLanguageController.tr('状態を確認できません')),
          TextButton(onPressed: _load, child: Text(SkoLanguageController.tr('再読み込み'))),
        ])) : row == null ? const SizedBox.shrink()
        : ListView(padding: const EdgeInsets.all(16), children: [
          Text(widget.target.databaseDate, style: Theme.of(context).textTheme.titleLarge),
          if (report) ...[
            Text(_name(row['sites'], 'name')),
            Text(row['work_description']?.toString() ?? ''),
            Text(sourceReportStatusLabel(row['status'], english: SkoLanguageController.isEnglish)),
            if (row['daily_report_workers'] is List)
              for (final worker in row['daily_report_workers'] as List)
                if (worker is Map) Text(_name(worker['workers'], 'name')),
          ] else ...[
            Text(_name(row['workers'], 'name')),
            Text(_name(row['vehicles'], 'display_name')),
            Text(_name(row['vehicles'], 'registration_number')),
            Text(row['confirmed_at']?.toString() ?? ''),
          ],
        ]),
    );
  }
}
