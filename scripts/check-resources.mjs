import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const resourceRoot = join(root, 'entry/src/main/resources');

function readElements(qualifier, type) {
  const content = JSON.parse(readFileSync(join(resourceRoot, qualifier, 'element', `${type}.json`), 'utf8'));
  const entries = content[type];
  const map = new Map(entries.map(entry => [entry.name, entry.value]));
  assert.equal(map.size, entries.length, `${qualifier}/${type}: duplicate resource name`);
  return map;
}

function sameKeys(base, localized, label) {
  assert.deepEqual([...localized.keys()].sort(), [...base.keys()].sort(), `${label}: resource keys differ`);
}

function placeholders(text) {
  return (text.match(/%(?:\d+\$)?[dsf]/g) ?? []).sort();
}

const strings = readElements('base', 'string');
const plurals = readElements('base', 'plural');
const light = readElements('base', 'color');
const dark = readElements('dark', 'color');
sameKeys(light, dark, 'dark/color');

for (const locale of ['en', 'zh_CN']) {
  const translations = readElements(locale, 'string');
  sameKeys(strings, translations, `${locale}/string`);
  for (const [key, value] of translations) {
    assert.ok(value.length > 0, `${locale}/${key}: empty translation`);
    assert.deepEqual(placeholders(value), placeholders(strings.get(key)), `${locale}/${key}: format arguments differ`);
  }
  const quantities = readElements(locale, 'plural');
  sameKeys(plurals, quantities, `${locale}/plural`);
  for (const [key, values] of quantities) {
    assert.ok(values.some(value => value.quantity === 'other'), `${locale}/${key}: missing other quantity`);
    for (const value of values) {
      assert.deepEqual(placeholders(value.value), ['%d'], `${locale}/${key}: count argument missing`);
    }
  }
}

function luminance(hex) {
  assert.match(hex, /^#[\da-f]{6}$/i);
  const channels = [1, 3, 5].map(offset => parseInt(hex.slice(offset, offset + 2), 16) / 255);
  const linear = channels.map(value => value <= 0.04045 ? value / 12.92 : ((value + 0.055) / 1.055) ** 2.4);
  return linear[0] * 0.2126 + linear[1] * 0.7152 + linear[2] * 0.0722;
}

const pairs = [
  ['text_primary', 'page_background'], ['text_primary', 'surface_background'],
  ['text_secondary', 'page_background'], ['text_secondary', 'surface_background'],
  ['text_primary', 'input_background'], ['text_secondary', 'input_background'],
  ['input_placeholder', 'input_background'], ['accent', 'surface_background'],
  ['primary_button_text', 'primary_button_background'],
  ['secondary_button_text', 'secondary_button_background'],
  ['hero_text_primary', 'hero_background'], ['hero_text_secondary', 'hero_background'],
  ['hero_button_text', 'hero_button_background']
];
let minimumContrast = Infinity;
for (const [mode, palette] of [['light', light], ['dark', dark]]) {
  for (const [foreground, background] of pairs) {
    const first = luminance(palette.get(foreground));
    const second = luminance(palette.get(background));
    const contrast = (Math.max(first, second) + 0.05) / (Math.min(first, second) + 0.05);
    minimumContrast = Math.min(minimumContrast, contrast);
    assert.ok(contrast >= 4.5, `${mode}: ${foreground}/${background} contrast is ${contrast.toFixed(2)}:1`);
  }
}

function sources(path) {
  return readdirSync(path, { withFileTypes: true }).flatMap(entry => {
    const child = join(path, entry.name);
    return entry.isDirectory() ? sources(child) : entry.name.endsWith('.ets') ? [child] : [];
  });
}

const resources = { string: strings, plural: plurals, color: light };
for (const path of sources(join(root, 'entry/src/main/ets'))) {
  const code = readFileSync(path, 'utf8');
  assert.doesNotMatch(code, /#[\da-f]{6,8}\b/i, `${path}: hardcoded color`);
  assert.doesNotMatch(code, /[\u3400-\u9fff]/u, `${path}: hardcoded Chinese text`);
  for (const match of code.matchAll(/\$r\('app\.(string|plural|color)\.([\w]+)'/g)) {
    assert.ok(resources[match[1]].has(match[2]), `${path}: missing resource ${match[0]}`);
  }
}

console.log(`Resource checks passed: ${strings.size} strings in each locale; ${light.size} colors per theme; plural resources and references valid.`);
console.log(`Minimum enabled-text contrast across both themes: ${minimumContrast.toFixed(2)}:1.`);
