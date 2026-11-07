const {test} = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');
const source = fs.readFileSync(path.join(__dirname, '../web/sko_startup.js'), 'utf8');
function fixture(language='ja') {
  const events = {}, timers = new Map(); let reloads = 0;
  const nodes = Object.fromEntries(['sko-startup','sko-startup-message','sko-startup-retry'].map(id=>[id,{hidden:false,textContent:'読み込み中です…',setAttribute(k,v){this[k]=v;},addEventListener(k,fn){this[k]=fn;}}]));
  const window = {addEventListener(k,fn){events[k]=fn;},location:{reload(){reloads++;}}};
  vm.runInNewContext(source,{window,navigator:{language},document:{getElementById:id=>nodes[id]},setTimeout(fn){timers.set(1,fn);return 1;},clearTimeout(id){timers.delete(id);}});
  return {window,nodes,events,timers,get reloads(){return reloads;}};
}
test('slow startup shows recovery without automatic reload',()=>{const f=fixture();f.timers.get(1)();assert.equal(f.nodes['sko-startup-retry'].hidden,false);assert.equal(f.reloads,0);f.nodes['sko-startup-retry'].click({preventDefault(){}});assert.equal(f.reloads,1);});
test('first frame hides panel and later errors cannot restore it',()=>{const f=fixture();f.events['flutter-first-frame']();f.window.skoStartup.fail();assert.equal(f.nodes['sko-startup'].hidden,true);assert.equal(f.timers.size,0);assert.equal(f.nodes['sko-startup-retry'].hidden,true);});
test('bootstrap fetch failure shows recovery; unrelated errors do not',()=>{const f=fixture();f.events.error({target:{id:'other'}});assert.equal(f.nodes['sko-startup-retry'].hidden,true);f.events.error({target:{id:'sko-flutter-bootstrap'}});assert.equal(f.nodes['sko-startup-retry'].hidden,false);});
test('English browser receives English recovery text',()=>{const f=fixture('en-US');f.window.skoStartup.fail();assert.match(f.nodes['sko-startup-message'].textContent,/Check your connection/);assert.equal(f.nodes['sko-startup-retry'].textContent,'Reload');});
test('a late first frame can recover after timeout',()=>{const f=fixture();f.window.skoStartup.fail();f.events['flutter-first-frame']();assert.equal(f.nodes['sko-startup'].hidden,true);assert.equal(f.reloads,0);});
const bootstrap = fs.readFileSync(path.join(__dirname,'../web/flutter_bootstrap.js'),'utf8').replace('{{flutter_js}}','').replace('{{flutter_build_config}}','');
test('loader keeps the self-hosted engine configuration',async()=>{let config;vm.runInNewContext(bootstrap,{_flutter:{loader:{load(value){config=value.config;return Promise.resolve();}}},window:{}});assert.equal(config.canvasKitBaseUrl,'canvaskit/');});
test('loader rejection requests recovery without exposing error details',async()=>{let failures=0;vm.runInNewContext(bootstrap,{_flutter:{loader:{load(){return Promise.reject(new Error('private diagnostic'));}}},window:{skoStartup:{fail(){failures++;}}}});await new Promise(resolve=>setImmediate(resolve));assert.equal(failures,1);});
test('synchronous loader failure also requests recovery',()=>{let failures=0;vm.runInNewContext(bootstrap,{_flutter:{loader:{load(){throw new Error('private diagnostic');}}},window:{skoStartup:{fail(){failures++;}}}});assert.equal(failures,1);});

test('the static retry link works when neither script loads', () => {
  const html = fs.readFileSync(path.join(__dirname, '../web/index.html'), 'utf8');
  assert.match(html, /<a id="sko-startup-retry" href="">再読み込み<\/a>/);
});
