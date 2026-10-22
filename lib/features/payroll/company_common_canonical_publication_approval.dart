import 'package:flutter/material.dart';

/// View data supplied only after the existing payroll-view/admin authorization
/// and versioned preview contract have been verified by the repository.
class CommonPayrollCanonicalApprovalPreview {
  const CommonPayrollCanonicalApprovalPreview({
    required this.payrollTypeLabel, required this.startsOn,
    required this.targetCount, required this.excludedCount,
    required this.unresolvedCount, required this.activationRequired,
    required this.readyToPublish, this.legacyCount = 0,
    this.reasons = const [],
  });
  final String payrollTypeLabel;
  final DateTime startsOn;
  final int targetCount, excludedCount, unresolvedCount, legacyCount;
  final bool activationRequired, readyToPublish;
  final List<String> reasons;
  bool get valid => startsOn.day == 1 && payrollTypeLabel.isNotEmpty &&
      [targetCount, excludedCount, unresolvedCount, legacyCount].every((n) => n >= 0);
}

class CommonPayrollCanonicalApproval {
  const CommonPayrollCanonicalApproval({required this.approveActivation, required this.approveSelectedDays});
  final bool approveActivation, approveSelectedDays;
}

/// No API calls or persistent changes happen in this dialog. Capability remains
/// false by default until the deployed versioned contract is verified.
class CommonPayrollCanonicalPublicationApprovalDialog extends StatefulWidget {
  const CommonPayrollCanonicalPublicationApprovalDialog({
    super.key, required this.preview, this.deploymentAvailable = false,
  });
  final CommonPayrollCanonicalApprovalPreview preview;
  final bool deploymentAvailable;
  @override State<CommonPayrollCanonicalPublicationApprovalDialog> createState() =>
      _CommonPayrollCanonicalPublicationApprovalDialogState();
}

class _CommonPayrollCanonicalPublicationApprovalDialogState
    extends State<CommonPayrollCanonicalPublicationApprovalDialog> {
  bool _activation = false, _selectedDays = false;
  @override void didUpdateWidget(covariant CommonPayrollCanonicalPublicationApprovalDialog oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.preview, widget.preview) ||
        oldWidget.deploymentAvailable != widget.deploymentAvailable) {
      _activation = false;
      _selectedDays = false;
    }
  }
  @override Widget build(BuildContext context) {
    final p = widget.preview;
    final enabled = widget.deploymentAvailable && p.valid && p.readyToPublish &&
        p.unresolvedCount == 0 && (!p.activationRequired || _activation) &&
        (p.legacyCount == 0 || _selectedDays);
    return AlertDialog(
      title: const Text('共通手当を給与へ反映'),
      content: SizedBox(width: 480, child: SingleChildScrollView(child: Column(
        mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${p.payrollTypeLabel}・${p.startsOn.year}年${p.startsOn.month}月以降の未確定給与'),
          const SizedBox(height: 12),
          Text('反映対象 ${p.targetCount}件　除外 ${p.excludedCount}件　要確認 ${p.unresolvedCount}件'),
          const SizedBox(height: 8),
          const Text('確定済み給与・手動調整は保持します。未保存の編集は含みません。'),
          if (p.reasons.isNotEmpty) ExpansionTile(
            key: const ValueKey('canonical-publication-reasons'),
            tilePadding: EdgeInsets.zero,
            title: const Text('対象・除外・要確認の詳細'),
            children: [for (final reason in p.reasons)
              ListTile(dense: true, contentPadding: EdgeInsets.zero, title: Text(reason))],
          ),
          if (p.legacyCount > 0) CheckboxListTile(
            key: const ValueKey('canonical-publication-selected-days'),
            contentPadding: EdgeInsets.zero, controlAffinity: ListTileControlAffinity.leading,
            value: _selectedDays,
            onChanged: p.valid && p.readyToPublish && widget.deploymentAvailable
                ? (value) => setState(() => _selectedDays = value == true) : null,
            title: const Text('日報で選んだ手当を、選択した日数で反映する'),
            subtitle: const Text('同じ日は1回。選んでいない日は加算しません。'),
          ),
          if (p.activationRequired) CheckboxListTile(
            key: const ValueKey('canonical-publication-activation'),
            contentPadding: EdgeInsets.zero, controlAffinity: ListTileControlAffinity.leading,
            value: _activation,
            onChanged: p.valid && p.readyToPublish && widget.deploymentAvailable
                ? (value) => setState(() => _activation = value == true) : null,
            title: Text('${p.payrollTypeLabel}の共通手当の給与反映を開始する'),
          ),
          if (p.unresolvedCount > 0)
            Text('要確認の設定を解消してから反映してください。',
              style: TextStyle(color: Theme.of(context).colorScheme.error)),
          if (!widget.deploymentAvailable || !p.readyToPublish || !p.valid)
            const Text('適用準備を確認できません。給与は変更されません。'),
        ],
      ))),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('戻る')),
        FilledButton(
          key: const ValueKey('canonical-publication-confirm'),
          onPressed: enabled ? () => Navigator.pop(context,
            CommonPayrollCanonicalApproval(approveActivation: _activation,
              approveSelectedDays: _selectedDays)) : null,
          child: const Text('確認して反映'),
        ),
      ],
    );
  }
}
