import { createRequire } from 'node:module';
import { createServer } from 'node:http';
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { createHash } from 'node:crypto';
import assert from 'node:assert/strict';
const require = createRequire(import.meta.url);
const { chromium } = require(process.env.PLAYWRIGHT_PACKAGE || 'C:/Users/Grant Knight/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright');
const source = readFileSync('preview/watch-preview.html');
const server = createServer((req, res) => { res.writeHead(200, {'Content-Type': 'text/html'}); res.end(source); });
await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
const url = `http://127.0.0.1:${server.address().port}`;
mkdirSync('verification/preview', { recursive: true });
const browser = await chromium.launch({ headless: true, channel: 'msedge' });
const results = [];
try {
  for (const [pass, width] of [[1, 1280], [2, 736], [3, 320]]) {
    const context = await browser.newContext({ viewport: { width, height: 900 } });
    const page = await context.newPage();
    const errors = []; page.on('pageerror', e => errors.push(e.message));
    await page.goto(url);
    // Freeze only the demo timer; deterministic time advancement below.
    await page.evaluate(() => { for (let i=1; i<100; i++) clearInterval(i); });
    let assertions = 0;
    const check = (actual, expected) => { assert.equal(actual, expected); assertions++; };
    check(await page.locator('#screen .speed').innerText(), '18.4');
    await page.locator('#gps').uncheck();
    check(await page.locator('#screen .speed').innerText(), '—');
    await page.locator('#gps').check();
    await page.selectOption('#unit', 'mph');
    check(await page.locator('#screen .speed').innerText(), '11.4');
    await page.selectOption('#scenario', 'stale');
    check(await page.locator('#screen .metric .value').first().innerText(), '—W');
    await page.locator('.screen-picker [data-tab=ride]').click();
    check(await page.locator('[data-action=start]').isDisabled(), true);
    await page.selectOption('#scenario', 'live');
    await page.locator('[data-action=start]').click();
    await page.evaluate(() => { for(let i=0;i<10;i++) previewApp.tick(); });
    const firstEnergy = await page.evaluate(() => previewApp.state.ride.wh);
    check(firstEnergy > 0, true);
    await page.selectOption('#scenario', 'disconnected');
    await page.evaluate(() => { for(let i=0;i<5;i++) previewApp.tick(); });
    check(await page.evaluate(() => previewApp.state.ride.wh), firstEnergy);
    check(await page.evaluate(() => previewApp.state.recording), true);
    check(await page.evaluate(() => previewApp.state.ride.gaps), 1);
    await page.selectOption('#scenario', 'live');
    await page.locator('[data-action=save]').click();
    await page.locator('#modal-cancel').click();
    check(await page.evaluate(() => previewApp.state.recording), true);
    await page.locator('[data-action=save]').click();
    await page.locator('#modal-confirm').click();
    check(await page.evaluate(() => previewApp.state.rides.length), 3);
    check(await page.evaluate(() => previewApp.state.recording), false);
    await page.reload();
    check(await page.evaluate(() => previewApp.state.rides.length), 3);
    await page.locator('.screen-picker [data-tab=history]').click();
    await page.locator('[data-ride]').first().click();
    await page.locator('[data-action=delete]').click();
    await page.locator('#modal-cancel').click();
    check(await page.evaluate(() => previewApp.state.rides.length), 3);
    await page.locator('[data-action=delete]').click();
    await page.locator('#modal-confirm').click();
    check(await page.evaluate(() => previewApp.state.rides.length), 2);
    await page.locator('.screen-picker [data-tab=navigation]').click();
    await page.locator('[data-action=clearDestination]').click();
    check(await page.locator('[data-action=setDestination]').count(), 1);
    await page.locator('[data-action=setDestination]').click();
    check(await page.locator('[data-action=clearDestination]').count(), 1);
    await page.locator('.screen-picker [data-tab=dashboard]').click();
    await page.selectOption('#scenario', 'low');
    check((await page.locator('#screen').innerText()).includes('14'), true);
    for (const tab of ['dashboard','controller','ride','navigation','history','settings']) {
      await page.locator(`.screen-picker [data-tab=${tab}]`).click();
      check(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth), true);
      check(await page.locator('.watch-top').innerText(), 'DEMO\n10:09');
    }
    await page.locator('.screen-picker [data-tab=dashboard]').click();
    await page.selectOption('#scenario', 'live');
    await page.selectOption('#unit', 'kph');
    check(errors.length, 0);
    await page.screenshot({ path: `verification/preview/preview-${width}.png`, fullPage: true });
    results.push({ pass, width, assertions, errors, result: 'PASS' });
    await context.close();
  }
} catch (error) {
  results.push({ result: 'FAIL', error: error.message }); process.exitCode = 1;
} finally {
  await browser.close(); server.close();
  const report = { source_sha256: createHash('sha256').update(source).digest('hex'), executed_at: new Date().toISOString(), results, status: results.length===3 && results.every(r=>r.result==='PASS') ? 'PASS' : 'FAIL' };
  writeFileSync('verification/preview/results.json', JSON.stringify(report, null, 2));
  console.log(JSON.stringify(report, null, 2));
}
