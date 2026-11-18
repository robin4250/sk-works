import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'company_document_exchange_repository.dart';
import '../payroll/payroll_pdf_service.dart';
import '../payroll/employment_contract_layout.dart';
import 'package:flutter/foundation.dart';

enum _Field {
  name('従業員名', Offset(contractWorkerNameX / 637, contractWorkerNameY / 900)),
  signedOn('締結日', Offset(.69, .106)),
  period('契約期間', Offset(.365, .205)),
  dailyPay('日給', Offset(.405, .428));

  const _Field(this.label, this.position);
  final String label;
  final Offset position;
}

class PartnerEmploymentContractPage extends StatefulWidget {
  const PartnerEmploymentContractPage({
    super.key,
    required this.workerName,
    this.repository,
    this.deliveryItemId,
  });

  final String workerName;
  final CompanyDocumentExchangeRepository? repository;
  final String? deliveryItemId;

  @override
  State<PartnerEmploymentContractPage> createState() =>
      _PartnerEmploymentContractPageState();
}

class _PartnerEmploymentContractPageState
    extends State<PartnerEmploymentContractPage> {
  static const _asset = PayrollEmploymentContractPage.templateAsset;
  final _positions = {for (final field in _Field.values) field: field.position};
  final _values = <_Field, String>{};
  Uint8List? _background;
  Map<String, String>? _issuer;
  var _periodFixed = false;
  final _workTerms = {for (final row in contractWorkRows) row.key: row.initial};
  var _transportTerms = PayrollEmploymentContractPage.defaultTransportTerms;
  var _retirementTerms = PayrollEmploymentContractPage.defaultRetirementTerms;
  var _revision = 0;
  var _busy = false;
  var _loadFailed = false;

  @override
  void initState() {
    super.initState();
    _values[_Field.name] = widget.workerName;
    if (widget.repository != null) _load();
  }

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _loadFailed = false;
    });
    try {
      final issuer = await widget.repository!.employmentContractIssuer(
        widget.deliveryItemId!,
      );
      if (!mounted) return;
      setState(() => _issuer = issuer);
      final saved = await widget.repository!.partnerEmploymentContractDraft(
        widget.deliveryItemId!,
      );
      if (!mounted || saved == null) return;
      final document = saved['document'] as Map;
      final values = document['values'] as Map;
      final positions = document['positions'] as Map;
      final image = document['background'] as String?;
      final savedBackground = image == null ? null : base64Decode(image);
      final legacyStandard =
          savedBackground != null &&
          listEquals(
            savedBackground,
            (await rootBundle.load(_asset)).buffer.asUint8List(),
          );
      if (!mounted) return;
      setState(() {
        _revision = saved['revision'] as int;
        _background = legacyStandard ? null : savedBackground;
        _periodFixed = document['periodFixed'] == true;
        for (final row in contractWorkRows) {
          _workTerms[row.key] = document[row.key] as String? ?? row.initial;
        }
        _transportTerms =
            document['transportTerms'] as String? ??
            PayrollEmploymentContractPage.defaultTransportTerms;
        _retirementTerms =
            document['retirementTerms'] as String? ??
            PayrollEmploymentContractPage.defaultRetirementTerms;
        for (final field in _Field.values) {
          final position = positions[field.name] as List;
          if (document['layout'] != 'a4_typeset' && _background == null) {
            _positions[field] = field.position.translate(
              0,
              field == _Field.period && _periodFixed ? .019 : 0,
            );
          } else {
            _positions[field] = Offset(
              (position[0] as num).toDouble(),
              (position[1] as num).toDouble(),
            );
          }
          _values[field] = values[field.name] as String? ?? '';
        }
      });
    } catch (_) {
      if (mounted) setState(() => _loadFailed = true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save({DateTime? approvalMonth}) async {
    setState(() => _busy = true);
    try {
      final issuer = await widget.repository!.employmentContractIssuer(
        widget.deliveryItemId!,
      );
      if (!mounted) return;
      setState(() => _issuer = issuer);
      final background = _background;
      final saved = await widget.repository!.partnerEmploymentContractDraft(
        widget.deliveryItemId!,
        revision: _revision,
        document: {
          'values': {
            for (final entry in _values.entries) entry.key.name: entry.value,
          },
          'positions': {
            for (final entry in _positions.entries)
              entry.key.name: [entry.value.dx, entry.value.dy],
          },
          'background': background == null ? null : base64Encode(background),
          if (background == null) 'layout': 'a4_typeset',
          'periodFixed': _periodFixed,
          if (_background == null) 'issuer': issuer,
          'transportTerms': _transportTerms,
          ..._workTerms,
          'retirementTerms': _retirementTerms,
        },
      );
      if (!mounted) return;
      _revision = saved!['revision'] as int;
      if (approvalMonth != null) {
        await widget.repository!.approvePartnerEmploymentContract(
          widget.deliveryItemId!,
          _revision,
          approvalMonth,
        );
      }
      if (mounted)
        _message(
          approvalMonth == null
              ? '雇用契約の下書きを保存しました。'
              : '対象月の給与明細に添付する契約書を登録しました。',
        );
    } catch (error) {
      if (!mounted) return;
      _message(
        error is PostgrestException && error.code == '40001'
            ? '別の画面で更新されています。入力内容を控えてから開き直してください。'
            : '下書きを保存できませんでした。',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _registerForPayroll() async {
    if (_Field.values.any((field) => (_values[field] ?? '').trim().isEmpty)) {
      _message('氏名・締結日・契約期間・日給を入力してください。');
      return;
    }
    final month = await showDatePicker(
      context: context,
      helpText: '添付する給与明細の月を選択',
      initialDate: DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (month == null || !mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${month.year}年${month.month}月の給与明細'),
        content: const Text('給与明細を確定すると、この契約書が2ページ目に付きます。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('登録'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) await _save(approvalMonth: month);
  }

  void _message(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _editValue(_Field field) async {
    var value = _values[field] ?? '';
    final updated = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(field.label),
        content: TextFormField(
          initialValue: value,
          autofocus: true,
          decoration: InputDecoration(
            hintText: switch (field) {
              _Field.signedOn => '2026-11-09',
              _Field.period when _periodFixed => '2026-11-09～2027-10-31',
              _Field.period => '2026-11-09',
              _ => null,
            },
          ),
          maxLength: field == _Field.period ? 40 : 24,
          onChanged: (text) => value = text,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, value.trim()),
            child: const Text('反映'),
          ),
        ],
      ),
    );
    if (mounted && updated != null) setState(() => _values[field] = updated);
  }

  Future<String?> _editContractText({
    required String label,
    required String value,
    required bool multiline,
    required int maxLength,
  }) {
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(label),
        content: SizedBox(
          width: 520,
          child: TextFormField(
            initialValue: value,
            minLines: multiline ? 4 : 1,
            maxLines: multiline ? 10 : 1,
            maxLength: maxLength,
            onChanged: (text) => value = text,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, value.trim()),
            child: const Text('反映'),
          ),
        ],
      ),
    );
  }

  Future<void> _editWorkTerm(String key, String label) async {
    final edited = await _editContractText(
      label: label,
      value: _workTerms[key]!,
      multiline: false,
      maxLength: 65,
    );
    if (mounted && edited != null) setState(() => _workTerms[key] = edited);
  }

  Future<void> _editTerms({required bool transport}) async {
    final edited = await _editContractText(
      label: transport ? '交通費' : '退職に関する事項',
      value: transport ? _transportTerms : _retirementTerms,
      multiline: !transport,
      maxLength: transport ? 40 : 1200,
    );
    if (mounted && edited != null) {
      setState(() {
        if (transport) {
          _transportTerms = edited;
        } else {
          _retirementTerms = edited;
        }
      });
    }
  }

  Future<void> _pickBackground() async {
    try {
      final selected = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: ['png', 'jpg', 'jpeg'],
      );
      if ((selected?.lengthSync() ?? 0) > 3 * 1024 * 1024) {
        if (mounted) _message('3 MB以下の様式画像を選んでください。');
        return;
      }
      final bytes = await selected?.readAsBytes();
      if (bytes == null || !mounted) return;
      if (bytes.length > 3 * 1024 * 1024) {
        _message('3 MB以下の様式画像を選んでください。');
        return;
      }
      final decoded = await decodeImageFromList(bytes);
      decoded.dispose();
      if (mounted) setState(() => _background = bytes);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('様式画像を開けませんでした。')));
      }
    }
  }

  Future<Uint8List> _buildPdf() async {
    final background = _background;
    final font = pw.Font.ttf(
      await rootBundle.load('assets/fonts/web-ui/NotoSansJP-Regular.ttf'),
    );
    final document = pw.Document(theme: pw.ThemeData.withFont(base: font));
    final page = await PayrollEmploymentContractPage.fromDocument(
      {
        if (background == null) 'layout': 'a4_typeset',
        if (background != null) 'background': base64Encode(background),
        'values': {
          for (final entry in _values.entries) entry.key.name: entry.value,
        },
        'positions': {
          for (final entry in _positions.entries)
            entry.key.name: [entry.value.dx, entry.value.dy],
        },
        if (_background == null && _issuer != null) 'issuer': _issuer,
        'transportTerms': _transportTerms,
          ..._workTerms,
        'retirementTerms': _retirementTerms,
      },
      statementId: '',
      statementRevision: 0,
    );
    page.appendTo(document);
    return document.save();
  }

  void _preview() {
    final pdf = _buildPdf();
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(title: const Text('雇用契約書のプレビュー')),
          body: PdfPreview(
            build: (_) => pdf,
            canChangePageFormat: false,
            canChangeOrientation: false,
            pdfFileName: '雇用契約書.pdf',
          ),
        ),
      ),
    );
  }

  Widget _typesetSheet(double width, double height) {
    final sx = width / 637;
    final sy = height / 900;
    Widget text(double x, double y, double size, String value) => Positioned(
      left: x * sx,
      top: y * sy,
      child: Text(
        value,
        style: TextStyle(fontSize: size * sx, height: 1.2, color: Colors.black),
      ),
    );
    return ColoredBox(
      color: Colors.white,
      child: Stack(
        children: [
          for (final (x1, y1, x2, y2) in contractRules)
            Positioned(
              left: x1 * sx,
              top: y1 * sy,
              width: x1 == x2 ? sx : (x2 - x1) * sx,
              height: y1 == y2 ? sy : (y2 - y1) * sy,
              child: const ColoredBox(color: Colors.black),
            ),
          for (final (x, y, size, value) in contractLabels)
            text(x, y, size, value),
          for (final row in contractWorkRows)
            Positioned(
              left: 135 * sx,
              top: row.y * sy,
              width: 428 * sx,
              height: 13 * sy,
              child: Semantics(
                button: true,
                label: row.label,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _editWorkTerm(row.key, row.label),
                  child: FittedBox(
                    alignment: Alignment.topLeft,
                    fit: BoxFit.scaleDown,
                    child: Text(
                      _workTerms[row.key]!,
                      style: TextStyle(fontSize: 10 * sx, color: Colors.black),
                    ),
                  ),
                ),
              ),
            ),
          Positioned(
            left: contractWorkerSignature.x * sx,
            top: contractWorkerSignature.y * sy,
            width: contractWorkerSignature.width * sx,
            height: 13 * sy,
            child: GestureDetector(
              onTap: () => _editValue(_Field.name),
              child: FittedBox(
                alignment: Alignment.topLeft,
                fit: BoxFit.scaleDown,
                child: Text(
                  _values[_Field.name] ?? '',
                  style: TextStyle(fontSize: 10 * sx, color: Colors.black),
                ),
              ),
            ),
          ),
          for (final field in PayrollEmploymentContractPage.issuerFields(
            _issuer ?? const {},
          ))
            if (field.y == 166)
              Positioned(
                left: field.x * sx,
                top: field.y * sy,
                width: field.width * sx,
                height: 15 * sy,
                child: FittedBox(
                  alignment: Alignment.topRight,
                  fit: BoxFit.scaleDown,
                  child: Text(
                    field.value,
                    style: TextStyle(fontSize: 10 * sx, color: Colors.black),
                  ),
                ),
              )
            else
              text(field.x, field.y, 9, field.value),
          Positioned(
            left: 413 * sx,
            top: 442 * sy,
            width: 134 * sx,
            height: 13 * sy,
            child: GestureDetector(
              onTap: () => _editTerms(transport: true),
              child: FittedBox(
                alignment: Alignment.topLeft,
                fit: BoxFit.scaleDown,
                child: Text(
                  _transportTerms,
                  style: TextStyle(fontSize: 10 * sx),
                ),
              ),
            ),
          ),
          Positioned(
            left: 142 * sx,
            top: 505 * sy,
            width: 420 * sx,
            height: 221 * sy,
            child: GestureDetector(
              onTap: () => _editTerms(transport: false),
              child: FittedBox(
                alignment: Alignment.topLeft,
                fit: BoxFit.scaleDown,
                child: Text(
                  _retirementTerms,
                  style: TextStyle(fontSize: 10 * sx, height: 1.25),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _editor({required bool editTemplate}) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth.clamp(0.0, 700.0).toDouble();
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (editTemplate)
              Wrap(
                spacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: _pickBackground,
                    icon: const Icon(Icons.image_outlined),
                    label: const Text('様式画像を差し替え'),
                  ),
                  TextButton(
                    onPressed: () => setState(() {
                      _background = null;
                      _periodFixed = false;
                      for (final field in _Field.values) {
                        _positions[field] = field.position;
                      }
                    }),
                    child: const Text('標準様式に戻す'),
                  ),
                ],
              )
            else ...[
              Wrap(
                spacing: 8,
                children: [
                  for (final field in _Field.values)
                    ActionChip(
                      label: Text(field.label),
                      onPressed: () => _editValue(field),
                    ),
                  ActionChip(
                    label: const Text('交通費'),
                    onPressed: () => _editTerms(transport: true),
                  ),
                  ActionChip(
                    label: const Text('退職に関する事項'),
                    onPressed: () => _editTerms(transport: false),
                  ),
                  FilledButton.icon(
                    onPressed: _preview,
                    icon: const Icon(Icons.picture_as_pdf_outlined),
                    label: const Text('PDFを確認'),
                  ),
                  if (widget.repository != null)
                    OutlinedButton(
                      onPressed: _registerForPayroll,
                      child: const Text('給与明細に添付'),
                    ),
                ],
              ),
              SwitchListTile(
                title: const Text('期間の定めあり'),
                value: _periodFixed,
                onChanged: (fixed) => setState(() {
                  final current = _positions[_Field.period]!;
                  _positions[_Field.period] = current.translate(
                    0,
                    fixed ? .019 : -.019,
                  );
                  _periodFixed = fixed;
                }),
              ),
            ],
            const SizedBox(height: 12),
            Center(
              child: SizedBox(
                width: width,
                child: AspectRatio(
                  aspectRatio: PdfPageFormat.a4.width / PdfPageFormat.a4.height,
                  child: LayoutBuilder(
                    builder: (context, paper) {
                      final background = _background;
                      return Stack(
                        children: [
                          Positioned.fill(
                            child: background == null
                                ? _typesetSheet(paper.maxWidth, paper.maxHeight)
                                : Image.memory(background, fit: BoxFit.fill),
                          ),
                          for (final field in _Field.values)
                            Positioned(
                              left: _positions[field]!.dx * paper.maxWidth,
                              top: _positions[field]!.dy * paper.maxHeight,
                              child: GestureDetector(
                                onTap: editTemplate
                                    ? null
                                    : () => _editValue(field),
                                onPanUpdate: !editTemplate
                                    ? null
                                    : (event) {
                                        setState(() {
                                          final current = _positions[field]!;
                                          _positions[field] = Offset(
                                            (current.dx +
                                                    event.delta.dx /
                                                        paper.maxWidth)
                                                .clamp(0.0, .85)
                                                .toDouble(),
                                            (current.dy +
                                                    event.delta.dy /
                                                        paper.maxHeight)
                                                .clamp(0.0, .97)
                                                .toDouble(),
                                          );
                                        });
                                      },
                                child: Semantics(
                                  button: !editTemplate,
                                  label: field.label,
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.primaryContainer,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Padding(
                                      padding: const EdgeInsets.all(3),
                                      child: Text(
                                        editTemplate
                                            ? field.label
                                            : (_values[field]?.isNotEmpty ==
                                                      true
                                                  ? _values[field]!
                                                  : field.label),
                                        style: const TextStyle(fontSize: 10),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 2,
    child: Scaffold(
      appBar: AppBar(
        title: const Text('雇用契約'),
        actions: [
          if (widget.repository != null)
            TextButton(
              onPressed: _busy || _loadFailed ? null : _save,
              child: const Text('下書きを保存'),
            ),
        ],
        bottom: const TabBar(
          tabs: [
            Tab(text: '契約書入力'),
            Tab(text: '様式編集'),
          ],
        ),
      ),
      body: _busy
          ? const Center(child: CircularProgressIndicator())
          : _loadFailed
          ? Center(
              child: OutlinedButton(
                onPressed: _load,
                child: const Text('下書きを再読み込み'),
              ),
            )
          : TabBarView(
              children: [
                _editor(editTemplate: false),
                _editor(editTemplate: true),
              ],
            ),
    ),
  );
}
