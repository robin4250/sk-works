import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../domain/company_seal_image_processing.dart';
import '../../domain/company_uploaded_seal_png.dart';
import 'company_seal_image_import.dart';

/// Returns a local candidate only. Registration and selection remain explicit
/// actions in the parent settings page after the common document preview.
class CompanySealImageEditorPage extends StatefulWidget {
  const CompanySealImageEditorPage({super.key, required this.input,
    required this.canEdit});
  final SealImportInput input;
  final Future<bool> Function() canEdit;
  @override
  State<CompanySealImageEditorPage> createState() => _CompanySealImageEditorPageState();
}

class _CompanySealImageEditorPageState extends State<CompanySealImageEditorPage> {
  SealImportFrame? _original;
  SealImportFrame? _frame;
  CompanyUploadedSealPng? _candidate;
  Rect _crop = const Rect.fromLTRB(0, 0, 1, 1);
  Offset? _start;
  int _page = 0, _generation = 0;
  bool _busy = false, _removeWhite = true, _preserveRed = true;
  double _whiteFloor = 245;
  String? _error;

  @override
  void initState() {
    super.initState();
    _removeWhite = !widget.input.name.toLowerCase().endsWith('.png');
    _load(0);
  }
  @override
  void dispose() { _generation++; super.dispose(); }
  Future<bool> _allowed() async {
    final allowed = await widget.canEdit();
    if (!mounted) { return false; }
    if (!allowed) { setState(() => _error = '角印の画像編集は現在利用できません。'); }
    return allowed;
  }
  Future<void> _load(int page) async {
    final generation = ++_generation;
    setState(() { _busy = true; _error = null; });
    try {
      if (!await _allowed()) { return; }
      final frame = await CompanySealImageImport.decode(widget.input, pdfPage: page);
      final allowed = await _allowed();
      if (!mounted || generation != _generation || !allowed) { return; }
      setState(() {
        _original = frame; _frame = frame; _page = page;
        _crop = const Rect.fromLTRB(0, 0, 1, 1); _candidate = null;
      });
    } catch (error) {
      if (mounted && generation == _generation) { setState(() => _error = '$error'); }
    } finally {
      if (mounted && generation == _generation) { setState(() => _busy = false); }
    }
  }
  Future<void> _rotate() async {
    final frame = _frame;
    if (frame == null || !await _allowed()) { return; }
    final generation = ++_generation;
    setState(() => _busy = true);
    try {
      final rotated = rotateCompanySealImage(frame.image, 1);
      final png = await CompanySealImageImport.encode(rotated);
      final allowed = await _allowed();
      if (!mounted || generation != _generation || !allowed) { return; }
      setState(() {
        _frame = SealImportFrame(image: rotated, previewPng: png);
        _crop = const Rect.fromLTRB(0, 0, 1, 1); _candidate = null;
      });
    } catch (error) {
      if (mounted && generation == _generation) { setState(() => _error = '$error'); }
    } finally {
      if (mounted && generation == _generation) { setState(() => _busy = false); }
    }
  }
  Future<void> _prepare() async {
    final frame = _frame;
    if (frame == null || !await _allowed()) { return; }
    final generation = ++_generation;
    setState(() { _busy = true; _error = null; });
    try {
      final image = frame.image;
      final crop = SealPixelCrop((_crop.left * image.width).floor(),
        (_crop.top * image.height).floor(), (_crop.right * image.width).ceil(),
        (_crop.bottom * image.height).ceil());
      final png = await CompanySealImageImport.prepare(image, crop,
        options: SealImageOptions(removeWhite: _removeWhite,
          whiteFloor: _whiteFloor.round(), preservePaleRed: _preserveRed));
      final allowed = await _allowed();
      if (!mounted || generation != _generation || !allowed) { return; }
      setState(() => _candidate = png);
    } catch (error) {
      if (mounted && generation == _generation) { setState(() => _error = '$error'); }
    } finally {
      if (mounted && generation == _generation) { setState(() => _busy = false); }
    }
  }
  void _invalidate(VoidCallback change) {
    setState(() { change(); _candidate = null; _error = null; });
  }
  Offset _point(Offset position, Size size) => Offset(
    (position.dx / size.width).clamp(0.0, 1.0),
    (position.dy / size.height).clamp(0.0, 1.0));

  @override
  Widget build(BuildContext context) {
    final frame = _frame;
    return Scaffold(appBar: AppBar(title: const Text('角印を切り抜いてPNG化')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        const Text('印影だけをドラッグして囲んでください。元の写真は変更されません。この画面では保存しません。'),
        if (widget.input.isPdf) Row(children: [
          IconButton(onPressed: _busy || _page == 0 ? null : () => _load(_page - 1), icon: const Icon(Icons.chevron_left)),
          Text('${_page + 1}ページ目'),
          IconButton(onPressed: _busy || _page + 1 >= CompanySealImageImport.maxPdfPages ? null : () => _load(_page + 1), icon: const Icon(Icons.chevron_right)),
          const Expanded(child: Text('表示したページだけを画像化します。最大20ページ目まで。')),
        ]),
        if (_busy) const LinearProgressIndicator(),
        if (_error != null) Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
        if (frame != null) Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 600),
          child: AspectRatio(aspectRatio: frame.image.width / frame.image.height,
            child: LayoutBuilder(builder: (context, box) {
              final size = Size(box.maxWidth, box.maxHeight);
              return GestureDetector(
                onPanStart: _busy ? null : (details) {
                  _start = _point(details.localPosition, size);
                  _invalidate(() => _crop = Rect.fromPoints(_start!, _start!));
                },
                onPanUpdate: _busy ? null : (details) {
                  final start = _start;
                  if (start != null) { _invalidate(() => _crop = Rect.fromPoints(start, _point(details.localPosition, size))); }
                },
                child: Stack(fit: StackFit.expand, children: [
                  Image.memory(frame.previewPng, fit: BoxFit.fill, gaplessPlayback: true),
                  Positioned(left: _crop.left * size.width, top: _crop.top * size.height,
                    width: math.max(1.0, _crop.width * size.width), height: math.max(1.0, _crop.height * size.height),
                    child: IgnorePointer(child: DecoratedBox(decoration: BoxDecoration(border: Border.all(color: Colors.blue, width: 2))))),
                ]));
            })))),
        Wrap(spacing: 8, children: [
          TextButton(onPressed: _busy || frame == null ? null : _rotate, child: const Text('90度回転')),
          TextButton(onPressed: _busy || _original == null ? null : () => _invalidate(() {
            _frame = _original; _crop = const Rect.fromLTRB(0, 0, 1, 1);
            _whiteFloor = 245; _preserveRed = true;
            _removeWhite = !widget.input.name.toLowerCase().endsWith('.png');
          }), child: const Text('このページの元画像に戻す')),
        ]),
        SwitchListTile(title: const Text('白い背景を透明にする'), value: _removeWhite,
          onChanged: _busy ? null : (value) => _invalidate(() => _removeWhite = value)),
        if (_removeWhite) ...[
          const Text('白背景の調整（薄い印影を確認しながら調整してください）'),
          Slider(min: 180, max: 255, divisions: 75, value: _whiteFloor,
            label: '${_whiteFloor.round()}', onChanged: _busy ? null : (value) => _invalidate(() => _whiteFloor = value)),
          SwitchListTile(title: const Text('薄い赤の線を残す'), value: _preserveRed,
            onChanged: _busy ? null : (value) => _invalidate(() => _preserveRed = value)),
        ],
        FilledButton(onPressed: _busy || frame == null ? null : _prepare, child: const Text('選んだ範囲をPNG化')),
        if (_candidate case final candidate?) ...[
          const SizedBox(height: 12),
          const Text('1024×1024 PNG・帳票上の角印サイズは共通設定のままです。線や余白を確認してください。'),
          Center(child: SizedBox(width: 260, height: 260, child: CustomPaint(painter: _CheckerPainter(),
            child: Image.memory(candidate.bytes, fit: BoxFit.contain)))),
          FilledButton(onPressed: _busy ? null : () async {
            final allowed = await _allowed();
            if (!context.mounted || !allowed || _candidate != candidate) { return; }
            Navigator.of(context).pop(candidate);
          }, child: const Text('このPNGを追加候補にする（まだ保存しない）')),
        ],
      ]));
  }
}
class _CheckerPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    const cell = 12.0;
    for (var y = 0; y < (size.height / cell).ceil(); y++) {
      for (var x = 0; x < (size.width / cell).ceil(); x++) {
        canvas.drawRect(Rect.fromLTWH(x * cell, y * cell, cell, cell), Paint()
          ..color = (x + y).isEven ? Colors.white : const Color(0xffdddddd));
      }
    }
  }
  @override
  bool shouldRepaint(covariant _CheckerPainter oldDelegate) => false;
}
