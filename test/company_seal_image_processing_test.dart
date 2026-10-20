import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/domain/company_seal_image_processing.dart';

SealRgbaImage image(int width, int height, List<int> color) {
  final pixels = Uint8List(width * height * 4);
  for (var i = 0; i < pixels.length; i += 4) {
    pixels.setRange(i, i + 4, color);
  }
  return SealRgbaImage(width: width, height: height, pixels: pixels);
}
void main() {
  test('white removal retains pale red, source and fixed raster geometry', () {
    final pixels = Uint8List.fromList(image(4, 4, [255, 255, 255, 255]).pixels);
    pixels.setRange(20, 24, [255, 250, 250, 255]);
    final source = SealRgbaImage(width: 4, height: 4, pixels: pixels);
    final original = Uint8List.fromList(source.pixels);
    final output = prepareCompanySealImage(source, SealPixelCrop.full(source));
    expect(output.width, 1024); expect(output.height, 1024);
    expect(source.pixels, original);
    expect(output.pixels[3], 0);
    final center = (512 * 1024 + 512) * 4;
    expect(output.pixels[center], 255);
    expect(output.pixels[center + 1], 0);
    expect(output.pixels[center + 3], 5);
  });
  test('manual crop excludes neighboring ink and keeps proportional padding', () {
    final source = image(4, 4, [255, 0, 0, 255]);
    final output = prepareCompanySealImage(source, const SealPixelCrop(0, 0, 4, 2),
      options: const SealImageOptions(removeWhite: false));
    expect(output.pixels[(100 * 1024 + 512) * 4 + 3], 0);
    expect(output.pixels[(512 * 1024 + 512) * 4 + 3], 255);
    expect(output.pixels[(900 * 1024 + 512) * 4 + 3], 0);
  });
  test('four rotations restore exact original pixels without mutation', () {
    final source = image(2, 3, [200, 1, 2, 255]);
    var rotated = source;
    for (var i = 0; i < 4; i++) { rotated = rotateCompanySealImage(rotated, 1); }
    expect(rotated.width, source.width); expect(rotated.height, source.height);
    expect(rotated.pixels, source.pixels);
  });
  test('empty region and invalid dimensions fail instead of saving blank PNG', () {
    final white = image(4, 4, [255, 255, 255, 255]);
    expect(() => prepareCompanySealImage(white, SealPixelCrop.full(white)), throwsFormatException);
    expect(() => prepareCompanySealImage(white, const SealPixelCrop(0, 0, 1, 1)), throwsFormatException);
    expect(() => SealRgbaImage(width: 4096, height: 1, pixels: Uint8List(4096 * 4)), throwsFormatException);
  });
}
