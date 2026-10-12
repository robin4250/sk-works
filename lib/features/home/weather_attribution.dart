import 'package:flutter/material.dart';
import '../../international/language_controller.dart';

/// Supply only metadata validated by WeatherGatewayResult. Logos retain provider
/// colors because they are required attribution assets, not SKO interface colors.
class WeatherAttribution extends StatelessWidget {
  const WeatherAttribution({super.key, required this.metadata, required this.onOpen});
  final Map<String, dynamic> metadata;
  final ValueChanged<Uri> onOpen;
  @override
  Widget build(BuildContext context) {
    final url = Uri.tryParse(metadata['url']?.toString() ?? '');
    if (url == null || url.scheme != 'https' ||
        !['weatherkit.apple.com', 'openweathermap.org'].contains(url.host)) {
      return const SizedBox.shrink();
    }
    final dark = Theme.of(context).brightness == Brightness.dark;
    final image = metadata[dark ? 'logo_dark_url' : 'logo_light_url']?.toString();
    return TextButton(onPressed: () => onOpen(url), child: Column(mainAxisSize: MainAxisSize.min, children: [
      if (image != null) Image.network(image, height: 22, fit: BoxFit.contain,
        semanticLabel: metadata['name']?.toString() ?? 'Apple Weather',
        errorBuilder: (_, error, stack) => Text(metadata['name']?.toString() ?? 'Apple Weather'))
      else Text(metadata['name']?.toString() ?? ''),
      Text(SkoLanguageController.tr('天気データの出典'), style: const TextStyle(fontSize: 10)),
    ]));
  }
}
