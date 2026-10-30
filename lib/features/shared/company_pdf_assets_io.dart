import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;

// Internal renderer only. Application builds select the Flutter asset loader.
// No document value can choose a filesystem path or change this asset set.
const _assets = <String, String>{
  'assets/fonts/company-seal/NotoSansJP-Bold.ttf':
      '60aa355a4881177ce785dfa69a7951c563d0396c588d24d07bff9e8946e667a3',
  'assets/fonts/company-seal/aoyagi-reisho/AoyagiReisho.ttf':
      'a4c55ad5f72e65a482931d967725e97ff206eb3019c87281d9e5514a63bb8db9',
  'assets/fonts/company-seal/aoyagi-reisho/coverage.json':
      'a18634f26175c1277ec3b344b2641dad167a5cd6f38fc225ab8f76483bf7152a',
  'assets/images/company-seals/sumida-v1/standard.png':
      '612e6c684b684ecb5f84230e79a5accad3e1a1e52a19470e5deae53ee478bbd1',
  'assets/images/company-seals/sumida-v1/light.png':
      '9a92a7eddcff164a871f0fb663febe381f2bb8076e2a232e220211bf0a38e8ba',
  'assets/images/company-seals/sumida-v1/worn.png':
      '071cb3b850ade006c3c8a99c07a3af1dc193caac04ac001d1436303f182373cf',
};
Directory? _root;
void configureCanonicalPdfAssets(String root) {
  if (_root != null) throw StateError('Canonical assets already configured.');
  final directory = Directory(root);
  if (!directory.isAbsolute) throw StateError('Absolute asset root required.');
  _root = Directory(directory.resolveSymbolicLinksSync());
}

Future<ByteData> load(String path) async {
  final expected = _assets[path], root = _root;
  if (expected == null || root == null)
    throw StateError('Unconfigured canonical asset.');
  final file = File.fromUri(root.uri.resolve(path));
  final resolved = await file.resolveSymbolicLinks();
  if (!resolved.startsWith('${root.path}${Platform.pathSeparator}')) {
    throw StateError('Canonical asset escaped root.');
  }
  final bytes = await File(resolved).readAsBytes();
  if (crypto.sha256.convert(bytes).toString() != expected) {
    throw StateError('Canonical asset changed.');
  }
  return ByteData.sublistView(bytes);
}

Future<String> loadString(String path) async {
  final data = await load(path);
  return utf8.decode(
    data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
  );
}
