import { createHash } from 'node:crypto';
import { readFileSync, readdirSync, writeFileSync, mkdirSync } from 'node:fs';
import { join, relative } from 'node:path';
const ignored = new Set(['.git', '.build', 'DerivedData', 'node_modules', 'verification', 'verification-output']);
function walk(directory) {
  return readdirSync(directory, { withFileTypes: true }).flatMap(item => {
    if (ignored.has(item.name) || item.name === '.DS_Store') return [];
    const path = join(directory, item.name);
    return item.isDirectory() ? walk(path) : [path];
  });
}
const files = walk('.').sort().map(path => ({ path: relative('.', path).replaceAll('\\', '/'), sha256: createHash('sha256').update(readFileSync(path)).digest('hex') }));
const sourceHash = createHash('sha256').update(JSON.stringify(files)).digest('hex');
mkdirSync('verification', { recursive: true });
writeFileSync('verification/candidate-manifest.json', JSON.stringify({ sourceHash, files }, null, 2));
console.log(JSON.stringify({ sourceHash, files: files.length }));
