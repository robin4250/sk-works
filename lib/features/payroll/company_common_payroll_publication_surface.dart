import 'package:flutter/material.dart';
import 'company_common_allowance_repository.dart';
import 'company_common_canonical_publication_panel.dart';
import 'company_common_canonical_publication_repository.dart';
import 'company_common_payroll_publication_panel.dart';

/// Select once per saved company snapshot. An existing legacy panel and its
/// in-memory pending command are never replaced by a background version probe.
class CompanyCommonPayrollPublicationSurface extends StatefulWidget {
  const CompanyCommonPayrollPublicationSurface({super.key, required this.settings,
    this.repository, this.enabled = true, this.canReconcile = true,
    this.initialPayrollType = 'hourly', this.onBusyChanged});
  final CompanyCommonAllowanceState settings;
  final CommonPayrollCanonicalPublicationRepository? repository;
  final bool enabled, canReconcile;
  final String initialPayrollType;
  final ValueChanged<bool>? onBusyChanged;
  @override State<CompanyCommonPayrollPublicationSurface> createState() => _CompanyCommonPayrollPublicationSurfaceState();
}
class _CompanyCommonPayrollPublicationSurfaceState extends State<CompanyCommonPayrollPublicationSurface> {
  late final CommonPayrollCanonicalPublicationRepository? _repository;
  late Future<bool> _probe;
  @override void initState() { super.initState(); _repository = widget.repository ??
    SupabaseCommonPayrollCanonicalPublicationRepository.maybeCreate(); _probe = _repository?.available() ?? Future.value(false); }
  @override Widget build(BuildContext context) => FutureBuilder<bool>(future: _probe, builder: (context, snapshot) {
    if (snapshot.connectionState != ConnectionState.done) {
      return const Card(child: ListTile(
      title: Text('未確定給与への反映'), subtitle: Text('反映方法を確認しています')));
    }
    if (snapshot.data == true && _repository != null) {
      return CompanyCommonCanonicalPublicationPanel(
      key: ValueKey('canonical-${widget.settings.companyId}/${widget.settings.version}'),
      settings: widget.settings, repository: _repository, enabled: widget.enabled,
      canReconcile: widget.canReconcile, initialPayrollType: widget.initialPayrollType,
      onBusyChanged: widget.onBusyChanged);
    }
    final legacy = widget.settings.legacyRefs.any((ref) => ref['amount_yen'] is int &&
      (ref['amount_yen'] as int) > 0 && ref['name'] is String && (ref['name'] as String).trim().isNotEmpty);
    if (!legacy) {
      return CompanyCommonPayrollPublicationPanel(
      companyId: widget.settings.companyId, enabled: widget.enabled, canReconcile: widget.canReconcile,
      initialPayrollType: widget.initialPayrollType, onBusyChanged: widget.onBusyChanged);
    }
    return Card(child: ExpansionTile(title: const Text('未確定給与への反映'),
      subtitle: const Text('共通手当の登録・保存は利用できます'), children: [
        const Padding(padding: EdgeInsets.all(12), child: Text('給与への反映を確認できません。設定を保存後、もう一度確認してください。')),
        TextButton(onPressed: () => setState(() => _probe = _repository?.available() ?? Future.value(false)),
          child: const Text('反映方法を確認')),
      ]));
  });
}
