import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:url_launcher/url_launcher.dart';

import '../common/japanese_phone.dart';
import 'people_cloud_repository.dart';

class PartnerCompanyDirectoryPage extends StatefulWidget {
  const PartnerCompanyDirectoryPage({super.key});

  @override
  State<PartnerCompanyDirectoryPage> createState() =>
      _PartnerCompanyDirectoryPageState();
}

class _PartnerCompanyDirectoryPageState
    extends State<PartnerCompanyDirectoryPage> {
  final _repository = PeopleCloudRepository.maybeCreate();
  final _query = TextEditingController();

  List<Map<String, dynamic>> _companies = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final repository = _repository;
    if (repository == null) {
      setState(() {
        _loading = false;
        _error = '取引会社一覧を利用できません。';
      });
      return;
    }

    try {
      if (!await repository.canOpenPartnerCompanyDirectory()) {
        throw StateError('取引会社一覧は管理者・サブ管理者のみ利用できます。');
      }
      final companies = await repository.loadPartnerCompanyDirectory();
      if (!mounted) return;
      setState(() {
        _companies = companies;
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  List<Map<String, dynamic>> get _filtered {
    final needle = _query.text.trim().toLowerCase();
    if (needle.isEmpty) return _companies;
    return _companies.where((row) {
      final text = [
        row['name'],
        row['postal_code'],
        row['address'],
        row['phone'],
        row['fax'],
        row['email'],
        row['president_name'],
        row['president_mobile'],
        row['president_home_area'],
        row['notes'],
      ].whereType<Object>().join(' ').toLowerCase();
      return text.contains(needle);
    }).toList(growable: false);
  }

  Future<void> _openMap(String address) async {
    final value = address.trim();
    if (value.isEmpty) return;
    final uri = Uri.https('maps.google.com', '/maps', {'q': value});
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication) &&
        mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Googleマップを開けませんでした')),
      );
    }
  }

  Future<void> _call(String phone) async {
    final domestic = japaneseDomesticPhone(phone);
    final value = domestic.replaceAll(RegExp(r'[^0-9+]'), '');
    if (value.isEmpty) return;
    if (!await launchUrl(Uri(scheme: 'tel', path: value)) && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('電話を開始できませんでした')),
      );
    }
  }

  Future<void> _print() async {
    if (_companies.isEmpty) return;
    final repository = _repository;
    if (repository == null) return;
    final companyName = await repository.companyName();
    if (!mounted) return;

    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => _PartnerDirectoryPrintPreview(
          companyName: companyName,
          companies: _filtered,
        ),
      ),
    );
  }

  Future<void> _edit([Map<String, dynamic>? row]) async {
    final result = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(
        builder: (_) => _PartnerCompanyEditPage(initial: row),
      ),
    );
    if (result == null || _repository == null) return;

    try {
      await _repository!.savePartnerCompanyDirectoryEntry(
        result,
        id: row?['id']?.toString(),
      );
      await _load();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('取引会社を保存できませんでした: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final companies = _filtered;
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          '取引会社一覧',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        actions: [
          IconButton(
            tooltip: '一覧表を印刷',
            onPressed: _loading || _companies.isEmpty ? null : _print,
            icon: const Icon(Icons.print_outlined),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _loading ? null : () => _edit(),
        icon: const Icon(Icons.add_business_outlined),
        label: const Text('取引会社を登録'),
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(_error!, textAlign: TextAlign.center),
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
                    children: [
                      TextField(
                        controller: _query,
                        decoration: const InputDecoration(
                          labelText: '取引会社を検索',
                          prefixIcon: Icon(Icons.search),
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                      const SizedBox(height: 10),
                      OutlinedButton.icon(
                        onPressed: _print,
                        icon: const Icon(Icons.table_chart_outlined),
                        label: const Text('取引会社 一覧表'),
                      ),
                      const SizedBox(height: 12),
                      if (companies.isEmpty)
                        const Card(
                          child: Padding(
                            padding: EdgeInsets.all(20),
                            child: Text('登録された取引会社はありません'),
                          ),
                        )
                      else
                        for (final row in companies)
                          Card(
                            child: ExpansionTile(
                              leading: const CircleAvatar(
                                child: Icon(Icons.business_outlined),
                              ),
                              title: Text(
                                row['name']?.toString() ?? '会社',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              subtitle: Text(
                                _address(row),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              childrenPadding:
                                  const EdgeInsets.fromLTRB(16, 0, 16, 12),
                              children: [
                                _value('会社名', row['name']),
                                _value('住所', _address(row)),
                                _actionValue(
                                  '電話番号',
                                  japaneseDomesticPhone(row['phone']),
                                  () => _call(
                                    row['phone']?.toString() ?? '',
                                  ),
                                  Icons.phone_outlined,
                                ),
                                _value(
                                  'FAX番号',
                                  japaneseDomesticPhone(row['fax']),
                                ),
                                _value('メールアドレス', row['email']),
                                _value('社長氏名', row['president_name']),
                                _actionValue(
                                  '社長携帯番号',
                                  japaneseDomesticPhone(
                                    row['president_mobile'],
                                  ),
                                  () => _call(
                                    row['president_mobile']?.toString() ?? '',
                                  ),
                                  Icons.phone_iphone_outlined,
                                ),
                                _value(
                                  '社長自宅エリア',
                                  row['president_home_area'],
                                ),
                                _value('メモ', row['notes']),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    Expanded(
                                      child: OutlinedButton.icon(
                                        onPressed: _address(row).trim().isEmpty
                                            ? null
                                            : () => _openMap(_address(row)),
                                        icon: const Icon(Icons.map_outlined),
                                        label: const Text('Googleマップ'),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: FilledButton.icon(
                                        onPressed: () => _edit(row),
                                        icon: const Icon(Icons.edit_outlined),
                                        label: const Text('編集'),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                    ],
                  ),
      ),
    );
  }

  String _address(Map<String, dynamic> row) {
    final postal = row['postal_code']?.toString().trim() ?? '';
    final address = row['address']?.toString().trim() ?? '';
    if (postal.isEmpty) return address;
    final normalized =
        postal.startsWith('〒') ? postal : '〒' + postal;
    return address.isEmpty ? normalized : normalized + ' ' + address;
  }

  Widget _value(String label, Object? value) {
    final text = value?.toString().trim() ?? '';
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      title: Text(label),
      subtitle: Text(text.isEmpty ? '未登録' : text),
    );
  }

  Widget _actionValue(
    String label,
    String value,
    VoidCallback onTap,
    IconData icon,
  ) {
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      title: Text(label),
      subtitle: Text(value.isEmpty ? '未登録' : value),
      trailing: value.isEmpty ? null : Icon(icon),
      onTap: value.isEmpty ? null : onTap,
    );
  }
}

class _PartnerCompanyEditPage extends StatefulWidget {
  const _PartnerCompanyEditPage({this.initial});

  final Map<String, dynamic>? initial;

  @override
  State<_PartnerCompanyEditPage> createState() =>
      _PartnerCompanyEditPageState();
}

class _PartnerCompanyEditPageState extends State<_PartnerCompanyEditPage> {
  late final Map<String, TextEditingController> _controllers;

  static const _fields = <(String, String)>[
    ('name', '会社名'),
    ('postal_code', '郵便番号'),
    ('address', '住所'),
    ('phone', '電話番号'),
    ('fax', 'FAX番号'),
    ('email', 'メールアドレス'),
    ('president_name', '社長氏名'),
    ('president_mobile', '社長携帯番号'),
    ('president_home_area', '社長自宅エリア'),
    ('notes', 'メモ'),
  ];

  @override
  void initState() {
    super.initState();
    _controllers = {
      for (final field in _fields)
        field.$1: TextEditingController(
          text: widget.initial?[field.$1]?.toString() ?? '',
        ),
    };
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.initial == null ? '取引会社を登録' : '取引会社を編集'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          for (final field in _fields) ...[
            TextField(
              controller: _controllers[field.$1],
              keyboardType: _keyboard(field.$1),
              maxLines: field.$1 == 'notes' ? 4 : 1,
              decoration: InputDecoration(
                labelText: field.$2,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
          ],
          FilledButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.save_outlined),
            label: const Text('確定して保存'),
          ),
        ],
      ),
    );
  }

  void _save() {
    final name = _controllers['name']!.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('会社名を入力してください')),
      );
      return;
    }
    Navigator.of(context).pop({
      for (final field in _fields)
        field.$1: _controllers[field.$1]!.text.trim(),
    });
  }

  TextInputType _keyboard(String key) {
    if (key == 'phone' || key == 'fax' || key == 'president_mobile') {
      return TextInputType.phone;
    }
    if (key == 'email') return TextInputType.emailAddress;
    return TextInputType.text;
  }
}

class _PartnerDirectoryPrintPreview extends StatelessWidget {
  const _PartnerDirectoryPrintPreview({
    required this.companyName,
    required this.companies,
  });

  final String companyName;
  final List<Map<String, dynamic>> companies;

  Future<Uint8List> _build() async {
    final regular = await PdfGoogleFonts.notoSansJPRegular();
    final bold = await PdfGoogleFonts.notoSansJPBold();
    final now = DateTime.now();
    final document = pw.Document(
      theme: pw.ThemeData.withFont(base: regular, bold: bold),
    );

    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(10 * PdfPageFormat.mm),
        build: (_) => [
          pw.Stack(
            children: [
              pw.Align(
                alignment: pw.Alignment.center,
                child: pw.Text(
                  companyName,
                  style: pw.TextStyle(
                    fontSize: 16,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ),
              pw.Align(
                alignment: pw.Alignment.centerRight,
                child: pw.Text(
                  _date(now),
                  style: const pw.TextStyle(fontSize: 9),
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 8),
          pw.Text(
            '取引会社一覧',
            textAlign: pw.TextAlign.center,
            style: pw.TextStyle(
              fontSize: 13,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 8),
          pw.TableHelper.fromTextArray(
            headers: const [
              '会社名',
              '郵便番号付き住所',
              '電話番号',
              'FAX番号',
              'メールアドレス',
              '社長氏名',
              '社長携帯番号',
              '社長自宅エリア',
              'メモ',
            ],
            data: [
              for (final row in companies)
                [
                  row['name']?.toString() ?? '',
                  _fullAddress(row),
                  japaneseDomesticPhone(row['phone']),
                  japaneseDomesticPhone(row['fax']),
                  row['email']?.toString() ?? '',
                  row['president_name']?.toString() ?? '',
                  japaneseDomesticPhone(row['president_mobile']),
                  row['president_home_area']?.toString() ?? '',
                  row['notes']?.toString() ?? '',
                ],
            ],
            headerStyle: pw.TextStyle(
              fontSize: 7,
              fontWeight: pw.FontWeight.bold,
            ),
            cellStyle: const pw.TextStyle(fontSize: 6.5),
            headerDecoration:
                const pw.BoxDecoration(color: PdfColors.grey300),
            cellPadding: const pw.EdgeInsets.all(3),
            border: pw.TableBorder.all(
              color: PdfColors.grey500,
              width: 0.5,
            ),
          ),
        ],
      ),
    );
    return document.save();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('取引会社 一覧表')),
      body: PdfPreview(
        build: (_) => _build(),
        canChangePageFormat: false,
        canChangeOrientation: false,
        allowPrinting: true,
        allowSharing: true,
        pdfFileName: '取引会社一覧.pdf',
      ),
    );
  }

  static String _fullAddress(Map<String, dynamic> row) {
    final postal = row['postal_code']?.toString().trim() ?? '';
    final address = row['address']?.toString().trim() ?? '';
    final normalized =
        postal.isEmpty ? '' : (postal.startsWith('〒') ? postal : '〒' + postal);
    return [normalized, address].where((v) => v.isNotEmpty).join(' ');
  }

  static String _date(DateTime value) {
    String two(int n) => n.toString().padLeft(2, '0');
    return value.year.toString() +
        '/' +
        two(value.month) +
        '/' +
        two(value.day);
  }
}
