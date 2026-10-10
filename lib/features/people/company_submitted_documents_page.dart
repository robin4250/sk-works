// ignore_for_file: prefer_interpolation_to_compose_strings, dead_code

import 'dart:math';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'document_photo_draft.dart';

import '../common/data_date_labels.dart';
import '../../international/language_controller.dart';
import '../payroll/payroll_confirmation_settings_page.dart';
import '../settings/company_seal_settings_page.dart';
import 'company_document_exchange_repository.dart';
import 'company_submitted_document_repository.dart';
import 'company_transfer_send_page.dart';

class CompanySubmittedDocumentsPage extends StatefulWidget {
  const CompanySubmittedDocumentsPage({super.key});

  @override
  State<CompanySubmittedDocumentsPage> createState() =>
      _CompanySubmittedDocumentsPageState();
}

class _CompanySubmittedDocumentsPageState
    extends State<CompanySubmittedDocumentsPage> {
  final _repository = CompanySubmittedDocumentRepository.maybeCreate();
  final _exchange = CompanyDocumentExchangeRepository.maybeCreate();
  final _imagePicker = ImagePicker();
  final _selected = <String>{};
  final _receiveCode = TextEditingController();
  final _note = TextEditingController();
  final _companyName = TextEditingController();
  final _companyAddress = TextEditingController();
  final _corporateNumber = TextEditingController();
  final _companyPhone = TextEditingController();
  final _companyFax = TextEditingController();
  final _companyEmail = TextEditingController();
  final _bankName = TextEditingController();
  final _bankBranch = TextEditingController();
  final _bankAccountNumber = TextEditingController();
  final _bankAccountHolder = TextEditingController();

  List<Map<String, dynamic>> _documents = const [];
  bool _loading = true;
  bool _busy = false;
  String? _targetCompany;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final controller in [
      _receiveCode,
      _note,
      _companyName,
      _companyAddress,
      _corporateNumber,
      _companyPhone,
      _companyFax,
      _companyEmail,
      _bankName,
      _bankBranch,
      _bankAccountNumber,
      _bankAccountHolder,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _openCommonSend() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => const CompanyTransferSendPage(
          title: '会社提出書類を送信',
          sourceKind: 'company',
          subjectLabel: '会社提出書類',
          workerIds: <String>{},
          description: '会社単位の提出書類を、接続済み親会社へ全部または選択して送信します。',
        ),
      ),
    );
  }

  Future<void> _load() async {
    final repository = _repository;
    if (repository == null) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = '会社データを取得できません。ログイン状態を確認してください。';
        });
      }
      return;
    }
    try {
      final results = await Future.wait<Object>([
        repository.listDocuments(),
        repository.loadCompanyData(),
      ]);
      final rows = List<Map<String, dynamic>>.from(results[0] as List);
      final company = Map<String, dynamic>.from(results[1] as Map);
      if (!mounted) return;
      _companyName.text = company['name']?.toString() ?? '';
      _companyAddress.text = company['address']?.toString() ?? '';
      _corporateNumber.text = company['corporate_number']?.toString() ?? '';
      _companyPhone.text = company['phone']?.toString() ?? '';
      _companyFax.text = company['fax']?.toString() ?? '';
      _companyEmail.text = company['email']?.toString() ?? '';
      _bankName.text = company['bank_name']?.toString() ?? '';
      _bankBranch.text = company['bank_branch']?.toString() ?? '';
      _bankAccountNumber.text =
          company['bank_account_number']?.toString() ?? '';
      _bankAccountHolder.text =
          company['bank_account_holder']?.toString() ?? '';
      setState(() {
        _documents = rows;
        _selected.removeWhere(
          (id) => !rows.any((row) => row['id']?.toString() == id),
        );
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

  @override
  Widget build(BuildContext context) {
    SkoLanguageController.watch(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('会社データ'),
        actions: [
          IconButton(
            tooltip: '会社提出書類を送信',
            onPressed: _busy ? null : _openCommonSend,
            icon: const Icon(Icons.send_outlined),
          ),
          IconButton(
            tooltip: '書類種類を追加',
            onPressed: _busy ? null : _create,
            icon: const Icon(Icons.add_circle_outline),
          ),
          IconButton(
            tooltip: '再読み込み',
            onPressed: _busy ? null : _reload,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
            ? Center(child: Text(_error!, textAlign: TextAlign.center))
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _companyDataCard(),
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.approval_outlined),
                      title: Text(SkoLanguageController.tr('会社角印')),
                      subtitle: Text(SkoLanguageController.tr('会社角印のON／OFF')),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: _busy ? null : () => Navigator.of(context).push<void>(
                        MaterialPageRoute(builder: (_) => const CompanySealSettingsPage()),
                      ),
                    ),
                  ),
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.event_available_outlined),
                      title: Text(SkoLanguageController.tr('給与の締め日・給料日・確認者')),
                      subtitle: Text(SkoLanguageController.tr('会社共通の給与設定')),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: _busy
                          ? null
                          : () => Navigator.of(context).push<void>(
                              MaterialPageRoute(
                                builder: (_) =>
                                    const PayrollConfirmationSettingsPage(),
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Text(
                        '書類',
                        style: Theme.of(context).textTheme.titleLarge
                            ?.copyWith(fontWeight: FontWeight.w900),
                      ),
                      const Spacer(),
                      OutlinedButton.icon(
                        onPressed: _busy ? null : _create,
                        icon: const Icon(Icons.add_circle_outline),
                        label: const Text('追加'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (_documents.isEmpty)
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(18),
                        child: Text('会社提出書類はまだ登録されていません'),
                      ),
                    ),
                  for (final row in _documents) _documentCard(row),
                  if (false && _selected.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    Text(
                      '上位会社へ送信（' + _selected.length.toString() + '件）',
                      style: Theme.of(context).textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _receiveCode,
                      decoration: const InputDecoration(
                        labelText: '上位会社の受取コード',
                        prefixIcon: Icon(Icons.vpn_key_outlined),
                      ),
                      onChanged: (_) => setState(() => _targetCompany = null),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: _busy ? null : _resolveTarget,
                      icon: const Icon(Icons.verified_outlined),
                      label: const Text('送信先会社を確認'),
                    ),
                    if (_targetCompany != null)
                      ListTile(
                        leading: const Icon(Icons.business_outlined),
                        title: const Text('送信先'),
                        subtitle: Text(
                          _targetCompany!,
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ),
                    TextField(
                      controller: _note,
                      maxLines: 3,
                      maxLength: 2000,
                      decoration: const InputDecoration(labelText: '案内・メモ（任意）'),
                    ),
                    FilledButton.icon(
                      onPressed: _busy || _targetCompany == null
                          ? null
                          : _confirmSend,
                      icon: const Icon(Icons.send_outlined),
                      label: const Text('内容を確認して送信'),
                    ),
                  ],
                ],
              ),
      ),
    );
  }

  Widget _companyDataCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '会社情報',
              style: Theme.of(context).textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 12),
            _companyField(_companyName, '会社名'),
            _companyField(_companyAddress, '会社住所', maxLines: 2),
            _companyField(
              _corporateNumber,
              '法人番号（13桁）',
              keyboardType: TextInputType.number,
            ),
            _companyField(
              _companyPhone,
              '会社電話番号',
              keyboardType: TextInputType.phone,
            ),
            _companyField(
              _companyFax,
              '会社FAX番号',
              keyboardType: TextInputType.phone,
            ),
            _companyField(
              _companyEmail,
              'メールアドレス',
              keyboardType: TextInputType.emailAddress,
            ),
            const Divider(height: 26),
            _companyField(_bankName, '銀行名'),
            _companyField(_bankBranch, '支店名'),
            _companyField(
              _bankAccountNumber,
              '口座番号',
              keyboardType: TextInputType.number,
            ),
            _companyField(_bankAccountHolder, '口座名義'),
            const SizedBox(height: 6),
            FilledButton.icon(
              onPressed: _busy ? null : _saveCompanyData,
              icon: const Icon(Icons.save_outlined),
              label: const Text('会社データを保存'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _companyField(
    TextEditingController controller,
    String label, {
    int maxLines = 1,
    TextInputType? keyboardType,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: controller,
        maxLines: maxLines,
        keyboardType: keyboardType,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }

  Future<void> _saveCompanyData() async {
    final repository = _repository;
    if (repository == null || _busy) return;
    final corporate = _corporateNumber.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (corporate.isNotEmpty && corporate.length != 13) {
      setState(() => _error = '法人番号は13桁で入力してください。');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await repository.saveCompanyData(
        name: _companyName.text,
        address: _companyAddress.text,
        corporateNumber: corporate,
        phone: _companyPhone.text,
        fax: _companyFax.text,
        email: _companyEmail.text,
        bankName: _bankName.text,
        bankBranch: _bankBranch.text,
        bankAccountNumber: _bankAccountNumber.text,
        bankAccountHolder: _bankAccountHolder.text,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('会社データを保存しました')));
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = '会社データを保存できませんでした: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _documentCard(Map<String, dynamic> row) {
    final id = row['id']?.toString() ?? '';
    final path = row['attachment_path']?.toString() ?? '';
    final expires = row['expires_at']?.toString() ?? '';
    return Card(
      child: Column(
        children: [
          CheckboxListTile(
            value: _selected.contains(id),
            onChanged: path.isEmpty
                ? null
                : (value) => setState(() {
                    if (value == true) {
                      _selected.add(id);
                    } else {
                      _selected.remove(id);
                    }
                  }),
            title: Text(
              row['name']?.toString() ?? '会社提出書類',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            subtitle: Text(
              [
                path.isEmpty ? 'PDF・画像未登録' : '提出ファイル登録済み',
                if (expires.isNotEmpty) '有効期限 ' + expires,
                if ((row['notes']?.toString() ?? '').isNotEmpty)
                  row['notes'].toString(),
                ...DataDateLabels.labels(
                  createdAt: row['created_at'],
                  updatedAt: row['updated_at'],
                ),
              ].join(' / '),
            ),
            secondary: const Icon(Icons.business_center_outlined),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                OutlinedButton.icon(
                  onPressed: _busy ? null : () => _pickFile(row),
                  icon: const Icon(Icons.upload_file_outlined),
                  label: Text(path.isEmpty ? 'カメラ・写真・ファイル' : '書類を差替'),
                ),
                const SizedBox(width: 8),
                TextButton.icon(
                  onPressed: _busy ? null : () => _pickMultiplePhotos(row),
                  icon: const Icon(Icons.photo_library_outlined),
                  label: const Text('表裏写真'),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: _busy ? null : () => _edit(row),
                  child: const Text('編集'),
                ),
                IconButton(
                  tooltip: '無効化',
                  onPressed: _busy ? null : () => _archive(row),
                  icon: const Icon(Icons.archive_outlined),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _create() async {
    final draft = await _metadataDialog();
    if (draft == null || _repository == null) return;
    setState(() => _busy = true);
    try {
      await _repository.createDocument(
        name: draft.name,
        expiresAt: draft.expiresAt,
        notes: draft.notes,
      );
      await _load();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _edit(Map<String, dynamic> row) async {
    final draft = await _metadataDialog(row: row);
    if (draft == null || _repository == null) return;
    setState(() => _busy = true);
    try {
      await _repository.updateMetadata(
        id: row['id'].toString(),
        name: draft.name,
        expiresAt: draft.expiresAt,
        notes: draft.notes,
      );
      await _load();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<_DocumentDraft?> _metadataDialog({Map<String, dynamic>? row}) async {
    final name = TextEditingController(text: row?['name']?.toString() ?? '');
    final notes = TextEditingController(text: row?['notes']?.toString() ?? '');
    DateTime? expiresAt = _parseDate(row?['expires_at']);
    final result = await showDialog<_DocumentDraft>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(row == null ? '会社提出書類を追加' : '会社提出書類を編集'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: name,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: '書類種類 *',
                    hintText: '例：建設業許可証',
                  ),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('有効期限'),
                  subtitle: Text(
                    expiresAt == null ? '設定なし' : _formatDate(expiresAt!),
                  ),
                  trailing: const Icon(Icons.calendar_month_outlined),
                  onTap: () async {
                    final now = DateTime.now();
                    final picked = await showDatePicker(
                      context: dialogContext,
                      initialDate: expiresAt ?? now,
                      firstDate: DateTime(1950),
                      lastDate: DateTime(now.year + 30),
                    );
                    if (picked != null) {
                      setDialogState(() => expiresAt = picked);
                    }
                  },
                ),
                TextField(
                  controller: notes,
                  maxLines: 3,
                  decoration: const InputDecoration(labelText: 'メモ'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('キャンセル'),
            ),
            FilledButton(
              onPressed: () {
                if (name.text.trim().isEmpty) return;
                Navigator.pop(
                  dialogContext,
                  _DocumentDraft(
                    name: name.text.trim(),
                    expiresAt: expiresAt,
                    notes: notes.text.trim(),
                  ),
                );
              },
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
    name.dispose();
    notes.dispose();
    return result;
  }

  // Keep all selected sides in memory until the user confirms the set.
  // Existing server attachments are never overwritten by a second photo.
  Future<void> _pickMultiplePhotos(Map<String, dynamic> row) async {
    final photos = DocumentPhotoDraft<XFile>();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, refresh) => AlertDialog(
          title: const Text('書類の写真（表・裏）'),
          content: SizedBox(
            width: 340,
            child: SingleChildScrollView(
              child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < photos.length; i++)
                  ListTile(
                    leading: const Icon(Icons.image_outlined),
                    title: Text(i == 0 ? '表面' : i == 1 ? '裏面' : '追加写真 ${i - 1}'),
                    subtitle: Text(photos.photos[i].name, maxLines: 1, overflow: TextOverflow.ellipsis),
                    trailing: IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => refresh(() => photos.removeAt(i)),
                    ),
                    onTap: () async {
                      final bytes = await photos.photos[i].readAsBytes();
                      if (!context.mounted) return;
                      await showDialog<void>(
                        context: context,
                        builder: (previewContext) => AlertDialog(
                          content: Image.memory(bytes, fit: BoxFit.contain),
                          actions: [TextButton(
                            onPressed: () => Navigator.pop(previewContext),
                            child: const Text('閉じる'),
                          )],
                        ),
                      );
                    },
                  ),
                TextButton.icon(
                  onPressed: () async {
                    final picked = await _imagePicker.pickImage(
                      source: ImageSource.camera,
                      imageQuality: 90,
                      maxWidth: 2600,
                    );
                    if (picked != null && context.mounted) {
                      refresh(() => photos.add(picked));
                    }
                  },
                  icon: const Icon(Icons.add_a_photo_outlined),
                  label: const Text('写真を撮影して追加'),
                ),
                TextButton.icon(
                  onPressed: () async {
                    final picked = await _imagePicker.pickMultiImage(
                      imageQuality: 90,
                      maxWidth: 2600,
                    );
                    if (context.mounted && picked.isNotEmpty) {
                      refresh(() => photos.addAll(picked));
                    }
                  },
                  icon: const Icon(Icons.add_photo_alternate_outlined),
                  label: const Text('ライブラリから追加'),
                ),
                const Text('写真の保存方式を準備中です。ここでは既存の登録写真を変更しません。'),
              ],
              ),
            ),
          ),
          actions: [TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('閉じる'),
          )],
        ),
      ),
    );
  }

  Future<void> _pickFile(Map<String, dynamic> row) async {
    final source = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: const Text('カメラで撮影'),
              onTap: () => Navigator.pop(sheetContext, 'camera'),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('写真ライブラリから選択'),
              onTap: () => Navigator.pop(sheetContext, 'photo'),
            ),
            ListTile(
              leading: const Icon(Icons.upload_file_outlined),
              title: const Text('PDF・ファイルから選択'),
              onTap: () => Navigator.pop(sheetContext, 'file'),
            ),
          ],
        ),
      ),
    );
    if (source == null || !mounted) return;

    if (source == 'camera' || source == 'photo') {
      final image = await _imagePicker.pickImage(
        source: source == 'camera' ? ImageSource.camera : ImageSource.gallery,
        imageQuality: 90,
        maxWidth: 2600,
      );
      if (image == null) return;
      await _uploadDocumentBytes(
        row: row,
        bytes: await image.readAsBytes(),
        filename: image.name,
        contentType: image.mimeType ?? 'image/jpeg',
      );
      return;
    }

    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png', 'heic', 'heif'],
    );
    if (file == null) return;
    await _uploadDocumentBytes(
      row: row,
      bytes: await file.readAsBytes(),
      filename: file.name,
      contentType: _contentType(file.extension),
    );
  }

  Future<void> _uploadDocumentBytes({
    required Map<String, dynamic> row,
    required List<int> bytes,
    required String filename,
    required String contentType,
  }) async {
    final repository = _repository;
    if (repository == null) return;
    setState(() => _busy = true);
    try {
      await repository.upload(
        id: row['id'].toString(),
        bytes: Uint8List.fromList(bytes),
        filename: filename,
        contentType: contentType,
      );
      await _load();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _archive(Map<String, dynamic> row) async {
    if (_repository == null) return;
    final name = row['name']?.toString() ?? '会社提出書類';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('会社提出書類を無効化'),
        content: Text(name + 'を一覧から外します。履歴・送信済みデータは削除しません。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('戻る'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('無効化'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _busy = true);
    try {
      await _repository.archive(row['id'].toString());
      await _load();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resolveTarget() async {
    final exchange = _exchange;
    if (exchange == null || _receiveCode.text.trim().isEmpty) return;
    final row = await exchange.resolveReceiveCode(_receiveCode.text);
    if (!mounted) return;
    setState(() => _targetCompany = row['company_name']?.toString());
  }

  Future<void> _confirmSend() async {
    final exchange = _exchange;
    final target = _targetCompany;
    if (exchange == null || target == null) return;
    final selectedRows = _documents
        .where((row) => _selected.contains(row['id']?.toString()))
        .toList(growable: false);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('送信内容の最終確認'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('送信先: ' + target),
              const SizedBox(height: 8),
              for (final row in selectedRows)
                Text('・' + (row['name']?.toString() ?? '会社提出書類')),
              const SizedBox(height: 12),
              const Text('会社提出書類として、出所会社を保持したまま上位会社へ送信します。'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('戻る'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('この内容で送信'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _busy = true);
    try {
      await exchange.send(
        requestId: _requestId(),
        receiveCode: _receiveCode.text,
        items: [
          for (final row in selectedRows)
            {'id': row['id'].toString(), 'kind': 'company'},
        ],
        note: _note.text,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(target + 'へ会社提出書類を送信しました')));
      setState(() {
        _selected.clear();
        _targetCompany = null;
      });
      _receiveCode.clear();
      _note.clear();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _reload() {
    setState(() => _loading = true);
    _load();
  }

  DateTime? _parseDate(Object? value) {
    final text = value?.toString();
    return text == null || text.isEmpty ? null : DateTime.tryParse(text);
  }

  String _formatDate(DateTime value) {
    return value.year.toString() +
        '/' +
        value.month.toString().padLeft(2, '0') +
        '/' +
        value.day.toString().padLeft(2, '0');
  }

  String _contentType(String? extension) {
    return switch (extension?.toLowerCase()) {
      'pdf' => 'application/pdf',
      'png' => 'image/png',
      'heic' => 'image/heic',
      'heif' => 'image/heif',
      _ => 'image/jpeg',
    };
  }

  String _requestId() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes
        .map((value) => value.toRadixString(16).padLeft(2, '0'))
        .join();
    return hex.substring(0, 8) +
        '-' +
        hex.substring(8, 12) +
        '-' +
        hex.substring(12, 16) +
        '-' +
        hex.substring(16, 20) +
        '-' +
        hex.substring(20);
  }
}

class _DocumentDraft {
  const _DocumentDraft({
    required this.name,
    required this.expiresAt,
    required this.notes,
  });

  final String name;
  final DateTime? expiresAt;
  final String notes;
}
