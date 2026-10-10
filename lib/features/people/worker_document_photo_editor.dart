import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'worker_document_photos.dart';

/// The editor only builds a draft. Cancelling never uploads or changes a row.
Future<List<WorkerDocumentPhoto>?> editWorkerDocumentPhotos(
  BuildContext context, {
  required List<String> paths,
  required Future<String> Function(String) signedUrl,
  bool canEdit = true,
}) => showDialog<List<WorkerDocumentPhoto>>(
  context: context,
  builder: (_) =>
      _PhotoEditor(paths: paths, signedUrl: signedUrl, canEdit: canEdit),
);

class _PhotoEditor extends StatefulWidget {
  const _PhotoEditor({
    required this.paths,
    required this.signedUrl,
    required this.canEdit,
  });
  final List<String> paths;
  final bool canEdit;
  final Future<String> Function(String) signedUrl;
  @override
  State<_PhotoEditor> createState() => _PhotoEditorState();
}

class _PhotoEditorState extends State<_PhotoEditor> {
  late final _photos = widget.paths.map(WorkerDocumentPhoto.saved).toList();
  final _picker = ImagePicker();
  final _urls = <String, Future<String>>{};
  bool _busy = false;
  String? _error;

  Future<void> _pick({bool camera = false, int? replace}) async {
    if (!widget.canEdit) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final List<XFile> files;
      if (camera || replace != null) {
        final file = await _picker.pickImage(
          source: camera ? ImageSource.camera : ImageSource.gallery,
          imageQuality: 88,
          maxWidth: 2400,
        );
        files = file == null ? [] : [file];
      } else {
        files = await _picker.pickMultiImage(imageQuality: 88, maxWidth: 2400);
      }
      final added = <WorkerDocumentPhoto>[];
      for (final file in files) {
        added.add(
          WorkerDocumentPhoto.pending(await file.readAsBytes(), file.name),
        );
      }
      if (!mounted) return;
      if (_photos.length +
              added.length -
              (replace != null && added.isNotEmpty ? 1 : 0) >
          20) {
        throw StateError('写真は20枚以内で選択してください。');
      }
      setState(() {
        if (replace != null && added.isNotEmpty) {
          _photos[replace] = added.single;
        } else {
          _photos.addAll(added);
        }
      });
    } catch (error) {
      if (mounted) setState(() => _error = '写真を選択できませんでした: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _image(WorkerDocumentPhoto photo, {double height = 120}) {
    if (photo.bytes != null) {
      return Image.memory(
        photo.bytes!,
        height: height,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => const Text('写真を表示できません。'),
      );
    }
    final path = photo.path!;
    if (path.toLowerCase().endsWith('.pdf')) {
      return const Text('PDF（写真プレビュー対象外）');
    }
    return FutureBuilder<String>(
      future: _urls.putIfAbsent(path, () => widget.signedUrl(path)),
      builder: (_, snapshot) {
        if (snapshot.hasError) return const Text('写真を読み込めません。');
        if (!snapshot.hasData) return const LinearProgressIndicator();
        return Image.network(
          snapshot.data!,
          height: height,
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => const Text('写真を表示できません。'),
        );
      },
    );
  }

  void _preview(WorkerDocumentPhoto photo) {
    showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: InteractiveViewer(child: _image(photo, height: 500)),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('閉じる'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('登録写真 ${_photos.length}枚'),
    content: SizedBox(
      width: 420,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('1枚目：表面 / 2枚目：裏面 / 3枚目以降：追加写真'),
            if (!widget.canEdit) const Text('複数写真の保存準備中です。保存済みの写真は確認できます。'),
            const Text(
              '新しい写真の送信は、会社が試験登録を許可した運転免許証に限られます。その他の書類は送信停止中です。保存済み写真は確認できます。',
            ),
            const SizedBox(height: 8),
            for (var i = 0; i < _photos.length; i++)
              Card(
                child: Column(
                  children: [
                    InkWell(
                      onTap: () => _preview(_photos[i]),
                      child: _image(_photos[i]),
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${i + 1}枚目${_photos[i].path == null ? '（未保存）' : ''}',
                          ),
                        ),
                        IconButton(
                          tooltip: '前へ',
                          onPressed: _busy || !widget.canEdit || i == 0
                              ? null
                              : () => setState(() {
                                  final photo = _photos.removeAt(i);
                                  _photos.insert(i - 1, photo);
                                }),
                          icon: const Icon(Icons.arrow_upward),
                        ),
                        IconButton(
                          tooltip: '差し替え',
                          onPressed: _busy || !widget.canEdit
                              ? null
                              : () => _pick(replace: i),
                          icon: const Icon(Icons.edit_outlined),
                        ),
                        IconButton(
                          tooltip: '写真を一覧から削除',
                          onPressed: _busy || !widget.canEdit
                              ? null
                              : () => setState(() => _photos.removeAt(i)),
                          icon: const Icon(Icons.delete_outline),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            Wrap(
              spacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: _busy || !widget.canEdit
                      ? null
                      : () => _pick(camera: true),
                  icon: const Icon(Icons.camera_alt_outlined),
                  label: const Text('1枚撮影'),
                ),
                OutlinedButton.icon(
                  onPressed: _busy || !widget.canEdit ? null : () => _pick(),
                  icon: const Icon(Icons.photo_library_outlined),
                  label: const Text('複数選択'),
                ),
              ],
            ),
            if (_busy) const LinearProgressIndicator(),
            if (_error != null)
              Text(_error!, style: const TextStyle(color: Colors.red)),
            const Text('保存した写真は履歴に保持されます。変更は確定後に反映します。'),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: _busy ? null : () => Navigator.pop(context),
        child: Text(widget.canEdit ? 'キャンセル' : '閉じる'),
      ),
      if (widget.canEdit)
        FilledButton(
          onPressed: _busy || !widget.canEdit
              ? null
              : () => Navigator.pop(
                  context,
                  List<WorkerDocumentPhoto>.of(_photos),
                ),
          child: const Text('写真を確定'),
        ),
    ],
  );
}
