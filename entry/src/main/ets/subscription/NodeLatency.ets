export enum LatencyStatus {
  PENDING = 'pending', TESTING = 'testing', SUCCESS = 'success',
  TIMEOUT = 'timeout', FAILED = 'failed', CANCELLED = 'cancelled'
}

@ObservedV2
export class NodeLatency {
  nodeId: string;
  @Trace status: LatencyStatus = LatencyStatus.PENDING;
  @Trace latencyMs: number = 0;
  @Trace measuredAt: number = 0;

  constructor(nodeId: string) { this.nodeId = nodeId; }
}

export interface LatencyMeasurement { status: string; latencyMs: number; }
export function compareNodeLatency(left: NodeLatency | undefined, right: NodeLatency | undefined): number {
  return (left?.status === LatencyStatus.SUCCESS ? left.latencyMs : Number.MAX_SAFE_INTEGER) -
    (right?.status === LatencyStatus.SUCCESS ? right.latencyMs : Number.MAX_SAFE_INTEGER);
}
export interface LatencyClient {
  begin(id: string): Promise<string>;
  measure(config: string, id: string): Promise<LatencyMeasurement>;
  cancel(id: string): Promise<void>;
  end(id: string): Promise<void>;
}
