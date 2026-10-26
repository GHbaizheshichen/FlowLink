import { getVersion, isAvailable, start as startXray, startTunnel as startHev,
  stop as stopCore, stats as getStats, beginLatencyBatch, measureLatency,
  cancelLatencyBatch, endLatencyBatch } from 'libproxy_core.so';
import { LatencyClient, LatencyMeasurement } from '../subscription/NodeLatency';

export class NativeCoreInfo {
  version: string = '';
  available: boolean = false;
}

export class NativeLatencyClient implements LatencyClient {
  begin(id: string): Promise<string> { return beginLatencyBatch(id); }
  async measure(config: string, id: string): Promise<LatencyMeasurement> {
    return JSON.parse(await measureLatency(config, id)) as LatencyMeasurement;
  }
  async cancel(id: string): Promise<void> { await cancelLatencyBatch(id); }
  async end(id: string): Promise<void> { await endLatencyBatch(id); }
}
export interface CoreExitAddresses { ipv4: string; ipv6: string; }
export interface TunnelStats { running: boolean; tx: number; rx: number; tx4: number; rx4: number; tx6: number; rx6: number; }

export class NativeCore {
  static getInfo(): NativeCoreInfo {
    const info = new NativeCoreInfo();
    info.version = getVersion();
    info.available = isAvailable();
    return info;
  }

  static start(config: string): Promise<string> { return startXray(config); }
  static startTunnel(fd: number, yaml: string): Promise<string> { return startHev(fd, yaml); }
  static async stop(): Promise<void> {
    const pending: Promise<string> = stopCore();
    await pending;
  }
  static async stats(): Promise<TunnelStats> {
    const pending: Promise<string> = getStats();
    return JSON.parse(await pending) as TunnelStats;
  }
}
