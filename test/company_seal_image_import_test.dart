import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/domain/company_seal_image_processing.dart';
import 'package:sk_works/features/settings/company_seal_image_import.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('native PNG round trip preserves alpha and pale red without darkening twice', () async {
    final rgba = Uint8List(32 * 32 * 4);
    for (var i = 0; i < rgba.length; i += 4) {
      rgba[i] = 255; rgba[i + 3] = 32;
    }
    final original = SealRgbaImage(width: 32, height: 32, pixels: rgba);
    final png = await CompanySealImageImport.encode(original);
    final input = SealImportInput(name: 'stamp.png', bytes: png);
    final decoded = await CompanySealImageImport.decode(input);
    expect(decoded.image.width, 32);
    expect(decoded.image.pixels[0], greaterThanOrEqualTo(248));
    expect(decoded.image.pixels[3], 32);
    expect(original.pixels, rgba);
  });
  test('PDF magic and file size are checked before decoding', () {
    expect(() => SealImportInput(name: 'bad.pdf', isPdf: true, bytes: Uint8List(30)), throwsFormatException);
    expect(() => SealImportInput(name: 'large.png', bytes: Uint8List(SealImportInput.maxBytes + 1)), throwsFormatException);
  });
}
