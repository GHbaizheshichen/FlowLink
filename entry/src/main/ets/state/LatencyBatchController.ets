import { util } from '@kit.ArkTS';
import { ProxyAppState } from './ProxyAppState';
import { ProxyNode } from '../subscription/ProxyNode';
import { NodeLatency, LatencyStatus, LatencyClient } from '../subscription/NodeLatency';
import { NativeLatencyClient } from '../native/NativeCore';
import { XrayConfig } from '../native/XrayConfig';
import { VpnStatus } from '../vpn/VpnState';

export class LatencyBatchController {
  private state: ProxyAppState;
  private client: LatencyClient;
  private id: string = '';
  private cancelled: boolean = false;

  constructor(state: ProxyAppState, client: LatencyClient = new NativeLatencyClient()) {
    this.state = state;
    this.client = client;
  }
  private allowed(): boolean {
    return this.state.initialized && this.state.nativeAvailable && !this.state.saving &&
      (this.state.vpnStatus === VpnStatus.IDLE || this.state.vpnStatus === VpnStatus.ERROR);
  }
  cancel(): void {
    if (!this.state.latencyRunning || this.state.latencyCancelling) { return; }
    this.cancelled = true;
    this.state.latencyCancelling = true;
    this.client.cancel(this.id).catch(() => {});
  }
  async start(input: ProxyNode[]): Promise<void> {
    if (this.state.latencyRunning) { return; }
    if (!this.allowed()) { this.state.latencyMessage = $r('app.string.latency_unavailable'); return; }
    // Freeze the filtered list; changing search/sort or leaving the page must
    // not change this batch's scope, nor modify the user's selected node.
    const available = new Set<ProxyNode>(this.state.nodes);
    const included = new Set<string>();
    const nodes = input.filter((node: ProxyNode) => {
      if (!available.has(node) || included.has(node.id)) { return false; }
      included.add(node.id);
      return true;
    });
    if (nodes.length === 0) { return; }
    this.id = util.generateRandomUUID(true);
    this.cancelled = false;
    this.state.latencyRunning = true;
    this.state.latencyCancelling = false;
    this.state.latencyCompleted = 0;
    this.state.latencyTotal = nodes.length;
    this.state.latencyMessage = undefined;
    const results = nodes.map((node: ProxyNode) => new NodeLatency(node.id));
    this.state.latencyResults = this.state.latencyResults.filter((result: NodeLatency) => !included.has(result.nodeId)).concat(results);
    let next: number = 0;
    try {
      const error = await this.client.begin(this.id);
      if (error) { throw new Error('latency_begin_failed'); }
      if (this.cancelled || !this.allowed()) {
        this.cancelled = true;
        await this.client.cancel(this.id);
      }
      const worker = async (): Promise<void> => {
        while (!this.cancelled && next < nodes.length) {
          if (!this.allowed()) { this.cancel(); break; }
          const index = next++;
          const result = results[index];
          result.status = LatencyStatus.TESTING;
          try {
            const measured = await this.client.measure(XrayConfig.forLatency(nodes[index]), this.id);
            if (this.cancelled) { result.status = LatencyStatus.CANCELLED; continue; }
            if (measured.status === LatencyStatus.SUCCESS && Number.isFinite(measured.latencyMs) && measured.latencyMs > 0) {
              result.status = LatencyStatus.SUCCESS;
              result.latencyMs = Math.round(measured.latencyMs);
            } else if (measured.status === LatencyStatus.TIMEOUT) { result.status = LatencyStatus.TIMEOUT; }
            else if (measured.status === LatencyStatus.CANCELLED) { result.status = LatencyStatus.CANCELLED; }
            else { result.status = LatencyStatus.FAILED; }
          } catch { result.status = this.cancelled ? LatencyStatus.CANCELLED : LatencyStatus.FAILED; }
          result.measuredAt = Date.now();
          if (result.status !== LatencyStatus.CANCELLED) { this.state.latencyCompleted++; }
        }
      };
      const workers: Promise<void>[] = [];
      for (let index = 0; index < Math.min(3, nodes.length); index++) { workers.push(worker()); }
      await Promise.all(workers);
      this.state.latencyMessage = this.cancelled ?
        $r('app.string.latency_cancelled_summary', this.state.latencyCompleted, this.state.latencyTotal) :
        $r('app.string.latency_finished', results.filter((result: NodeLatency) => result.status === LatencyStatus.SUCCESS).length,
          this.state.latencyTotal);
    } catch { this.state.latencyMessage = $r('app.string.latency_unavailable'); }
    finally {
      // Keep running=true until every native worker and its isolated core have
      // closed; queued late results can never overwrite a newly started batch.
      try { await this.client.end(this.id); } catch {}
      results.forEach((result: NodeLatency) => {
        if (result.status === LatencyStatus.PENDING || result.status === LatencyStatus.TESTING) {
          result.status = this.cancelled ? LatencyStatus.CANCELLED : LatencyStatus.FAILED;
        }
      });
      this.state.latencyRunning = false;
      this.state.latencyCancelling = false;
      this.id = '';
    }
  }
}
