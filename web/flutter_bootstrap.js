{{flutter_js}}
{{flutter_build_config}}

// Android Chrome can present a blank GPU frame when opening an invitation.
const userAgent = globalThis.navigator?.userAgent ?? '';
const androidChrome = /Android.*Chrome\//.test(userAgent)
  && !/; wv\)|EdgA\/|OPR\/|SamsungBrowser\//.test(userAgent);
const externalInvitation = /^#\/?\?(customer|subcontractor|sko|work_pass)_invite=[a-f0-9]{48}$/
  .test(window.location?.hash ?? '');
try {
  Promise.resolve(_flutter.loader.load({
    config: {
      canvasKitBaseUrl: 'canvaskit/',
      canvasKitForceCpuOnly: androidChrome && externalInvitation,
    },
  })).catch(() => window.skoStartup?.fail());
} catch (_) {
  window.skoStartup?.fail();
}
