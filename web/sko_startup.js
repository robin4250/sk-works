(() => {
  'use strict';
  // External invitation links can replace only the fragment in an open tab.
  // Flutter reads the invitation when it starts, so start it with the new link.
  const initialHash = window.location.hash;
  const invitationHash = /^#\/?\?(customer|subcontractor|sko|work_pass)_invite=[a-f0-9]{48}$/;
  window.addEventListener('hashchange', event => {
    const next = new URL(event.newURL);
    if (next.hash !== initialHash && invitationHash.test(next.hash)) {
      // Flutter can update the current fragment before hashchange is delivered.
      // Change the document URL while keeping the invitation code in the fragment.
      const current = new URL(window.location.href);
      const revision = Number(current.searchParams.get('invite_navigation')) || 0;
      next.searchParams.set('invite_navigation', String(revision + 1));
      window.location.replace(next.href);
    }
  });
  const panel = document.getElementById('sko-startup');
  const message = document.getElementById('sko-startup-message');
  const retry = document.getElementById('sko-startup-retry');
  if (!panel || !message || !retry) return;
  const english = /^en(?:-|$)/i.test(navigator.language || '');
  if (english) {
    panel.setAttribute('lang', 'en');
    message.textContent = 'Loading…';
    retry.textContent = 'Reload';
  }
  retry.hidden = true;
  let finished = false;
  const fail = () => {
    if (finished) return;
    clearTimeout(timer);
    message.textContent = english
      ? 'Loading is taking longer than expected. Check your connection, then reload.'
      : '読み込みに時間がかかっています。通信状態を確認して、再読み込みしてください。';
    retry.hidden = false;
  };
  const timer = setTimeout(fail, 30000);
  retry.addEventListener('click', event => {
    event.preventDefault();
    window.location.reload();
  });
  window.addEventListener('flutter-first-frame', () => {
    finished = true;
    clearTimeout(timer);
    panel.hidden = true;
  }, {once: true});
  // Script fetch failures do not reject the Flutter loader promise.
  window.addEventListener('error', event => {
    if (event.target?.id === 'sko-flutter-bootstrap') fail();
  }, true);
  window.skoStartup = Object.freeze({fail});
})();
