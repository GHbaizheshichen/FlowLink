import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
import vm from 'node:vm';
class HarmonyURL extends URL { get params() { return this.searchParams; } }
const context = vm.createContext({
  url: { URL: HarmonyURL },
  util: {
    TextDecoder: { create: (...args) => ({ decodeToString: bytes => new TextDecoder(...args).decode(bytes) }) },
    Base64Helper: class { decodeSync(text) { if (!/^[A-Za-z0-9+/]*={0,2}$/.test(text)) throw Error('base64'); return Buffer.from(text, 'base64'); } }
  },
  $r: (id, ...args) => ({ id, args })
});
const paths = ['subscription/ProxyNode', 'subscription/SubscriptionParser', 'vpn/TunnelConfig', 'vpn/IpAddress', 'native/XrayConfig'];
for (const file of paths) {
  const source = readFileSync(`entry/src/main/ets/${file}.ets`, 'utf8').replace(/^import .*;\r?\n/gm, '').replace(/^export /gm, '')
    .replace(/enum (\w+) \{([^}]+)\}/g, (_, name, members) => `const ${name} = {${members.replace(/=/g, ':')}}`);
  vm.runInContext(stripTypeScriptTypes(source, { mode: 'strip', disableExperimentalWarning: true }), context);
}
vm.runInContext('globalThis.api = { SubscriptionParser, XrayConfig, TunnelConfig, IpAddress }', context);
const { SubscriptionParser: parser, XrayConfig: config } = context.api;
const uri = 'vless://00000000-0000-4000-8000-000000000001@example.invalid:443?encryption=none&security=reality&type=tcp&flow=xtls-rprx-vision&fp=chrome&pbk=AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA&sid=0102&sni=example.com#Test%20Node';
assert.equal(parser.parse(uri).nodes.length, 1);
assert.equal(parser.parse(Buffer.from(uri).toString('base64')).nodes[0].name, 'Test Node');
for (const fingerprint of ['firefox', 'safari']) {
  const node = parser.parse(uri.replace('fp=chrome', `fp=${fingerprint}`)).nodes[0];
  assert.ok(node); assert.equal(node.fingerprint, fingerprint);
}
assert.equal(parser.parse(uri.replace('sni=example.com', 'servername=example.com')).nodes.length, 1);
for (const invalid of [uri.replace('security=reality', 'security=tls'), uri.replace('type=tcp', 'type=ws'),
  uri.replace('sid=0102', 'sid=xyz'), uri.replace('flow=xtls-rprx-vision', 'flow='),
  uri.replace(':443?', ':0?'), uri.replace('fp=chrome', 'fp=unknown'), uri.replace('encryption=none', 'encryption=other'),
  uri.replace('00000000-0000-4000-8000-000000000001', 'bad-id'), uri.replace('sni=example.com', 'sni=')]) {
  assert.equal(parser.parse(invalid).nodes.length, 0);
}
assert.equal(parser.parse('%%broken%%').nodes.length, 0);
const mixed = parser.parse(uri + '\nvmess://unsupported\n');
assert.equal(mixed.nodes.length, 1); assert.equal(mixed.skipped, 1);
const generated = JSON.parse(config.create(parser.parse(uri).nodes[0], 'test-local-token'));
assert.equal(generated.outbounds[0].streamSettings.security, 'reality');
assert.equal(generated.outbounds[0].settings.vnext[0].users[0].flow, 'xtls-rprx-vision');
assert.equal(generated.inbounds[0].listen, '127.0.0.1');
assert.equal(generated.inbounds[0].settings.auth, 'password');
assert.equal(generated.log.loglevel, 'none');
assert.equal(generated.dns.servers[0], 'https://1.1.1.1/dns-query');
assert.equal(generated.dns.queryStrategy, 'UseIP', 'AAAA must not be filtered out by IPv4-only DNS');
assert.equal(generated.routing.rules[0].outboundTag, 'dns-out');
const ipv6Node = parser.parse(uri.replace('example.invalid', '[2001:db8::10]')).nodes[0];
assert.ok(ipv6Node, 'bracketed IPv6 subscription server');
assert.equal(ipv6Node.server, '2001:db8::10');
assert.equal(JSON.parse(config.create(ipv6Node, 'test-local-token')).outbounds[0].settings.vnext[0].address, '2001:db8::10');
const vpn = context.api.TunnelConfig.create();
assert.equal(vpn.isIPv4Accepted, true);
assert.equal(vpn.isIPv6Accepted, true);
assert.ok(vpn.addresses.some(a => a.address.family === 1));
assert.ok(vpn.addresses.some(a => a.address.family === 2 && a.address.address === context.api.TunnelConfig.IPV6));
assert.deepEqual(Array.from(vpn.routes, r => [r.destination.address.family, r.destination.address.address, r.destination.prefixLength]), [[1, '0.0.0.0', 0], [2, '::', 0]]);
assert.ok(vpn.routes.every(r => r.isDefaultRoute && !r.hasGateway && r.interface === ''));
assert.ok(vpn.dnsAddresses.some(a => a.includes(':')));
const yaml = config.tunnel('test-local-token');
assert.ok(yaml.includes(`ipv4: ${context.api.TunnelConfig.IPV4}`));
assert.ok(yaml.includes(`ipv6: '${context.api.TunnelConfig.IPV6}'`));
const ip = context.api.IpAddress;
assert.equal(ip.normalize('2001:0DB8:0:0:0:0:0:1', 6), '2001:db8::1');
assert.equal(ip.normalize('2001:db8::1\n', 6), '2001:db8::1');
for (const invalid of ['192.0.2.1', '::ffff:c000:201', '::ffff:192.0.2.1', 'fe80::1%wlan0', '2001::db8::1', 'bad/host', '']) {
  assert.equal(ip.normalize(invalid, 6), '', `invalid IPv6: ${invalid}`);
}
assert.equal(ip.normalize('192.0.2.1', 4), '192.0.2.1');
assert.equal(ip.normalize('999.0.0.1', 4), '');
assert.equal(ip.normalize('192.000.2.1', 4), '');
if (process.argv[2]) {
  const real = parser.parse(readFileSync(process.argv[2], 'utf8'));
  assert.ok(real.nodes.length > 0);
  console.log(`Private subscription: ${real.nodes.length} supported, ${real.skipped} skipped (credentials omitted).`);
}
console.log('Subscription/config tests passed: supported URI and Base64, malformed and unsupported entries, authenticated loopback configuration.');
