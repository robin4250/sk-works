import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/shared/resource_registration_card.dart';

// CRC-valid synthetic solid-color PNGs; no user photo is copied or rewritten.
final _landscape = base64Decode('iVBORw0KGgoAAAANSUhEUgAAAZAAAABkCAYAAACoy2Z3AAABgUlEQVR4nO3VMQ0AIQDAQOSg6YVhFzR8F0Jyw+3dOua3NgD8NW4HAPAmAwEgMRAAEgMBIDEQABIDASAxEAASAwEgMRAAEgMBIDEQABIDASAxEAASAwEgMRAAEgMBIDEQABIDASAxEAASAwEgMRAAEgMBIDEQABIDASAxEAASAwEgMRAAEgMBIDEQABIDASAxEAASAwEgMRAAEgMBIDEQABIDASAxEAASAwEgMRAAEgMBIDEQABIDASAxEAASAwEgMRAAEgMBIDEQABIDASAxEAASAwEgMRAAEgMBIDEQABIDASAxEAASAwEgMRAAEgMBIDEQABIDASAxEAASAwEgMRAAEgMBIDEQABIDASAxEAASAwEgMRAAEgMBIDEQABIDASAxEAASAwEgMRAAEgMBIDEQABIDASAxEAASAwEgMRAAEgMBIDEQABIDASAxEAASAwEgMRAAEgMBIDEQABIDASAxEAASAwEgMRAAEgMBIDEQABIDASAxEAASAwEgMRAAkgM425zbuW08swAAAABJRU5ErkJggg==');
final _portrait = base64Decode('iVBORw0KGgoAAAANSUhEUgAAAGQAAAGQCAYAAABYlsXvAAADo0lEQVR4nO3RMREAIBDAsJeDJoRhF2TQIUP23nXWPpeO+R2AIWmGxBgSY0iMITGGxBgSY0iMITGGxBgSY0iMITGGxBgSY0iMITGGxBgSY0iMITGGxBgSY0iMITGGxBgSY0iMITGGxBgSY0iMITGGxBgSY0iMITGGxBgSY0iMITGGxBgSY0iMITGGxBgSY0iMITGGxBgSY0iMITGGxBgSY0iMITGGxBgSY0iMITGGxBgSY0iMITGGxBgSY0iMITGGxBgSY0iMITGGxBgSY0iMITGGxBgSY0iMITGGxBgSY0iMITGGxBgSY0iMITGGxBgSY0iMITGGxBgSY0iMITGGxBgSY0iMITGGxBgSY0iMITGGxBgSY0iMITGGxBgSY0iMITGGxBgSY0iMITGGxBgSY0iMITGGxBgSY0iMITGGxBgSY0iMITGGxBgSY0iMITGGxBgSY0iMITGGxBgSY0iMITGGxBgSY0iMITGGxBgSY0iMITGGxBgSY0iMITGGxBgSY0iMITGGxBgSY0iMITGGxBgSY0iMITGGxBgSY0iMITGGxBgSY0iMITGGxBgSY0iMITGGxBgSY0iMITGGxBgSY0iMITGGxBgSY0iMITGGxBgSY0iMITGGxBgSY0iMITGGxBgSY0iMITGGxBgSY0iMITGGxBgSY0iMITGGxBgSY0iMITGGxBgSY0iMITGGxBgSY0iMITGGxBgSY0iMITGGxBgSY0iMITGGxBgSY0iMITGGxBgSY0iMITGGxBgSY0iMITGGxBgSY0iMITGGxBgSY0iMITGGxBgSY0iMITGGxBgSY0iMITGGxBgSY0iMITGGxBgSY0iMITGGxBgSY0iMITGGxBgSY0iMITGGxBgSY0iMITGGxBgSY0iMITGGxBgSY0iMITGGxBgSY0iMITGGxBgSY0iMITGGxBgSY0iMITGGxBgSY0iMITGGxBgSY0iMITGGxBgSY0iMITGGxBgSY0iMITGGxBgSY0iMITGGxBgSY0iMITGGxBgSY0iMITGGxBgSY0iMITGGxBgSY0iMITGGxBgSY0iMITGGxBgSY0iMITGGxBgSY0iMITGGxBgSY0iMITGGxBgSY0iMITGGxBgSY0iMITGGxBgSY0iMITGGxBgSY0iMITGGxBgSY0iMITGGxBgSY0iMITGGxBgSY0iMITGGxBgSY0iMITGGxBgSY0iMITGGxBgSY0iMITGGxBgSY0iMITGGxBgSY0iMITGGxDwnJ5zbOsnR+gAAAABJRU5ErkJggg==');

void main() {
  for (final scale in [1.0, 2.0]) {
    testWidgets('qualification thumbnail decode preserves aspect and fixed card geometry at text scale $scale', (tester) async {
      Size? cardSize;
      List<Size>? slotSizes;
      for (final horizontal in [true, false]) {
        final bytes = horizontal ? _landscape : _portrait;
        final ratio = horizontal ? 4.0 : .25;
        await tester.pumpWidget(MaterialApp(home: MediaQuery(
          data: MediaQueryData(size: const Size(320, 640), textScaler: TextScaler.linear(scale)),
          child: Scaffold(body: SizedBox(width: 320, child: ResourceRegistrationCard(
            key: ValueKey(horizontal), title: '合成資格', icon: Icons.badge_outlined,
            registered: true, onAction: () {}, attachments: [
              ResourceAttachment(label: '表面', path: 'synthetic-front-$horizontal', loadBytes: () async => bytes),
              ResourceAttachment(label: '裏面', path: 'synthetic-back-$horizontal', loadBytes: () async => bytes),
            ]))))));
        await tester.pumpAndSettle();
        final images = tester.widgetList<Image>(find.byType(Image)).toList();
        expect(images, hasLength(2));
        for (final image in images) {
          await tester.runAsync(() => precacheImage(image.image, tester.element(find.byType(ResourceRegistrationCard))));
        }
        await tester.pumpAndSettle();
        final currentCardSize = tester.getSize(find.byType(ResourceRegistrationCard));
        final currentSlots = [for (final element in find.byType(ResourceAttachmentThumbnail).evaluate()) tester.getSize(find.byWidget(element.widget))];
        cardSize ??= currentCardSize; slotSizes ??= currentSlots;
        expect(currentCardSize, cardSize, reason: 'original image dimensions must not resize the qualification card');
        expect(currentSlots, slotSizes, reason: 'front/back small windows remain fixed');
        expect(currentSlots.every((size) => size.width == 52), isTrue);
        for (final element in find.byType(RawImage).evaluate()) {
          final rendered = element.renderObject! as RenderImage;
          final decoded = rendered.image!;
          expect(decoded.width / decoded.height, closeTo(ratio, .001),
            reason: 'decode hints must not stretch a landscape or portrait original');
          expect(rendered.fit, BoxFit.contain);
          final source = Size(decoded.width.toDouble(), decoded.height.toDouble());
          final fitted = applyBoxFit(rendered.fit!, source, rendered.size);
          expect(fitted.source, source, reason: 'contain keeps the whole photo without cropping');
          expect(fitted.destination.aspectRatio, closeTo(ratio, .001));
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      }
    });
  }
}
