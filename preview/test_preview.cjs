// Exercise the exact preview script without browser dependencies.
// Native Watch rendering and hardware are verified separately on Apple devices.
const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const source = fs.readFileSync(require('node:path').join(__dirname, 'watch-preview.html'), 'utf8');
const script = source.match(/<script>([\s\S]*?)<\/script>/)[1];
function boot(storage = new Map()) {
  const elements = new Map();
  const get = id => {
    if (!elements.has(id)) elements.set(id, { innerHTML: '', textContent: '', hidden: id === 'modal', checked: true,
      scrollTop: 0, focus() {}, setAttribute() {}, onclick: null, click() { this.onclick?.(); } });
    return elements.get(id);
  };
  const context = { window: {}, document: { getElementById: get, querySelector: get,
    querySelectorAll: () => [], addEventListener() {}, activeElement: get('focus') },
    localStorage: { getItem: k => storage.has(k) ? storage.get(k) : null, setItem: (k,v) => storage.set(k,v) },
    setInterval() {}, Date, console };
  vm.runInNewContext(script, context, { filename: 'watch-preview.html' });
  return { app: context.window.previewApp, elements, get, storage };
}
const first = boot();
for (const name of ['dashboard', 'controller', 'ride', 'navigation', 'history', 'settings', 'bms']) {
  first.app.setTab(name);
  assert(first.get('screen').innerHTML.length > 60, name + ' renders');
}
first.app.setTab('dashboard');
assert.match(first.get('screen').innerHTML, /GPS · km\/h/);
first.get('gps').onchange({ target: { checked: false } });
assert.match(first.get('screen').innerHTML, /GPS unavailable/);
first.get('scenario').onchange({ target: { value: 'stale' } });
assert.match(first.get('screen').innerHTML, /STALE DATA/);
assert(!first.get('screen').innerHTML.includes('852'));
first.app.setTab('ride');
assert.match(first.get('screen').innerHTML, /disabled/);
first.app.action('start');
assert.equal(first.app.state.recording, false);
first.get('scenario').onchange({ target: { value: 'live' } });
first.get('gps').onchange({ target: { checked: true } });
first.app.action('start');
assert.equal(first.app.state.recording, true);
for (let i=0; i<60; i++) first.app.tick();
assert.equal(first.app.state.ride.seconds, 60);
assert(first.app.state.ride.km > 0 && first.app.state.ride.wh > 0);
const km = first.app.state.ride.km, wh = first.app.state.ride.wh;
first.get('scenario').onchange({ target: { value: 'disconnected' } });
first.app.tick();
assert.equal(first.app.state.ride.km, km);
assert.equal(first.app.state.ride.wh, wh);
assert.equal(first.app.state.ride.gaps, 1);
first.app.action('save');
assert.equal(first.get('modal').hidden, false);
first.get('modal-cancel').click();
assert.equal(first.app.state.recording, true);
first.app.action('save');
first.get('modal-confirm').click();
assert.equal(first.app.state.recording, false);
assert.equal(first.app.state.rides.length, 3);
const second = boot(first.storage);
assert.equal(second.app.state.rides.length, 3);
second.app.setTab('history');
second.app.state.selected = second.app.state.rides[0].id;
second.app.action('delete');
second.get('modal-cancel').click();
assert.equal(second.app.state.rides.length, 3);
second.app.action('delete');
second.get('modal-confirm').click();
assert.equal(second.app.state.rides.length, 2);
assert.equal(boot(first.storage).app.state.rides.length, 2);
const corrupt = boot(new Map([['foil-assist-preview-v1', '[{"malformed":true}]']]));
assert.equal(corrupt.app.state.rides.length, 2);
assert.match(corrupt.get('storage-note').textContent, /invalid/);
second.app.setTab('dashboard');
second.get('scenario').onchange({ target: { value: 'low' } });
assert.match(second.get('screen').innerHTML, />14<small>/);
second.get('unit').onchange({ target: { value: 'mph' } });
assert.match(second.get('screen').innerHTML, /11\.4/);
console.log('PASS: seven screens; GPS unavailable; stale masking; start guards; gap accounting; save/cancel; browser persistence; delete/cancel; invalid history recovery; units; low battery.');
