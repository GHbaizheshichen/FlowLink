import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
import vm from 'node:vm';
import { randomUUID } from 'node:crypto';

const context = vm.createContext({ util: { generateRandomUUID: () => randomUUID() }, $r: (id, ...args) => ({ id, args }),
  NativeLatencyClient: class {} });
for (const file of ['subscription/ProxyNode', 'subscription/NodeLatency', 'vpn/VpnState', 'vpn/TunnelConfig',
  'native/XrayConfig', 'state/ProxyAppState', 'state/LatencyBatchController']) {
  const source = readFileSync(`entry/src/main/ets/${file}.ets`, 'utf8')
    .replace(/^import .*;\r?\n/gm, '').replace(/^export /gm, '')
    .replace(/^@ObservedV2\s*\r?\n/gm, '').replace(/@Trace\s+/g, '')
    .replace(/enum (\w+) \{([^}]+)\}/g, (_, name, members) => `const ${name} = {${members.replace(/=/g, ':')}}`);
  vm.runInContext(stripTypeScriptTypes(source, { mode: 'strip', disableExperimentalWarning: true }), context);
}
vm.runInContext('globalThis.api = {ProxyAppState, LatencyBatchController, NodeLatency, LatencyStatus, compareNodeLatency}', context);
const { ProxyAppState, LatencyBatchController, LatencyStatus, compareNodeLatency } = context.api;
const tick = () => new Promise(resolve => setImmediate(resolve));
const makeState = (count = 10) => {
  const state = new ProxyAppState();
  state.initialized = state.nativeAvailable = true;
  state.nodes = Array.from({ length: count }, (_, index) => ({ id: `node-${index}`, name: `Test ${index}`,
    server: `node-${index}.invalid`, protocol: 'vless', port: 443, uuid: '00000000-0000-4000-8000-000000000001' }));
  state.selectedNodeId = 'node-4';
  return state;
};
class Client {
  pending = []; calls = []; active = 0; maximum = 0; begins = 0; ends = 0; cancels = 0;
  async begin() { this.begins++; return ''; }
  measure(config, id) {
    assert.equal(JSON.parse(config).inbounds.length, 0, 'latency probes must not bind the VPN SOCKS port');
    this.calls.push({ config, id });
    this.maximum = Math.max(this.maximum, ++this.active);
    return new Promise(resolve => this.pending.push(result => { this.active--; resolve(result); }));
  }
  async cancel() { this.cancels++; }
  async end() { assert.equal(this.active, 0, 'cleanup must wait for active probes'); this.ends++; }
}
const state = makeState();
const client = new Client();
const runner = new LatencyBatchController(state, client);
const running = runner.start(state.nodes);
await tick();
assert.equal(client.active, 3);
let completed = 0;
while (client.pending.length) {
  client.pending.shift()({ status: completed++ === 2 ? 'timeout' : 'success', latencyMs: 100 + completed });
  await tick();
}
await running;
assert.equal(client.maximum, 3);
assert.equal(client.calls.length, state.nodes.length);
assert.equal(state.latencyCompleted, state.nodes.length);
assert.equal(state.selectedNodeId, 'node-4', 'testing must not select a different node');
assert.equal(state.latencyResults.filter(r => r.status === LatencyStatus.TIMEOUT).length, 1);
assert.equal(state.latencyRunning, false);
assert.equal(client.ends, 1);
assert.ok(compareNodeLatency({ status: 'success', latencyMs: 80 }, { status: 'success', latencyMs: 100 }) < 0);
assert.ok(compareNodeLatency({ status: 'success', latencyMs: 80 }, { status: 'timeout', latencyMs: 0 }) < 0);
assert.ok(compareNodeLatency(undefined, { status: 'success', latencyMs: 80 }) > 0);

const cancelledState = makeState();
const cancelClient = new Client();
const cancelRunner = new LatencyBatchController(cancelledState, cancelClient);
const cancelledRun = cancelRunner.start(cancelledState.nodes);
await tick();
cancelRunner.cancel();
await cancelRunner.start(cancelledState.nodes);
assert.equal(cancelClient.begins, 1, 'new run must not start before old workers drain');
assert.equal(cancelledState.latencyCancelling, true);
for (const resolve of cancelClient.pending.splice(0)) resolve({ status: 'success', latencyMs: 1 });
await cancelledRun;
assert.equal(cancelClient.calls.length, 3, 'cancelled queue must not start more work');
assert.equal(cancelledState.latencyCompleted, 0);
assert.ok(cancelledState.latencyResults.every(r => r.status === 'cancelled'), 'late successes must not overwrite cancellation');
assert.equal(cancelledState.selectedNodeId, 'node-4');

const blocked = makeState(); blocked.vpnStatus = 'connected';
const blockedClient = new Client();
await new LatencyBatchController(blocked, blockedClient).start(blocked.nodes);
assert.equal(blockedClient.begins, 0, 'active VPN must prevent latency jobs');
const subsetState = makeState(); const subsetClient = new Client();
const subset = new LatencyBatchController(subsetState, subsetClient).start([
  ...subsetState.nodes.slice(0, 2), subsetState.nodes[0], { ...subsetState.nodes[2] }
]);
await tick();
for (const resolve of subsetClient.pending.splice(0)) resolve({ status: 'failed', latencyMs: 0 });
await subset;
assert.equal(subsetClient.calls.length, 2, 'duplicate and stale node objects must not create extra jobs');
assert.ok(subsetState.latencyResults.every(r => r.status === 'failed' && r.latencyMs === 0));
console.log('Latency scheduler tests passed: 3-worker limit, scope, progress, cancellation, stale results, cleanup, selection, VPN guard and sorting.');
