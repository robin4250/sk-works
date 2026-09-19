import 'package:flutter/material.dart';

class SignatureResult {
  const SignatureResult({
    required this.signerName,
    required this.strokes,
  });

  final String signerName;
  final List<List<Offset>> strokes;

  Object toJson() => [
        for (final stroke in strokes)
          [
            for (final point in stroke)
              {
                'x': point.dx,
                'y': point.dy,
              }
          ]
      ];

  static List<List<Offset>> fromJson(Object? value) {
    if (value is! List) return const [];
    final strokes = <List<Offset>>[];
    for (final rawStroke in value) {
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
}

class SignatureCapturePage extends StatefulWidget {
  const SignatureCapturePage({super.key});

  @override
  State<SignatureCapturePage> createState() => _SignatureCapturePageState();
}

class _SignatureCapturePageState extends State<SignatureCapturePage> {
  final _signer = TextEditingController();
  final _strokes = <List<Offset>>[];
  Size _canvasSize = Size.zero;

  @override
  void dispose() {
    _signer.dispose();
    super.dispose();
  }

  void _startStroke(DragStartDetails details) {
    if (_canvasSize.width <= 0 || _canvasSize.height <= 0) return;
    setState(() {
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
        const SnackBar(content: Text('責任者名を入力してください')),
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
        title: const Text(
          '責任者サイン',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        actions: [
          TextButton(
            onPressed: _strokes.isEmpty
                ? null
                : () => setState(() => _strokes.clear()),
            child: const Text('消去'),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
              child: TextField(
                controller: _signer,
                decoration: const InputDecoration(
                  labelText: '現場責任者名',
                  prefixIcon: Icon(Icons.person_outline),
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    _canvasSize =
                        Size(constraints.maxWidth, constraints.maxHeight);
                    return GestureDetector(
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
                                painter: SignaturePainter(strokes: _strokes),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: FilledButton.icon(
                onPressed: _submit,
                icon: const Icon(Icons.check_circle_outline),
                label: const Text('このサインで確定'),
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
  });

  final List<List<Offset>> strokes;
  final double height;

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
        painter: SignaturePainter(strokes: strokes),
        size: Size.infinite,
      ),
    );
  }
}

class SignaturePainter extends CustomPainter {
  const SignaturePainter({required this.strokes});

  final List<List<Offset>> strokes;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    for (final stroke in strokes) {
      if (stroke.isEmpty) continue;
      final path = Path();
      path.moveTo(stroke.first.dx * size.width, stroke.first.dy * size.height);
      for (final point in stroke.skip(1)) {
        path.lineTo(point.dx * size.width, point.dy * size.height);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant SignaturePainter oldDelegate) =>
      oldDelegate.strokes != strokes;
}
