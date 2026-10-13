// ignore_for_file: prefer_interpolation_to_compose_strings

import 'dart:io';

final japanese = RegExp(r'''['"\x60][^'"\x60\n]*[\u3040-\u30ff\u3400-\u9fff][^'"\x60\n]*['"\x60]''');
final translated = RegExp(r'SkoLanguageController\.tr\(');

void main() {
  final pages = Directory('lib/features')
      .listSync(recursive: true)
      .whereType<File>()
      .where((file) => file.path.endsWith('_page.dart'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  stdout.writeln('SKO UI language audit');
  stdout.writeln('pages=' + pages.length.toString());
  stdout.writeln('path\tjapanese_literals\ttranslation_calls');

  var totalJapanese = 0;
  var totalTranslated = 0;
  for (final file in pages) {
    final source = file.readAsStringSync();
    final jp = japanese.allMatches(source).length;
    final tr = translated.allMatches(source).length;
    totalJapanese += jp;
    totalTranslated += tr;
    if (jp > 0 || tr > 0) {
      stdout.writeln(file.path + '\t' + jp.toString() + '\t' + tr.toString());
    }
  }

  stdout.writeln(
    'TOTAL\t' + totalJapanese.toString() + '\t' + totalTranslated.toString(),
  );
}
