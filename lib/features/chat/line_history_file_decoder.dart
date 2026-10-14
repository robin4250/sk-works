import 'dart:convert';
import 'package:archive/archive.dart';

const lineHistoryFileLimitBytes = 5 * 1024 * 1024;

/// Reads text in memory; ZIP paths are never extracted onto the device.
String decodeLineHistoryFile(List<int> bytes, String fileName) {
  if (bytes.isEmpty || bytes.length > lineHistoryFileLimitBytes) {
    throw const FormatException('Empty or oversized LINE file');
  }
  List<int> textBytes = bytes;
  if (fileName.toLowerCase().endsWith('.zip')) {
    final archive = ZipDecoder().decodeBytes(bytes);
    final candidates = archive.files.where((entry) {
      final path = entry.name.replaceAll('\\', '/');
      final parts = path.split('/');
      return entry.isFile && !entry.isSymbolicLink &&
        !parts.contains('__MACOSX') &&
        !parts.any((part) => part.startsWith('._')) &&
        path.toLowerCase().endsWith('.txt');
    }).toList();
    if (candidates.length != 1) {
      throw const FormatException('ZIP needs one LINE history text');
    }
    final entry = candidates.single;
    if (entry.size <= 0 || entry.size > lineHistoryFileLimitBytes) {
      throw const FormatException('Oversized expanded LINE text');
    }
    final contents = entry.readBytes();
    if (contents == null || contents.isEmpty ||
        contents.length > lineHistoryFileLimitBytes) {
      throw const FormatException('Unreadable LINE text');
    }
    textBytes = contents;
  } else if (!fileName.toLowerCase().endsWith('.txt')) {
    throw const FormatException('Choose a LINE TXT or ZIP');
  }
  return utf8.decode(textBytes).replaceFirst('\uFEFF', '');
}
