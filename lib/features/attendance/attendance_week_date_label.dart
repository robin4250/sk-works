import 'package:flutter/material.dart';

/// Give the full holiday name its own readable line; date/weekday share a row.
class AttendanceWeekDateLabel extends StatelessWidget {
  const AttendanceWeekDateLabel({super.key, required this.date, required this.weekday, this.holidayName});
  final DateTime date;
  final String weekday;
  final String? holidayName;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final color = holidayName != null || date.weekday == DateTime.sunday
        ? colors.error
        : date.weekday == DateTime.saturday ? Colors.blue.shade700 : colors.onSurfaceVariant;
    return SizedBox(
      width: holidayName == null ? 46 : 110,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text('${date.day} $weekday', style: TextStyle(fontSize: 11, height: 1.05, fontWeight: FontWeight.w700, color: color)),
          ),
          if (holidayName != null) ...[
            const SizedBox(height: 1),
            Text(holidayName!, textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, height: 1.05, fontWeight: FontWeight.w700, color: colors.error)),
          ],
        ],
      ),
    );
  }
}
