// ignore_for_file: prefer_interpolation_to_compose_strings

import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'vehicle_route_repository.dart';

class VehicleEditorPage extends StatefulWidget {
  const VehicleEditorPage({
    super.key,
    this.vehicle,
  });

  final Map<String, dynamic>? vehicle;

  @override
  State<VehicleEditorPage> createState() => _VehicleEditorPageState();
}

class _VehicleEditorPageState extends State<VehicleEditorPage> {
  final _repository = VehicleRouteRepository.maybeCreate();
  final _picker = ImagePicker();

  late final TextEditingController _name;
  late final TextEditingController _registration;
  late final TextEditingController _odometer;
  late final TextEditingController _storageAddress;

  _PendingDocument? _registrationDoc;
  _PendingDocument? _compulsoryDoc;
  _PendingDocument? _voluntaryDoc;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final row = widget.vehicle;
    _name = TextEditingController(
      text: row?['display_name']?.toString() ?? '',
    );
    _registration = TextEditingController(
      text: row?['registration_number']?.toString() ?? '',
    );
    _odometer = TextEditingController(
      text: _number(row?['odometer_km']),
    );
    _storageAddress = TextEditingController(
      text: row?['storage_address']?.toString() ?? '',
    );
  }

  @override
  void dispose() {
    _name.dispose();
    _registration.dispose();
    _odometer.dispose();
    _storageAddress.dispose();
    super.dispose();
  }

  Future<_PendingDocument?> _pickDocument(String title) async {
    final source = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.picture_as_pdf_outlined),
              title: const Text('PDF・ファイルから選ぶ'),
              onTap: () => Navigator.pop(context, 'file'),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('写真ライブラリから選ぶ'),
              onTap: () => Navigator.pop(context, 'gallery'),
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: const Text('カメラで撮影'),
              onTap: () => Navigator.pop(context, 'camera'),
            ),
          ],
        ),
      ),
    );
    if (source == null) return null;

    if (source == 'gallery') {
      final image = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 92,
        maxWidth: 2400,
      );
      if (image == null) return null;
      return _PendingDocument(
        bytes: await image.readAsBytes(),
        filename: image.name,
        contentType: image.mimeType ?? 'image/jpeg',
      );
    }

    if (source == 'camera') {
      final image = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 88,
        maxWidth: 2400,
      );
      if (image == null) return null;
      return _PendingDocument(
        bytes: await image.readAsBytes(),
        filename: image.name,
        contentType: image.mimeType ?? 'image/jpeg',
      );
    }

    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const [
        'pdf',
        'jpg',
        'jpeg',
        'png',
        'heic',
        'heif',
      ],
    );
    if (file == null) return null;
    return _PendingDocument(
      bytes: await file.readAsBytes(),
      filename: file.name,
      contentType: _contentType(file.extension),
    );
  }

  Future<void> _save() async {
    final repository = _repository;
    if (repository == null || _saving) return;

    final odometer = double.tryParse(_odometer.text.trim());
    if (_name.text.trim().isEmpty ||
        _registration.text.trim().isEmpty ||
        odometer == null ||
        odometer < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('表示名・車両番号・走行距離を確認してください'),
        ),
      );
      return;
    }

    final row = widget.vehicle;
    final registrationReady = _registrationDoc != null ||
        (row?['registration_document_path']?.toString().isNotEmpty == true);
    final compulsoryReady = _compulsoryDoc != null ||
        (row?['compulsory_insurance_path']?.toString().isNotEmpty == true);
    final voluntaryReady = _voluntaryDoc != null ||
        (row?['voluntary_insurance_path']?.toString().isNotEmpty == true);
    final missingLabels = <String>[
      if (!registrationReady) '車検証',
      if (!compulsoryReady) '自賠責保険',
      if (!voluntaryReady) '任意保険証書',
    ];

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(widget.vehicle == null ? '車両を登録しますか？' : '車両を更新しますか？'),
        content: Text(
          _name.text.trim() +
              ' / ' +
              _registration.text.trim() +
              ' / ' +
              _odometer.text.trim() +
              ' km' +
              (missingLabels.isEmpty
                  ? ''
                  : '\n未登録書類は後から追加できます：' +
                      missingLabels.join('・')),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('戻る'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('確定して保存'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _saving = true);
    try {
      final vehicleId = await repository.saveVehicle(
        id: widget.vehicle?['id']?.toString(),
        name: _name.text,
        registrationNumber: _registration.text,
        odometerKm: odometer,
        storageAddress: _storageAddress.text,
      );

      for (final entry in <(String, _PendingDocument?)>[
        ('registration', _registrationDoc),
        ('compulsory', _compulsoryDoc),
        ('voluntary', _voluntaryDoc),
      ]) {
        final document = entry.$2;
        if (document == null) continue;
        await repository.uploadVehicleDocument(
          vehicleId: vehicleId,
          kind: entry.$1,
          bytes: document.bytes,
          filename: document.filename,
          contentType: document.contentType,
        );
      }

      final missingAfterSave =
          await repository.notifyMissingVehicleDocuments(vehicleId);
      if (!mounted) return;
      if (missingAfterSave.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '車両を登録しました。未登録書類は後から追加してください：' +
                  missingAfterSave.join('・'),
            ),
          ),
        );
      }
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('車両を保存できませんでした: ' + error.toString())),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final row = widget.vehicle;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.vehicle == null ? '車両を登録' : '車両を変更'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          TextField(
            controller: _name,
            decoration: const InputDecoration(
              labelText: '表示名',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _registration,
            decoration: const InputDecoration(
              labelText: '車両番号',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _odometer,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: '走行距離',
              suffixText: 'km',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _storageAddress,
            decoration: const InputDecoration(
              labelText: '保管場所（駐車場の住所）',
              hintText: '例：東京都墨田区○○1-2-3',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 18),
          const Text(
            '車両書類',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            '書類は車両登録後に追加しても大丈夫です。未登録がある場合は管理者・サブ管理者へ通知します。',
          ),
          const SizedBox(height: 8),
          _documentTile(
            title: '車検証',
            existing: row?['registration_document_path'],
            pending: _registrationDoc,
            onPick: () async {
              final value = await _pickDocument('車検証');
              if (value != null && mounted) {
                setState(() => _registrationDoc = value);
              }
            },
          ),
          _documentTile(
            title: '自賠責保険',
            existing: row?['compulsory_insurance_path'],
            pending: _compulsoryDoc,
            onPick: () async {
              final value = await _pickDocument('自賠責保険');
              if (value != null && mounted) {
                setState(() => _compulsoryDoc = value);
              }
            },
          ),
          _documentTile(
            title: '任意保険証書',
            existing: row?['voluntary_insurance_path'],
            pending: _voluntaryDoc,
            onPick: () async {
              final value = await _pickDocument('任意保険証書');
              if (value != null && mounted) {
                setState(() => _voluntaryDoc = value);
              }
            },
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: const Icon(Icons.save_outlined),
            label: Text(_saving ? '保存中…' : '確定して保存'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
            ),
          ),
        ],
      ),
    );
  }

  Widget _documentTile({
    required String title,
    required Object? existing,
    required _PendingDocument? pending,
    required Future<void> Function() onPick,
  }) {
    final hasExisting = (existing?.toString() ?? '').isNotEmpty;
    final status = pending != null
        ? '今回登録: ' + pending.filename
        : hasExisting
            ? '登録済み'
            : '未登録';

    return Card(
      child: ListTile(
        leading: const Icon(Icons.description_outlined),
        title: Text(title),
        subtitle: Text(status),
        trailing: OutlinedButton.icon(
          onPressed: _saving ? null : onPick,
          icon: const Icon(Icons.upload_file_outlined),
          label: const Text('登録'),
        ),
      ),
    );
  }

  String _number(Object? value) {
    final number = (value as num?)?.toDouble() ??
        double.tryParse(value?.toString() ?? '') ??
        0;
    if (number == number.roundToDouble()) return number.toInt().toString();
    return number.toStringAsFixed(1);
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
}

class _PendingDocument {
  const _PendingDocument({
    required this.bytes,
    required this.filename,
    required this.contentType,
  });

  final Uint8List bytes;
  final String filename;
  final String contentType;
}
