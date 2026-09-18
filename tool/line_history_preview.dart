import 'dart:io';

import 'package:sk_works/features/chat/line_history_parser.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.length != 1) {
    stderr.writeln('Usage: dart run tool/line_history_preview.dart <line-export.txt>');
    exitCode = 64;
    return;
  }

  final file = File(arguments.single);
  if (!await file.exists()) {
    stderr.writeln('File not found: ${file.path}');
    exitCode = 66;
    return;
  }

  final source = await file.readAsString();
  final result = const LineHistoryParser().parse(source);

  stdout.writeln('Parsed messages: ${result.messages.length}');
  stdout.writeln('Ignored non-message lines: ${result.ignoredLineCount}');
  stdout.writeln('No data was uploaded or written to SKO.');

  if (result.messages.isEmpty) {
    return;
  }

  stdout.writeln();
  stdout.writeln('Preview (first 20 messages):');
  for (final message in result.messages.take(20)) {
    final timestamp = _formatTimestamp(message.timestamp);
    final previewBody = message.body.replaceAll('\n', ' ↩ ');
    stdout.writeln('[$timestamp] ${message.sender}: $previewBody');
  }
}

String _formatTimestamp(DateTime value) {
  String twoDigits(int number) => number.toString().padLeft(2, '0');

  return '${value.year}-${twoDigits(value.month)}-${twoDigits(value.day)} '
      '${twoDigits(value.hour)}:${twoDigits(value.minute)}';
}
