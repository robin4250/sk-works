{{flutter_js}}
{{flutter_build_config}}

// Ship the matching engine with this build; no runtime CanvasKit CDN fetch.
_flutter.loader.load({
  config: {canvasKitBaseUrl: 'canvaskit/'},
});
