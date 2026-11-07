(() => {
  'use strict';
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
