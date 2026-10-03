// Independent council regression: never calls OpenRouter or inherits a usable API key.
import { mkdtempSync, writeFileSync, readFileSync, rmSync, mkdirSync } from 'node:fs';
import { join } from 'node:path';
import { spawnSync } from 'node:child_process';
import assert from 'node:assert/strict';

mkdirSync('verification', { recursive: true });
const directory = mkdtempSync(join('verification', 'gate-council-'));
const categories = ['swift_core_tests', 'watch_simulator_build', 'preview_browser_tests', 'independent_review'];
const complete = Object.fromEntries(categories.map(name => [name, {
  result: 'PASS', revision: 'revision-1', ...(name === 'independent_review' ? { author_is_reviewer: false } : {})
}]));
const cases = [
  { name: 'missing', data: { revision: 'revision-1' }, expected: 'INSUFFICIENT_EVIDENCE' },
  { name: 'failed-and-missing', data: { revision: 'revision-1', executed_results: { swift_core_tests: { result: 'FAIL', revision: 'revision-1' } } }, expected: 'HOLD' },
  { name: 'complete', data: { revision: 'revision-1', executed_results: complete }, expected: 'PASS' },
  { name: 'self-review', data: { revision: 'revision-1', executed_results: { ...complete, independent_review: { result: 'PASS', revision: 'revision-1', author_is_reviewer: true } } }, expected: 'HOLD' },
  { name: 'no-revision', data: {}, expected: 'INSUFFICIENT_EVIDENCE' },
  { name: 'defect-and-missing', data: { revision: 'revision-1', open_defects: ['critical'] }, expected: 'HOLD' },
  { name: 'revision-mismatch', data: { revision: 'revision-2', executed_results: complete }, expected: 'HOLD' }
];
try {
  for (const item of cases) {
    const path = join(directory, item.name); // Deliberately no .json suffix.
    const input = JSON.stringify(item.data);
    writeFileSync(path, input);
    const result = spawnSync(process.execPath, ['scripts/jev-gate.mjs', path], {
      encoding: 'utf8', env: { ...process.env, OPENROUTER_API_KEY: '' }
    });
    assert.equal(result.status, 1, item.name);
    assert.equal(readFileSync(path, 'utf8'), input, 'Input must be preserved');
    const report = JSON.parse(readFileSync(path + '-jev.json', 'utf8'));
    assert.equal(report.preflight, item.expected, item.name);
    assert.equal(report.status, 'HOLD', 'Missing credential cannot authorize a PASS');
    assert.equal(report.error, 'MISSING_ENVIRONMENT_CREDENTIAL');
    assert.equal(report.decisions.length, 0);
  }
  const summary = { suite: 'independent Jev deterministic gate regression', result: 'PASS', cases: cases.length, networkRequests: 0 };
  writeFileSync('verification/jev-gate-council-tests.json', JSON.stringify(summary, null, 2));
  console.log(JSON.stringify(summary));
} finally {
  rmSync(directory, { recursive: true });
}
