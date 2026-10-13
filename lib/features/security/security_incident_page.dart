import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../../international/language_controller.dart';
import '../shared/company_seal_pdf.dart';
import 'security_incident.dart';
import 'security_incident_repository.dart';
import 'security_incident_report.dart';

import 'dart:convert';

class SecurityIncidentPage extends StatefulWidget {
  const SecurityIncidentPage({super.key, this.loadRecords, this.incidentId});
  final Future<List<SecurityIncident>> Function()? loadRecords;
  final String? incidentId;
  @override
  State<SecurityIncidentPage> createState() => _SecurityIncidentPageState();
}

class _SecurityIncidentPageState extends State<SecurityIncidentPage> {
  bool _loading = true, _failed = false;
  List<SecurityIncident> _records = const [];
  int _generation = 0;
  bool get _english => SkoLanguageController.isEnglish;
  String _text(String japanese, String english) =>
      _english ? english : japanese;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _failed = false;
      _records = const [];
    });
    try {
      final loader =
          widget.loadRecords ?? SecurityIncidentRepository.maybeCreate()?.load;
      if (loader == null) throw StateError('Unavailable');
      final records = await loader();
      if (!mounted || generation != _generation) return;
      setState(() {
        _records = records;
        _loading = false;
      });
      final id = widget.incidentId;
      if (id != null) {
        final matches = records.where((record) => record.id == id);
        if (matches.length == 1) await _open(matches.single);
      }
    } catch (_) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _failed = true;
        _loading = false;
      });
    }
  }

  Future<void> _open(SecurityIncident record) => Navigator.of(context)
      .push<void>(
        MaterialPageRoute(
          builder: (_) => SecurityIncidentDetailPage(record: record),
        ),
      );
  void _help() => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(_text('セキュリティ記録について', 'About security records')),
      content: SingleChildScrollView(
        child: Text(
          _text(
            'マスター専用の記録です。検知は攻撃確定ではありません。調査区分と収集状態を分けて確認します。収集中・前後ログ不足の記録は完全な記録ではありません。印刷・保存・共有は同じ安全化済みの内容です。本文・個人情報・秘密情報は含めません。隔離環境の検証段階で、本番の自動遮断は行いません。',
            'Master-only records. Detection does not confirm an attack. Investigation and collection states are separate. Collecting or missing logs indicate incomplete records. Print, save and share use the same sanitized report, without message bodies, personal information or secrets. This is an isolated validation stage, without automatic production blocking.',
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(_text('閉じる', 'Close')),
        ),
      ],
    ),
  );
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(_text('セキュリティ記録', 'Security records')),
      actions: [
        IconButton(
          onPressed: _help,
          icon: const Icon(Icons.help_outline),
          tooltip: _text('ヘルプ', 'Help'),
        ),
        IconButton(
          onPressed: _loading ? null : _load,
          icon: const Icon(Icons.refresh),
          tooltip: _text('更新', 'Refresh'),
        ),
      ],
    ),
    body: SafeArea(
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : _failed
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _text(
                      '記録を取得できません。未接続・権限・通信状態を確認してください。',
                      'Records unavailable. Check connection and access.',
                    ),
                  ),
                  TextButton(
                    onPressed: _load,
                    child: Text(_text('再読み込み', 'Retry')),
                  ),
                ],
              ),
            )
          : _records.isEmpty
          ? Center(child: Text(_text('保存された記録はありません。', 'No saved records.')))
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: _records.length,
              separatorBuilder: (_, index) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final record = _records[index];
                return Card(
                  child: ListTile(
                    leading: const Icon(Icons.policy_outlined),
                    title: Text(record.statusLabel(_english)),
                    subtitle: Text(
                      '${record.detectedAt.toLocal()}\n${record.collectionLabel(_english)} · ${record.events.length} ${_text('件', 'events')}',
                    ),
                    isThreeLine: true,
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _open(record),
                  ),
                );
              },
            ),
    ),
  );
}

class SecurityIncidentDetailPage extends StatefulWidget {
  const SecurityIncidentDetailPage({super.key, required this.record});
  final SecurityIncident record;
  @override
  State<SecurityIncidentDetailPage> createState() =>
      _SecurityIncidentDetailPageState();
}

class _SecurityIncidentDetailPageState
    extends State<SecurityIncidentDetailPage> {
  bool _busy = false;
  late final _report = SecurityIncidentReportData(widget.record);
  bool get _english => SkoLanguageController.isEnglish;
  String _text(String japanese, String english) =>
      _english ? english : japanese;
  Future<void> _export(bool print) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final bytes = await SecurityIncidentReport.build(
        _report,
        english: _english,
      );
      if (!mounted) return;
      final name = 'SKO-security-${widget.record.id}.pdf';
      if (print) {
        await Printing.layoutPdf(name: name, onLayout: (_) async => bytes);
      } else {
        await Printing.sharePdf(bytes: bytes, filename: name);
      }
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_text('出力できませんでした。', 'Export failed.'))),
        );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _shareJson() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final box = context.findRenderObject() as RenderBox?;
      await SharePlus.instance.share(
        ShareParams(
          files: [
            XFile.fromData(
              Uint8List.fromList(utf8.encode(_report.json)),
              mimeType: 'application/json',
              name: 'SKO-security-${widget.record.id}.json',
            ),
          ],
          fileNameOverrides: ['SKO-security-${widget.record.id}.json'],
          sharePositionOrigin: box == null
              ? null
              : box.localToGlobal(Offset.zero) & box.size,
        ),
      );
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_text('出力できませんでした。', 'Export failed.'))),
        );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(_text('記録の詳細', 'Record details'))),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          for (final line in _report.lines(_english))
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: SelectableText(line),
            ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: _busy ? null : () => _export(true),
                icon: const Icon(Icons.print_outlined),
                label: Text(_text('印刷', 'Print')),
              ),
              OutlinedButton.icon(
                onPressed: _busy ? null : () => _export(false),
                icon: const Icon(Icons.save_alt),
                label: Text(_text('保存・共有', 'Save / share')),
              ),
              OutlinedButton.icon(
                onPressed: _busy ? null : _shareJson,
                icon: const Icon(Icons.data_object),
                label: Text(_text('JSON照合データ', 'JSON verification data')),
              ),
            ],
          ),
          Text(
            _text(
              'iPhoneでは共有メニューから「ファイルに保存」を選べます。',
              'On iPhone, choose Save to Files in the share menu.',
            ),
          ),
        ],
      ),
    ),
  );
}

class SecurityIncidentReport {
  static Future<Uint8List> build(
    SecurityIncidentReportData report, {
    required bool english,
    pw.Font? font,
  }) async {
    final regular = font ?? await CompanySealPdf.loadFont();
    final document = pw.Document(theme: pw.ThemeData.withFont(base: regular));
    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        maxPages: 100,
        build: (_) => [
          for (final line in report.lines(english))
            pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 8),
              child: pw.Text(line, style: const pw.TextStyle(fontSize: 10)),
            ),
        ],
      ),
    );
    return document.save();
  }
}
