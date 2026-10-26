import 'package:flutter/material.dart';
import '../../widgets/sko_orientation_policy.dart';

class SignatureResult {
  const SignatureResult({
    required this.signerName,
    required this.strokes,
    this.canvasSize,
  });

  final String signerName;
  final List<List<Offset>> strokes;
  final Size? canvasSize;

  Object toJson() => [
        for (final stroke in strokes)
          [
            for (final point in stroke)
              {
                'x': point.dx,
                'y': point.dy,
                if (canvasSize != null) 'canvas_width': canvasSize!.width,
                if (canvasSize != null) 'canvas_height': canvasSize!.height,
              }
          ]
      ];

  static List<List<Offset>> fromJson(Object? value) {
    final rawValue = value is Map ? value['strokes'] : value;
    if (rawValue is! List) { return const []; }
    final strokes = <List<Offset>>[];
    for (final rawStroke in rawValue) {
      if (rawStroke is! List) { continue; }
      final points = <Offset>[];
      for (final rawPoint in rawStroke) {
        if (rawPoint is! Map) { continue; }
        final x = (rawPoint['x'] as num?)?.toDouble();
        final y = (rawPoint['y'] as num?)?.toDouble();
        if (x == null || y == null) { continue; }
        points.add(Offset(x, y));
      }
      if (points.isNotEmpty) { strokes.add(points); }
    }
    return strokes;
  }

  // Point metadata survives existing RPCs which wrap the stroke list unchanged.
  // Legacy normalized strokes have no recoverable capture dimensions.
  static Size? sizeFromJson(Object? value) {
    final strokes = value is Map ? value['strokes'] : value;
    if (strokes is! List) { return null; }
    for (final stroke in strokes) {
      if (stroke is! List) { continue; }
      for (final point in stroke) {
        if (point is! Map) { continue; }
        final width = point['canvas_width'];
        final height = point['canvas_height'];
        if (width is num && height is num && width.isFinite && height.isFinite && width > 0 && height > 0) {
          return Size(width.toDouble(), height.toDouble());
        }
      }
    }
    return null;
  }
}

class SignatureCapturePage extends StatefulWidget {
  const SignatureCapturePage({
    super.key,
    this.title = '責任者サイン',
    this.signerLabel = '現場責任者名',
    this.submitLabel = 'サインを確定',
    this.initialSignerName = '',
    this.signerNameOptions = const [],
    this.reviewText,
  });

  final String title;
  final String signerLabel;
  final String submitLabel;
  final String initialSignerName;
  final List<String> signerNameOptions;
  final String? reviewText;

  @override
  State<SignatureCapturePage> createState() => _SignatureCapturePageState();
}

class _SignatureCapturePageState extends State<SignatureCapturePage> {
  final _signer = TextEditingController();
  final _strokes = <List<Offset>>[];
  Size _canvasSize = Size.zero;
  Size? _captureSize;
  bool _landscape = false;
  bool _strokeActive = false;

  @override
  void initState() {
    super.initState();
    _signer.text = widget.initialSignerName;
    SkoOrientationPolicy.enterSignature();
  }

  @override
  void dispose() {
    _signer.dispose();
    SkoOrientationPolicy.leaveSignature();
    super.dispose();
  }

  void _startStroke(DragStartDetails details) {
    if (!_landscape || _canvasSize.width <= 0 || _canvasSize.height <= 0) { return; }
    FocusManager.instance.primaryFocus?.unfocus();
    _strokeActive = true;
    setState(() {
      _captureSize ??= _canvasSize;
      _strokes.add([
        Offset(
          (details.localPosition.dx / _canvasSize.width).clamp(0, 1),
          (details.localPosition.dy / _canvasSize.height).clamp(0, 1),
        ),
      ]);
    });
  }

  void _addPoint(DragUpdateDetails details) {
    if (!_landscape || !_strokeActive || _strokes.isEmpty || _canvasSize.width <= 0 || _canvasSize.height <= 0) {
      return;
    }
    setState(() {
      _strokes.last.add(
        Offset(
          (details.localPosition.dx / _canvasSize.width).clamp(0, 1),
          (details.localPosition.dy / _canvasSize.height).clamp(0, 1),
        ),
      );
    });
  }

  void _submit() {
    if (!_landscape) { return; }
    if (_signer.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${widget.signerLabel}を入力してください')),
      );
      return;
    }
    if (_strokes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('サインを入力してください')),
      );
      return;
    }

    Navigator.of(context).pop(
      SignatureResult(
        signerName: _signer.text.trim(),
        canvasSize: _captureSize,
        strokes: [
          for (final stroke in _strokes) List<Offset>.from(stroke),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Flutter's viewport follows either landscape direction on phones/tablets.
    // A flat/locked portrait viewport stays blocked; handwriting is not guessed.
    _landscape = MediaQuery.orientationOf(context) == Orientation.landscape;
    if (!_landscape) { _strokeActive = false; }
    final hasOptions = widget.signerNameOptions.any((name) => name.trim().isNotEmpty);
    final picker = DropdownButtonFormField<String>(
      key: const ValueKey('signature-member-picker'),
      decoration: const InputDecoration(labelText: '出勤メンバーから選択', isDense: true),
      items: [for (final name in widget.signerNameOptions.map((name) => name.trim()).where((name) => name.isNotEmpty).toSet())
        DropdownMenuItem(value: name, child: Text(name))],
      onChanged: (name) { if (name != null) { _signer.text = name; } },
    );
    final nameField = TextField(controller: _signer,
      decoration: InputDecoration(labelText: widget.signerLabel,
        prefixIcon: const Icon(Icons.person_outline), isDense: true));
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.title,
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        actions: [
          if (widget.reviewText != null) IconButton(
            tooltip: 'サインする日報を確認', icon: const Icon(Icons.description_outlined),
            onPressed: () => showDialog<void>(context: context, builder: (dialogContext) => AlertDialog(
              title: const Text('サインする日報'),
              content: SingleChildScrollView(child: Text(widget.reviewText!)),
              actions: [TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('閉じる'))]))),
          TextButton(
            onPressed: _strokes.isEmpty
                ? null
                : () => setState(() { _strokes.clear(); _captureSize = null; _strokeActive = false; }),
            child: const Text('消去'),
          ),
        ],
      ),
      body: SafeArea(child: LayoutBuilder(builder: (context, bodyConstraints) => Column(
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: bodyConstraints.maxHeight * .35),
            child: SingleChildScrollView(child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: _landscape && hasOptions
                ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(child: picker), const SizedBox(width: 16), Expanded(child: nameField)])
                : Column(children: [if (hasOptions) ...[picker, const SizedBox(height: 12)], nameField]),
            )),
          ),
          Expanded(child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: LayoutBuilder(builder: (context, constraints) {
              final available = Size(constraints.maxWidth, constraints.maxHeight);
              final fitted = _captureSize == null ? available
                : applyBoxFit(BoxFit.contain, _captureSize!, available).destination;
              _canvasSize = fitted;
              return Stack(fit: StackFit.expand, children: [
                Center(child: SizedBox(width: fitted.width, height: fitted.height,
                  child: GestureDetector(
                    key: const ValueKey('signature-drawing-surface'),
                    behavior: HitTestBehavior.opaque,
                    onPanStart: _landscape ? _startStroke : null,
                    onPanUpdate: _landscape ? _addPoint : null,
                    onPanEnd: _landscape ? (_) { _strokeActive = false; } : null,
                    onPanCancel: _landscape ? () { _strokeActive = false; } : null,
                    child: Container(
                      decoration: BoxDecoration(color: Colors.white,
                        borderRadius: BorderRadius.circular(18)),
                      foregroundDecoration: BoxDecoration(
                        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                        borderRadius: BorderRadius.circular(18)),
                      child: CustomPaint(painter: SignaturePainter(strokes: _strokes,
                        canvasSize: _captureSize ?? _canvasSize)),
                    ),
                  ),
                )),
                if (!_landscape) const Positioned.fill(child: IgnorePointer(child: SignatureOrientationGuide())),
              ]);
            }),
          )),
          Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: FilledButton.icon(onPressed: _landscape ? _submit : null,
              icon: const Icon(Icons.check_circle_outline), label: Text(widget.submitLabel))),
        ],
      ))),
    );
  }
}

/// Portrait-only direction marks use the current screen's upright coordinates.
class SignatureOrientationGuide extends StatelessWidget {
  const SignatureOrientationGuide({super.key});
  @override
  Widget build(BuildContext context) => Container(
    key: const ValueKey('signature-orientation-guide'),
    decoration: BoxDecoration(color: Colors.white.withValues(alpha: .94),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: Theme.of(context).colorScheme.primary, width: 2)),
    child: Stack(children: [
      const Align(alignment: Alignment.topCenter, child: Padding(
        padding: EdgeInsets.all(8), child: Text('↑ 上', style: TextStyle(fontWeight: FontWeight.bold)))),
      const Align(alignment: Alignment.bottomCenter, child: Padding(
        padding: EdgeInsets.all(8), child: Text('下 ↓', style: TextStyle(fontWeight: FontWeight.bold)))),
      const Align(alignment: Alignment.centerLeft, child: Padding(
        padding: EdgeInsets.all(8), child: Text('← 左', style: TextStyle(fontWeight: FontWeight.bold)))),
      const Align(alignment: Alignment.centerRight, child: Padding(
        padding: EdgeInsets.all(8), child: Text('右 →', style: TextStyle(fontWeight: FontWeight.bold)))),
      Positioned.fill(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 60, vertical: 40),
        child: Center(child: FittedBox(fit: BoxFit.scaleDown,
          child: SizedBox(width: 260, child: Text('横向きにしてサインしてください',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 32, fontWeight: FontWeight.w800,
              color: Theme.of(context).colorScheme.primary))))))),
    ]),
  );
}

class SignaturePreview extends StatelessWidget {
  const SignaturePreview({
    super.key,
    required this.strokes,
    this.height = 120,
    this.canvasSize,
  });

  final List<List<Offset>> strokes;
  final double height;
  final Size? canvasSize;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(12),
      ),
      child: CustomPaint(
        painter: SignaturePainter(strokes: strokes, canvasSize: canvasSize, fitInk: true),
        size: Size.infinite,
      ),
    );
  }
}

class SignaturePainter extends CustomPainter {
  const SignaturePainter({required this.strokes, this.canvasSize, this.fitInk = false});

  final List<List<Offset>> strokes;
  final Size? canvasSize;
  final bool fitInk;

  @override
  void paint(Canvas canvas, Size size) {
    final source = canvasSize ?? const Size(400, 120);
    final bounds = fitInk
        ? signatureInkBounds(strokes, source)
        : Offset.zero & source;
    final fitted = applyBoxFit(BoxFit.contain, bounds.size, size).destination;
    final scale = fitted.width / bounds.width;
    final origin = Offset((size.width - fitted.width) / 2,
        (size.height - fitted.height) / 2) - bounds.topLeft * scale;
    Offset project(Offset point) => origin +
        Offset(point.dx * source.width, point.dy * source.height) * scale;
    final paint = Paint()
      ..color = Colors.black
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    for (final stroke in strokes) {
      if (stroke.isEmpty) { continue; }
      final path = Path();
      final first = project(stroke.first);
      path.moveTo(first.dx, first.dy);
      for (final point in stroke.skip(1)) {
        final projected = project(point);
        path.lineTo(projected.dx, projected.dy);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant SignaturePainter oldDelegate) =>
      true; // Capture appends points to the same stroke list while drawing.
}

/// Trim blank canvas space, retaining original pixel geometry and stroke edges.
Rect signatureInkBounds(List<List<Offset>> strokes, Size source) {
  final points = strokes.expand((stroke) => stroke).where(
      (point) => point.dx.isFinite && point.dy.isFinite).toList();
  if (points.isEmpty) { return Offset.zero & source; }
  var left = points.first.dx.clamp(0.0, 1.0) * source.width;
  var right = left;
  var top = points.first.dy.clamp(0.0, 1.0) * source.height;
  var bottom = top;
  for (final point in points.skip(1)) {
    final x = point.dx.clamp(0.0, 1.0) * source.width;
    final y = point.dy.clamp(0.0, 1.0) * source.height;
    if (x < left) { left = x; }
    if (x > right) { right = x; }
    if (y < top) { top = y; }
    if (y > bottom) { bottom = y; }
  }
  return Rect.fromLTRB(left - 2.4, top - 2.4, right + 2.4, bottom + 2.4);
}

