import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'company_income_tax_repository.dart';

typedef IncomeTaxPdfPicker = Future<IncomeTaxPdfFile?> Function();

String _civilDate(DateTime day) => '${day.year.toString().padLeft(4, '0')}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';

class CompanyIncomeTaxPage extends StatefulWidget {
  const CompanyIncomeTaxPage({super.key, required this.companyId, this.repository, this.pickPdf});
  final String companyId;
  final CompanyIncomeTaxRepository? repository;
  final IncomeTaxPdfPicker? pickPdf;
  @override
  State<CompanyIncomeTaxPage> createState() => _CompanyIncomeTaxPageState();
}

class _CompanyIncomeTaxPageState extends State<CompanyIncomeTaxPage> {
  late CompanyIncomeTaxRepository _repository;
  late final TextEditingController _date;
  String _kind = 'monthly';
  CompanyIncomeTaxTablesData? _data;
  IncomeTaxUploadRequest? _unknown;
  IncomeTaxUploadRequest? _retryUpload;
  bool _busy = false;
  bool _loading = false;
  int _generation = 0;
  String? _error;
  @override
  void initState() {
    super.initState();
    _repository = widget.repository ?? SupabaseCompanyIncomeTaxRepository();
    _date = TextEditingController(text: _civilDate(DateTime.now().toUtc().add(const Duration(hours: 9))));
    _load();
  }
  @override
  void didUpdateWidget(covariant CompanyIncomeTaxPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.companyId != widget.companyId || oldWidget.repository != widget.repository) {
      _repository = widget.repository ?? SupabaseCompanyIncomeTaxRepository();
      _data = null;
      _unknown = null;
      _retryUpload = null;
      _load();
    }
  }
  @override
  void dispose() { _date.dispose(); super.dispose(); }

  Future<void> _load() async {
    try { parseIncomeTaxDate(_date.text.trim()); } on FormatException catch (error) {
      setState(() => _error = error.message);
      return;
    }
    final generation = ++_generation;
    final queryDate = _date.text.trim();
    final queryKind = _kind;
    setState(() { _busy = true; _loading = true; _error = null; });
    try {
      final data = await _repository.read(companyId: widget.companyId, date: queryDate, kind: queryKind);
      if (!mounted || generation != _generation) return;
      setState(() => _data = data);
      final unknown = _unknown;
      if (unknown != null) {
        final matched = data.tables.where((table) => table.id == unknown.tableId && table.version == 1 &&
          incomeTaxValuesEqual(table.value, unknown.value)).toList();
        if (matched.length == 1) {
          setState(() => _unknown = null);
          ScaffoldMessenger.of(context)
            ..removeCurrentSnackBar()
            ..showSnackBar(const SnackBar(content: Text('PDFの登録を確認しました')));
        }
      }
    } catch (_) {
      if (!mounted || generation != _generation) return;
      setState(() { _data = null; _error = '税額表を取得できません。接続・権限・機能の導入状況を確認してください。'; });
    } finally {
      if (mounted && generation == _generation) setState(() { _busy = false; _loading = false; });
    }
  }

  Future<IncomeTaxPdfFile?> _pickPdf() async {
    final picker = widget.pickPdf;
    if (picker != null) return picker();
    final file = await FilePicker.pickFile(type: FileType.custom, allowedExtensions: const ['pdf']);
    if (file == null) return null;
    final size = file.lengthSync() ?? await file.length();
    if (size == null || size < 5 || size > incomeTaxPdfMaxBytes) {
      throw const FormatException('10MB以下のPDFファイルを選択してください');
    }
    return IncomeTaxPdfFile(name: file.name, bytes: await file.readAsBytes());
  }

  Future<void> _register() async {
    if (_busy || _unknown != null || _data?.canEdit != true) {
      return;
    }
    final generation = _generation;
    setState(() => _busy = true);
    try {
      final request = _retryUpload ?? await showDialog<IncomeTaxUploadRequest>(context: context,
        builder: (_) => _IncomeTaxRegistration(companyId: widget.companyId, pickPdf: _pickPdf));
      if (!mounted || generation != _generation || request == null) return;
      final confirmed = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
        title: const Text('PDFを登録'),
        content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start,
          children: [_registrationDetails(request.value), const SizedBox(height: 12),
            const Text('年度・適用期間・情報元とPDFを確認して登録してください。登録後は未検証資料として保存され、給与には使用されません。')],
        )),
        actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('キャンセル')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('確認して登録'))],
      )) ?? false;
      if (!mounted || generation != _generation || !confirmed) return;
      setState(() { _unknown = request; _loading = true; });
      await _repository.registerPdf(request);
      if (!mounted || generation != _generation) return;
      setState(() { _unknown = null; _retryUpload = null; });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('PDFを未検証資料として登録しました')));
      await _load();
    } on IncomeTaxUploadIncomplete {
      if (mounted && generation == _generation) {
        setState(() { _retryUpload = _unknown; _unknown = null; });
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('PDFのアップロードを確認できませんでした。再試行またはファイルを選び直してください。')));
      }
    } catch (_) {
      if (mounted && generation == _generation) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_unknown == null ?
          '登録内容を確認できませんでした。' : '登録結果を確認できません。再読み込みして確認してください。')));
      }
    } finally {
      if (mounted && generation == _generation) setState(() { _busy = false; _loading = false; });
    }
  }

  static Widget _registrationDetails(Map<String, dynamic> value) => Column(
    crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      Text('${value['calendar_year']}年 ${incomeTaxKinds[value['kind']]}'),
      Text('適用開始 ${value['starts_on']}'), Text('適用最終日 ${incomeTaxIncludedLastDay(value['ends_before'] as String)}'),
      Text('PDF ${value['file_name']}'), Text('情報元 ${value['publisher']}'), Text('${value['source_url']}'),
    ],
  );

  Future<void> _openOfficialReference(String url) async {
    try {
      if (!await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication)) {
        throw StateError('Could not open reference');
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('国税庁の資料を開けませんでした。接続を確認して再度お試しください。')),
      );
    }
  }

  Future<void> _openPdf(CompanyIncomeTaxTable table) async {
    if (_busy) return;
    final generation = _generation;
    setState(() => _busy = true);
    try {
      final url = await _repository.pdfUrl(table.value['storage_path'] as String);
      if (!mounted || generation != _generation) return;
      final uri = Uri.tryParse(url);
      if (uri == null || uri.scheme != 'https' || uri.host.isEmpty || !await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        throw StateError('PDF unavailable');
      }
    } catch (_) {
      if (mounted && generation == _generation) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('PDFを開けませんでした')));
      }
    } finally {
      if (mounted && generation == _generation) setState(() => _busy = false);
    }
  }

  Widget _tableCard(CompanyIncomeTaxTable table) => Card(child: ExpansionTile(
    key: PageStorageKey('income-table-${table.id}'),
    title: Text('${table.value['calendar_year']}年 ${incomeTaxKinds[table.value['kind']]}'),
    subtitle: Text(table.rulesVerified ? '資料・計算ルール確認済み' : table.officialVerified ? '資料確認済み・計算ルール未確認' : '未検証'),
    children: [Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _registrationDetails(table.value),
      if (table.registeredBy != null) Text('登録者 ${table.registeredBy}'), Text('登録日時 ${table.registeredAt}'),
      OutlinedButton.icon(onPressed: _busy ? null : () => _openPdf(table), icon: const Icon(Icons.picture_as_pdf), label: const Text('PDFを開く')),
    ]))],
  ));

  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(toolbarHeight: kToolbarHeight, title: const Text('所得税の税額表'), actions: [
    IconButton(tooltip: '税額表の使い方', icon: const Icon(Icons.help_outline), onPressed: () => showDialog<void>(
      context: context, builder: (context) => AlertDialog(title: const Text('税額表の使い方'),
        content: _data?.canEdit == true ? const Text('PDFの登録と正式資料・計算ルールの検証は別です。新年度を事前登録しても未検証資料は給与に使用されません。共通公開や検証の操作はここでは行えません。\n\n旧年度PDFは保持します。適用最終日までの資料として登録します。公式資料の自動取得と実給与の税額表計算は準備中です。') : const Text('年度・適用期間・情報元とPDFを閲覧できます。未検証資料は給与に使用されません。給与連携は準備中です。'),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('閉じる'))],
      ),
    )),
  ]), body: SafeArea(child: ListView(padding: const EdgeInsets.all(16), children: [
    const Text('会社内のPDF資料を管理します。給与連携は準備中です。'),
    Card(child: ExpansionTile(
      title: const Text('国税庁の公式資料'),
      subtitle: const Text('源泉徴収税額表・年度別の資料'),
      children: [
        ListTile(
          title: const Text('2026年（令和8年）分の税額表PDF'),
          trailing: const Icon(Icons.open_in_new),
          onTap: () => _openOfficialReference('https://www.nta.go.jp/publication/pamph/gensen/zeigakuhyo2026/data/all.pdf'),
        ),
        ListTile(
          title: const Text('年度別の税額表・関連資料'),
          trailing: const Icon(Icons.open_in_new),
          onTap: () => _openOfficialReference('https://www.nta.go.jp/publication/pamph/01.htm'),
        ),
        const Padding(padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Text('対象の年分を確認してください。資料を開くだけでは会社への登録や給与への反映は行われません。')),
      ],
    )),
    if (_unknown != null) const Card(child: Padding(padding: EdgeInsets.all(12), child: Text('登録結果の確認が必要です。再読み込みで確認してください。重複登録を防ぐため追加登録は停止しています。'))),
    if (_data?.canEdit == true && _retryUpload != null) Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(children: [
      const Text('アップロード結果を確認できません。再試行または別のPDFを選択できます。'),
      TextButton(onPressed: _busy ? null : () { setState(() => _retryUpload = null); _register(); }, child: const Text('ファイルを選び直す')),
    ]))),
    if (_loading) const LinearProgressIndicator(),
    if (_error != null) Text(_error!),
    Row(children: [Expanded(child: TextField(key: const ValueKey('income-query-date'), controller: _date,
      enabled: !_busy, decoration: const InputDecoration(labelText: '確認日（YYYY-MM-DD）'),
      onChanged: (_) => setState(() => _data = null))), const SizedBox(width: 12),
      Expanded(child: DropdownButtonFormField<String>(initialValue: _kind, isExpanded: true,
        decoration: const InputDecoration(labelText: '種類'), items: [for (final entry in incomeTaxKinds.entries)
          DropdownMenuItem(value: entry.key, child: Text(entry.value))],
        onChanged: _busy ? null : (value) => setState(() { _kind = value ?? 'monthly'; _data = null; })))]),
    OutlinedButton.icon(onPressed: _busy ? null : _load, icon: const Icon(Icons.refresh), label: const Text('再読み込み')),
    if (_data != null) ...[
      if (!_data!.canEdit) const Text('閲覧のみ：年度・適用期間・情報元とPDFを確認できます。'),
      Text(_data!.selected == null ? '確認日の適用候補はありません' :
        '確認日の適用候補：${_data!.selected!.value['calendar_year']}年 ${incomeTaxKinds[_data!.selected!.value['kind']]}'),
      if (_data!.canEdit) FilledButton.icon(onPressed: _busy || _unknown != null ? null : _register, icon: const Icon(Icons.add), label: Text(_retryUpload == null ? 'PDFを登録' : 'アップロードを再試行')),
      if (_data!.tables.isEmpty) const Text('登録済み資料はありません'),
      for (final table in _data!.tables) _tableCard(table),
      if (_data!.canEdit) Card(child: ExpansionTile(title: const Text('変更履歴'), children: [
        for (final row in _data!.history) ListTile(
          title: Text(row['event_type'] == 'verification' ? '検証記録' : '登録記録'),
          subtitle: Text('変更者 ${row['actor_id']}\n変更日時 ${row['changed_at']}'),
        ),
      ])),
    ],
  ])));
}

class _IncomeTaxRegistration extends StatefulWidget {
  const _IncomeTaxRegistration({required this.companyId, required this.pickPdf});
  final String companyId;
  final IncomeTaxPdfPicker pickPdf;
  @override
  State<_IncomeTaxRegistration> createState() => _IncomeTaxRegistrationState();
}

class _IncomeTaxRegistrationState extends State<_IncomeTaxRegistration> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _year;
  late final TextEditingController _start;
  late final TextEditingController _end;
  final _url = TextEditingController();
  final _publisher = TextEditingController(text: '国税庁');
  String _kind = 'monthly';
  IncomeTaxPdfFile? _file;
  bool _picking = false;
  String? _error;
  int _defaultYear = DateTime.now().toUtc().add(const Duration(hours: 9)).year;
  @override
  void initState() {
    super.initState();
    _year = TextEditingController(text: '$_defaultYear');
    _start = TextEditingController(text: '$_defaultYear-01-01');
    _end = TextEditingController(text: '$_defaultYear-12-31');
  }
  @override
  void dispose() { for (final controller in [_year, _start, _end, _url, _publisher]) { controller.dispose(); } super.dispose(); }

  Future<void> _pick() async {
    if (_picking) return;
    setState(() { _picking = true; _error = null; });
    try {
      final file = await widget.pickPdf();
      if (mounted && file != null) setState(() => _file = file);
    } catch (_) {
      if (mounted) setState(() => _error = '10MB以下のPDFファイルを選択してください');
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  void _submit() {
    if (!_form.currentState!.validate()) return;
    final file = _file;
    if (file == null) { setState(() => _error = 'PDFを選択してください'); return; }
    try {
      final request = IncomeTaxUploadRequest.create(companyId: widget.companyId, year: int.parse(_year.text.trim()), kind: _kind,
        startsOn: _start.text.trim(), endsOn: _end.text.trim(), sourceUrl: _url.text.trim(), publisher: _publisher.text.trim(), file: file);
      Navigator.pop(context, request);
    } on FormatException catch (error) { setState(() => _error = error.message); }
  }

  Widget _field(TextEditingController controller, String label, String key) => Padding(padding: const EdgeInsets.only(bottom: 12),
    child: TextFormField(key: ValueKey(key), controller: controller, decoration: InputDecoration(labelText: label),
      validator: (text) => text == null || text.trim().isEmpty ? '入力してください' : null));

  @override
  Widget build(BuildContext context) => AlertDialog(title: const Text('PDF資料を追加'), content: SizedBox(width: 480,
    child: SingleChildScrollView(child: Form(key: _form, child: Column(mainAxisSize: MainAxisSize.min, children: [
      TextFormField(key: const ValueKey('income-year'), controller: _year, keyboardType: TextInputType.number,
        decoration: const InputDecoration(labelText: '年度（暦年）'), validator: (text) {
          final year = int.tryParse(text?.trim() ?? '');
          return year == null || year < 1000 || year > 9998 ? '年度を入力してください' : null;
        }, onChanged: (text) {
          final year = int.tryParse(text);
          if (year == null || year < 1000 || year > 9998) return;
          if (_start.text == '$_defaultYear-01-01' && _end.text == '$_defaultYear-12-31') {
            _start.text = '$year-01-01'; _end.text = '$year-12-31';
          }
          setState(() => _defaultYear = year);
        }),
      DropdownButtonFormField<String>(initialValue: _kind, isExpanded: true, decoration: const InputDecoration(labelText: '種類'),
        items: [for (final entry in incomeTaxKinds.entries) DropdownMenuItem(value: entry.key, child: Text(entry.value))],
        onChanged: (value) => setState(() => _kind = value ?? 'monthly')),
      OutlinedButton.icon(onPressed: _picking ? null : _pick, icon: const Icon(Icons.attach_file),
        label: Text(_file?.name ?? 'PDFを選択（10MB以下）')),
      _field(_url, '公式情報元URL', 'income-source-url'),
      ExpansionTile(title: const Text('適用期間・情報元'), subtitle: Text('${_start.text} → ${_end.text}'),
        children: [_field(_start, '適用開始（YYYY-MM-DD）', 'income-start'),
          _field(_end, '適用最終日（YYYY-MM-DD）', 'income-end'), _field(_publisher, '情報元の名称', 'income-publisher')]),
      if (_error != null) Text(_error!),
    ])))), actions: [TextButton(onPressed: _picking ? null : () => Navigator.pop(context), child: const Text('キャンセル')),
      FilledButton(onPressed: _picking ? null : _submit, child: const Text('内容を確認'))]);
}
