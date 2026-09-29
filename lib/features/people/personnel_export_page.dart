import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../domain/company_data_transfer.dart';
import '../../domain/personnel_export_selection.dart';

enum PersonnelExportOperation { send, print }

class PersonnelExportWorker {
  const PersonnelExportWorker({required this.id, required this.name, this.originCompanyName});
  final String id;
  final String name;
  final String? originCompanyName;
}

class PersonnelExportResult {
  const PersonnelExportResult({required this.selection, required this.operation, this.targetCompany});
  final PersonnelExportSelection selection;
  final PersonnelExportOperation operation;
  final String? targetCompany;
}

class PersonnelExportPage extends StatefulWidget {
  const PersonnelExportPage({
    super.key,
    required this.title,
    required this.workers,
    required this.operation,
    this.fixedKind,
    this.initialWorkerIds = const <String>[],
  });

  final String title;
  final List<PersonnelExportWorker> workers;
  final PersonnelExportOperation operation;
  final TransferPayloadKind? fixedKind;
  final List<String> initialWorkerIds;

  @override
  State<PersonnelExportPage> createState() => _PersonnelExportPageState();
}

class _PersonnelExportPageState extends State<PersonnelExportPage> {
  late final Set<String> _selectedWorkerIds;
  late TransferPayloadKind _kind;
  final _targetCompanyController = TextEditingController();
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _selectedWorkerIds = widget.initialWorkerIds
        .where((id) => widget.workers.any((worker) => worker.id == id))
        .toSet();
    _kind = widget.fixedKind ?? TransferPayloadKind.personnelBundle;
  }

  @override
  void dispose() {
    _targetCompanyController.dispose();
    super.dispose();
  }

  bool get _isSend => widget.operation == PersonnelExportOperation.send;

  PersonnelExportSelection get _selection => PersonnelExportSelection(
        workerIds: _selectedWorkerIds.toList(growable: false),
        kind: _kind,
      );

  String get _operationLabel => _isSend ? '親会社に送る' : '印刷';

  @override
  Widget build(BuildContext context) {
    final selection = _selection;
    final canContinue = !selection.isEmpty &&
        (!_isSend || _targetCompanyController.text.trim().isNotEmpty);

    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
          children: [
            Text(
              _operationLabel,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
            ),
            const SizedBox(height: 6),
            const Text('対象と内容を確認してから確定します。一発で送信・印刷はしません。'),
            const SizedBox(height: 18),
            if (widget.fixedKind == null) ...[
              const Text('内容', style: TextStyle(fontWeight: FontWeight.w900)),
              const SizedBox(height: 8),
              SegmentedButton<TransferPayloadKind>(
                segments: const [
                  ButtonSegment(value: TransferPayloadKind.personnelBundle, label: Text('一式')),
                  ButtonSegment(value: TransferPayloadKind.qualificationsOnly, label: Text('資格のみ')),
                  ButtonSegment(value: TransferPayloadKind.documentsOnly, label: Text('書類のみ')),
                ],
                selected: {_kind},
                onSelectionChanged: (value) => setState(() => _kind = value.first),
              ),
              const SizedBox(height: 18),
            ],
            if (_isSend) ...[
              TextField(
                controller: _targetCompanyController,
                decoration: const InputDecoration(
                  labelText: '送信先の親会社',
                  hintText: '会社名 または SKO会社ID',
                  prefixIcon: Icon(Icons.business_outlined),
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 18),
            ],
            Row(
              children: [
                const Text('対象者', style: TextStyle(fontWeight: FontWeight.w900)),
                const Spacer(),
                TextButton(
                  onPressed: widget.workers.isEmpty
                      ? null
                      : () => setState(() {
                            if (_selectedWorkerIds.length == widget.workers.length) {
                              _selectedWorkerIds.clear();
                            } else {
                              _selectedWorkerIds
                                ..clear()
                                ..addAll(widget.workers.map((worker) => worker.id));
                            }
                          }),
                  child: Text(
                    _selectedWorkerIds.length == widget.workers.length && widget.workers.isNotEmpty
                        ? '全解除'
                        : 'すべて選択',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            if (widget.workers.isEmpty)
              const Card(child: Padding(padding: EdgeInsets.all(18), child: Text('対象者がありません')))
            else
              for (final worker in widget.workers)
                Card(
                  child: CheckboxListTile(
                    value: _selectedWorkerIds.contains(worker.id),
                    onChanged: (value) => setState(() {
                      if (value == true) {
                        _selectedWorkerIds.add(worker.id);
                      } else {
                        _selectedWorkerIds.remove(worker.id);
                      }
                    }),
                    title: Text(worker.name, style: const TextStyle(fontWeight: FontWeight.w800)),
                    subtitle: (worker.originCompanyName ?? '').isEmpty
                        ? null
                        : Text('出所: \${worker.originCompanyName}'),
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                ),
            const SizedBox(height: 18),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('確認内容', style: TextStyle(fontWeight: FontWeight.w900)),
                    const SizedBox(height: 8),
                    if (_isSend && _targetCompanyController.text.trim().isNotEmpty)
                      Text('送信先: \${_targetCompanyController.text.trim()}'),
                    Text('内容: \${selection.summaryLabel}'),
                    Text('対象者: \${_selectedWorkerIds.length}名'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: !canContinue || _submitting ? null : _confirmAndRun,
              icon: Icon(_isSend ? Icons.send_outlined : Icons.print_outlined),
              label: Text('内容を確認して\$_operationLabel'),
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmAndRun() async {
    final selection = _selection;
    final selectedNames = widget.workers
        .where((worker) => _selectedWorkerIds.contains(worker.id))
        .map((worker) => worker.name)
        .toList(growable: false);
    final targetCompany = _isSend ? _targetCompanyController.text.trim() : null;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('最終確認 — \$_operationLabel'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (targetCompany != null) Text('送信先: \$targetCompany'),
              Text('内容: \${selection.summaryLabel}'),
              Text('対象: \${selectedNames.length}名'),
              const SizedBox(height: 10),
              for (final name in selectedNames) Text('・\$name'),
              if (_isSend) ...[
                const SizedBox(height: 12),
                const Text('受け渡し後も出所情報を保持し、上位会社へ転送できる前提で扱います。'),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('戻る')),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(_isSend ? '送信内容を確定' : '印刷する'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _submitting = true);
    try {
      if (widget.operation == PersonnelExportOperation.print) {
        await _printSelection(selection, selectedNames);
      }
      if (!mounted) return;
      Navigator.of(context).pop(
        PersonnelExportResult(
          selection: selection,
          operation: widget.operation,
          targetCompany: targetCompany,
        ),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _printSelection(
    PersonnelExportSelection selection,
    List<String> selectedNames,
  ) async {
    final document = pw.Document();
    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (_) => [
          pw.Text('SKO Personnel Export', style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 12),
          pw.Text('Scope: \${selection.kind.name}'),
          pw.Text('People: \${selectedNames.length}'),
          pw.SizedBox(height: 12),
          for (final name in selectedNames) pw.Text('- \$name'),
        ],
      ),
    );
    await Printing.layoutPdf(onLayout: (_) => document.save());
  }
}