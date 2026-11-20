// Uruchamia kod węzłów Code z wygenerowanych workflow z atrapami $input / $() / $now.
import { readFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { DateTime } from 'luxon';

const HERE = dirname(fileURLToPath(import.meta.url));
export const WF_DIR = join(HERE, '..', 'workflows');
export const fixture = (n) => readFileSync(join(HERE, 'fixtures', n), 'utf8')
  .replaceAll('__RECENT__', new Date(Date.now() - 3600e3).toUTCString());

export function loadWorkflow(file) { return JSON.parse(readFileSync(join(WF_DIR, file), 'utf8')); }
export function codeOf(wf, nodeName) {
  const n = wf.nodes.find((x) => x.name === nodeName);
  if (!n) throw new Error('No node ' + nodeName);
  return n.parameters.jsCode;
}

const AsyncFunction = Object.getPrototypeOf(async function () {}).constructor;
const wrapItems = (arr) => arr.map((x) => (x && x.json ? x : { json: x }));

// nodes: { 'Node name': [items] }, input: [items]
export async function runCode(jsCode, { input = [], nodes = {}, executed = [] } = {}) {
  const inItems = wrapItems(input);
  const $input = { all: () => inItems, first: () => inItems[0], item: inItems[0] };
  const $ = (name) => {
    const items = nodes[name];
    if (!items && !executed.includes(name)) throw new Error(`Node "${name}" not provided to harness`);
    const w = wrapItems(items || []);
    return { all: () => w, first: () => w[0], isExecuted: executed.includes(name) || !!items };
  };
  const ctx = {
    helpers: {
      getBinaryDataBuffer: async (i, prop) => Buffer.from(inItems[i].binary[prop].data, 'base64'),
    },
  };
  const fn = new AsyncFunction('$input', '$', '$now', '$execution', jsCode);
  return fn.call(ctx, $input, $, DateTime.now(), { id: 'test-exec' });
}
