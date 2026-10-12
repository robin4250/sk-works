import 'package:flutter/material.dart';

import 'traffic_link_policy.dart';

/// Small theme-coloured signs; labels supply the accessible destination name.
class TrafficDestinationIcon extends StatelessWidget {
  const TrafficDestinationIcon({super.key, required this.destination});

  final TrafficDestination destination;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: SizedBox.square(
        dimension: 20,
        child: CustomPaint(
          painter: _TrafficSignPainter(
            destination,
            DefaultTextStyle.of(context).style.color ??
                Theme.of(context).colorScheme.primary,
          ),
        ),
      ),
    );
  }
}

class _TrafficSignPainter extends CustomPainter {
  const _TrafficSignPainter(this.destination, this.color);

  final TrafficDestination destination;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 24, size.height / 24);
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
        canvas.drawPath(carriage, line);
        for (final x in [5.0, 10.0, 15.0]) {
          canvas.drawRRect(
            RRect.fromRectAndRadius(Rect.fromLTWH(x, 9, 3, 4), const Radius.circular(.5)),
            fill,
          );
        }
        canvas.drawCircle(const Offset(6, 18), 1.6, fill);
        canvas.drawCircle(const Offset(18, 18), 1.6, fill);
        segment(1, 22, 23, 22);
      case TrafficDestination.busStop:
        // Bus-stop sign on a post, rather than a front-facing bus.
        canvas.drawRRect(
          RRect.fromRectAndRadius(const Rect.fromLTWH(5, 2, 14, 12), const Radius.circular(4)),
          line,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(const Rect.fromLTWH(8, 5, 8, 5), const Radius.circular(1)),
          line,
        );
        segment(10, 6, 14, 6);
        canvas.drawCircle(const Offset(9.5, 11), .8, fill);
        canvas.drawCircle(const Offset(14.5, 11), .8, fill);
        segment(12, 14, 12, 21);
        segment(8, 22, 16, 22);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_TrafficSignPainter oldDelegate) =>
      destination != oldDelegate.destination || color != oldDelegate.color;
}
