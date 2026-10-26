import { execFileSync } from 'node:child_process';
import { readdirSync, readFileSync, writeFileSync, mkdirSync, existsSync } from 'node:fs';
import { resolve, join } from 'node:path';
const root = resolve(import.meta.dirname, '..');
const destination = join(root, 'entry/src/main/resources/rawfile/native-notices.txt');
const go = join(process.env.GOROOT, 'bin/go.exe');
const information = execFileSync(go, ['version', '-m', join(root, 'entry/libs/arm64-v8a/libharmony_xray.so')], {
  encoding: 'utf8', env: process.env
});
const modules = information.split(/\r?\n/).map(line => line.trim().split(/\s+/)).filter(fields => fields[0] === 'dep');
let output = readFileSync(join(root, 'native/THIRD_PARTY_NOTICES.md'), 'utf8') + '\n\n';
const sources = modules.map(([, name, version]) => ({
  name: `${name} ${version}`,
  directory: join(process.env.GOMODCACHE, `${name.replace(/[A-Z]/g, char => '!' + char.toLowerCase())}@${version}`)
}));
for (const directory of ['', 'src/core', 'third-part/hev-task-system', 'third-part/lwip', 'third-part/yaml']) {
  sources.push({ name: `Hev ${directory || 'tunnel'}`, directory: join(root, 'entry/src/main/cpp/third-party/hev-socks5-tunnel', directory) });
}
sources.push({ name: 'Go runtime and toolchain', directory: process.env.GOROOT });
for (const source of sources) {
  if (!source.directory || !existsSync(source.directory)) continue;
  output += `\n===== ${source.name} =====\n`;
  const names = readdirSync(source.directory).filter(name => /^(license|copying|notice|patents)(\.|$)/i.test(name));
  for (const name of names) {
    const path = join(source.directory, name);
    try { output += `\n--- ${name} ---\n${readFileSync(path, 'utf8')}\n`; } catch {}
  }
  // Fallback root module carries certificate data licensing in its bundle package.
  const certificateNotice = join(source.directory, 'bundle', 'LICENSE');
  if (existsSync(certificateNotice)) output += readFileSync(certificateNotice, 'utf8') + '\n';
}
mkdirSync(join(root, 'entry/src/main/resources/rawfile'), { recursive: true });
writeFileSync(destination, output);
console.log(`Collected native notices from ${sources.length} sources.`);
