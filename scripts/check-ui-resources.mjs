import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('../', import.meta.url));
const resources = path.join(root, 'entry/src/main/resources');
const read = (qualifier, kind) => {
  const entries = JSON.parse(fs.readFileSync(path.join(resources, qualifier, `element/${kind}.json`), 'utf8'))[kind];
  const values = new Map(entries.map(item => [item.name, item.value]));
  assert.equal(values.size, entries.length, `Duplicate ${kind} names in ${qualifier}`);
  return values;
};
const strings = read('base', 'string');
for (const qualifier of ['en', 'zh_CN']) {
  const localized = read(qualifier, 'string');
  assert.deepEqual([...localized.keys()].sort(), [...strings.keys()].sort(), `${qualifier}: missing translation`);
  for (const [name, value] of strings) {
    const placeholders = text => (text.match(/%\d+\$[dsf]|%[dsf]/g) ?? []).sort();
    assert.deepEqual(placeholders(localized.get(name)), placeholders(value), `${qualifier}: format arguments for ${name}`);
  }
}
const colors = { base: read('base', 'color'), dark: read('dark', 'color') };
assert.deepEqual([...colors.base.keys()].sort(), [...colors.dark.keys()].sort(), 'Missing theme token');
const luminance = hex => {
  const channels = hex.slice(1).match(/../g).map(channel => {
    const value = parseInt(channel, 16) / 255;
    return value <= .04045 ? value / 12.92 : ((value + .055) / 1.055) ** 2.4;
  });
  return channels[0] * .2126 + channels[1] * .7152 + channels[2] * .0722;
};
const pairs = [
  ['text_primary', 'page_background'], ['text_secondary', 'page_background'],
  ['text_primary', 'surface_background'], ['text_secondary', 'surface_background'],
  ['primary_button_text', 'primary_button_background'], ['accent', 'selected_background'],
  ['danger', 'danger_background'], ...['hk', 'jp', 'sg', 'de', 'other'].map(region => ['region_text', `region_${region}`])
];
for (const [qualifier, palette] of Object.entries(colors)) {
  for (const [foreground, background] of pairs) {
    const [darker, lighter] = [luminance(palette.get(foreground)), luminance(palette.get(background))].sort((a, b) => a - b);
    const contrast = (lighter + .05) / (darker + .05);
    assert(contrast >= 4.5, `${qualifier}: ${foreground}/${background} is only ${contrast.toFixed(2)}:1`);
  }
}
const walk = directory => fs.readdirSync(directory, { withFileTypes: true }).flatMap(entry => {
  const filename = path.join(directory, entry.name);
  return entry.isDirectory() ? walk(filename) : [filename];
});
const media = new Set(fs.readdirSync(path.join(resources, 'base/media')).map(name => path.parse(name).name));
const sources = walk(path.join(root, 'entry/src/main/ets')).filter(filename => filename.endsWith('.ets'));
for (const filename of sources) {
  const source = fs.readFileSync(filename, 'utf8');
  assert(!/@(?:Component|State|Prop|Link|Observed|Watch|Provide|Consume)\b/.test(source), `${filename}: legacy decorator`);
  for (const [, kind, name] of source.matchAll(/\$r\('app\.(string|color|media)\.([^']+)'/g)) {
    const inventory = kind === 'string' ? strings : kind === 'color' ? colors.base : media;
    assert(inventory.has(name), `${filename}: missing ${kind}.${name}`);
  }
}
console.log(`UI resource checks passed: ${strings.size} strings across 3 locales, ${colors.base.size} paired colors, ` +
  `${pairs.length * 2} contrast checks and ${sources.length} ArkTS files with V2 decorators.`);
