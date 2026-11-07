{{flutter_js}}
{{flutter_build_config}}

// Keep the engine self-hosted and preserve Flutter's default initialization.
try {
  Promise.resolve(_flutter.loader.load({
    config: {canvasKitBaseUrl: 'canvaskit/'},
  })).catch(() => window.skoStartup?.fail());
} catch (_) {
  window.skoStartup?.fail();
}
