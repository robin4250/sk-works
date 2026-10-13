import 'package:flutter/material.dart';

import 'traffic_link_policy.dart';

/// Compact coloured signs; labels supply the accessible destination name.
class TrafficDestinationIcon extends StatelessWidget {
  const TrafficDestinationIcon({super.key, required this.destination, this.enabled = true});

  final TrafficDestination destination;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: SizedBox.square(
        dimension: 20,
        child: CustomPaint(
          painter: _TrafficSignPainter(
            destination,
            enabled,
            DefaultTextStyle.of(context).style.color ??
                Theme.of(context).colorScheme.primary,
          ),
        ),
      ),
    );
  }
}

class _TrafficSignPainter extends CustomPainter {
  const _TrafficSignPainter(this.destination, this.enabled, this.disabledColor);

  final TrafficDestination destination;
  final bool enabled;
  final Color disabledColor;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 24, size.height / 24);
    final accent = switch (destination) {
      TrafficDestination.nearestStation => const Color(0xffad1457),
      TrafficDestination.trainTransfer => const Color(0xff606060),
      TrafficDestination.busStop => const Color(0xff2e7d32),
    };
    final color = enabled ? accent : disabledColor;
    final body = Paint()..color = enabled ? Color.lerp(accent, Colors.white, .82)! : disabledColor;
    final detail = Paint()..color = enabled ? const Color(0xff454545) : disabledColor;
    final line = Paint()
      ..color = color
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    final fill = Paint()..color = color;
    void segment(double x1, double y1, double x2, double y2) =>
        canvas.drawLine(Offset(x1, y1), Offset(x2, y2), line);
    switch (destination) {
      case TrafficDestination.nearestStation:
        // Station building with a raised station-name sign and platform doors.
        canvas.drawRRect(
          RRect.fromRectAndRadius(const Rect.fromLTWH(5, 2, 14, 5), const Radius.circular(1)),
          line,
        );
        segment(8, 4.5, 16, 4.5);
        segment(7, 7, 7, 10);
        segment(17, 7, 17, 10);
        canvas.drawRect(const Rect.fromLTWH(3, 10, 18, 11), body);
        canvas.drawRect(const Rect.fromLTWH(3, 10, 18, 11), line);
        segment(1.5, 21, 22.5, 21);
        canvas.drawRect(const Rect.fromLTWH(9, 14, 6, 7), line);
        segment(12, 14, 12, 21);
        canvas.drawRect(const Rect.fromLTWH(5, 13, 2, 3), fill);
        canvas.drawRect(const Rect.fromLTWH(17, 13, 2, 3), fill);
      case TrafficDestination.trainTransfer:
        // Side view: carriage, windows, wheels and rail.
        final carriage = Path()
          ..moveTo(3, 6)
          ..lineTo(18, 6)
          ..quadraticBezierTo(21, 6, 22, 10)
          ..lineTo(22, 17)
          ..lineTo(2, 17)
          ..lineTo(2, 8)
          ..quadraticBezierTo(2, 6, 3, 6);
        body.color = enabled ? const Color(0xffe0e0e0) : disabledColor;
        canvas.drawPath(carriage, body);
        canvas.drawRect(const Rect.fromLTWH(2, 14, 20, 2),
          Paint()..color = enabled ? const Color(0xff2e7d32) : disabledColor);
        canvas.drawPath(carriage, line);
        for (final x in [5.0, 10.0, 15.0]) {
          canvas.drawRRect(
            RRect.fromRectAndRadius(Rect.fromLTWH(x, 9, 3, 4), const Radius.circular(.5)),
            fill,
          );
        }
        canvas.drawCircle(const Offset(6, 18), 1.6, detail);
        canvas.drawCircle(const Offset(18, 18), 1.6, detail);
        segment(1, 22, 23, 22);
      case TrafficDestination.busStop:
        // Bus-stop sign with a side-view bus, windows and two wheels.
        canvas.drawRRect(
          RRect.fromRectAndRadius(const Rect.fromLTWH(5, 2, 14, 12), const Radius.circular(4)),
          line,
        );
        final bus = RRect.fromRectAndRadius(const Rect.fromLTWH(8, 5, 8, 5), const Radius.circular(1));
        canvas.drawRRect(bus, body);
        canvas.drawRRect(bus, line);
        for (final x in [9.0, 11.5, 14.0]) {
          canvas.drawRect(Rect.fromLTWH(x, 6, 1.5, 1.5), fill);
        }
        canvas.drawCircle(const Offset(9.5, 11), .8, detail);
        canvas.drawCircle(const Offset(14.5, 11), .8, detail);
        segment(12, 14, 12, 21);
        segment(8, 22, 16, 22);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_TrafficSignPainter oldDelegate) =>
      destination != oldDelegate.destination || enabled != oldDelegate.enabled || disabledColor != oldDelegate.disabledColor;
}
