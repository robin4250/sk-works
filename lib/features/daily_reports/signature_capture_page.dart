import 'package:flutter/material.dart';

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
    if (rawValue is! List) return const [];
    final strokes = <List<Offset>>[];
    for (final rawStroke in rawValue) {
      if (rawStroke is! List) continue;
      final points = <Offset>[];
      for (final rawPoint in rawStroke) {
        if (rawPoint is! Map) continue;
        final x = (rawPoint['x'] as num?)?.toDouble();
        final y = (rawPoint['y'] as num?)?.toDouble();
        if (x == null || y == null) continue;
        points.add(Offset(x, y));
      }
      if (points.isNotEmpty) strokes.add(points);
    }
    return strokes;
  }

  // Point metadata survives existing RPCs which wrap the stroke list unchanged.
  // Legacy normalized strokes have no recoverable capture dimensions.
  static Size? sizeFromJson(Object? value) {
    final strokes = value is Map ? value['strokes'] : value;
    if (strokes is! List) return null;
    for (final stroke in strokes) {
      if (stroke is! List) continue;
      for (final point in stroke) {
        if (point is! Map) continue;
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
    this.submitLabel = 'このサインで確定',
    this.initialSignerName = '',
    this.signerNameOptions = const [],
  });

  final String title;
  final String signerLabel;
  final String submitLabel;
  final String initialSignerName;
  final List<String> signerNameOptions;

  @override
  State<SignatureCapturePage> createState() => _SignatureCapturePageState();
}

class _SignatureCapturePageState extends State<SignatureCapturePage> {
  final _signer = TextEditingController();
  final _strokes = <List<Offset>>[];
  Size _canvasSize = Size.zero;
  Size? _captureSize;

  @override
  void initState() {
    super.initState();
    _signer.text = widget.initialSignerName;
  }

  @override
  void dispose() {
    _signer.dispose();
    super.dispose();
  }

  void _startStroke(DragStartDetails details) {
    if (_canvasSize.width <= 0 || _canvasSize.height <= 0) return;
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
    if (_strokes.isEmpty || _canvasSize.width <= 0 || _canvasSize.height <= 0) {
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
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.title,
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        actions: [
          TextButton(
            onPressed: _strokes.isEmpty
                ? null
                : () => setState(() { _strokes.clear(); _captureSize = null; }),
            child: const Text('消去'),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Text('画面を横向きにすると大きくサインできます。記入時の縦横比を保って保存します。'),
            ),
            if (widget.signerNameOptions.any((name) => name.trim().isNotEmpty))
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: DropdownButtonFormField<String>(
                  key: const ValueKey('signature-member-picker'),
                  decoration: const InputDecoration(labelText: '出勤メンバーから選択'),
                  items: [
                    for (final name
                        in widget.signerNameOptions
                            .map((name) => name.trim())
                            .where((name) => name.isNotEmpty)
                            .toSet())
                      DropdownMenuItem(value: name, child: Text(name)),
                  ],
                  onChanged: (name) {
                    if (name != null) _signer.text = name;
                  },
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
              child: TextField(
                controller: _signer,
                decoration: InputDecoration(
                  labelText: widget.signerLabel,
                  prefixIcon: const Icon(Icons.person_outline),
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final available = Size(constraints.maxWidth, constraints.maxHeight);
                    final fitted = _captureSize == null ? available : applyBoxFit(BoxFit.contain, _captureSize!, available).destination;
                    _canvasSize = fitted;
                    return Center(child: SizedBox(width: fitted.width, height: fitted.height, child: GestureDetector(
                      onPanStart: _startStroke,
                      onPanUpdate: _addPoint,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          border: Border.all(
                            color: Theme.of(context).colorScheme.outlineVariant,
                          ),
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Stack(
                          children: [
                            const Positioned(
                              left: 16,
                              top: 14,
                              child: Text(
                                'この枠内に指またはペンでサインしてください',
                                style: TextStyle(fontSize: 13),
                              ),
                            ),
                            Positioned.fill(
                              child: CustomPaint(
                                painter: SignaturePainter(strokes: _strokes, canvasSize: _captureSize ?? _canvasSize),
                              ),
                            ),
                          ],
                        ),
                      ),
                    )));
                  },
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: FilledButton.icon(
                onPressed: _submit,
                icon: const Icon(Icons.check_circle_outline),
                label: Text(widget.submitLabel),
              ),
            ),
          ],
        ),
      ),
    );
  }
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
        painter: SignaturePainter(strokes: strokes, canvasSize: canvasSize),
        size: Size.infinite,
      ),
    );
  }
}

class SignaturePainter extends CustomPainter {
  const SignaturePainter({required this.strokes, this.canvasSize});

  final List<List<Offset>> strokes;
  final Size? canvasSize;

  @override
  void paint(Canvas canvas, Size size) {
    final source = canvasSize ?? const Size(400, 120);
    final fitted = applyBoxFit(BoxFit.contain, source, size).destination;
    final origin = Offset((size.width - fitted.width) / 2, (size.height - fitted.height) / 2);
    final paint = Paint()
      ..color = Colors.black
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    for (final stroke in strokes) {
      if (stroke.isEmpty) continue;
      final path = Path();
      path.moveTo(origin.dx + stroke.first.dx * fitted.width, origin.dy + stroke.first.dy * fitted.height);
      for (final point in stroke.skip(1)) {
        path.lineTo(origin.dx + point.dx * fitted.width, origin.dy + point.dy * fitted.height);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant SignaturePainter oldDelegate) =>
      true; // Capture appends points to the same stroke list while drawing.
}
