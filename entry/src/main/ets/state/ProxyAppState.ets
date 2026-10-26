import { ProxyNode } from '../subscription/ProxyNode';
import { VpnStatus } from '../vpn/VpnState';
import { NodeLatency } from '../subscription/NodeLatency';

@ObservedV2
export class ProxyAppState {
  @Trace appearance: number = -1;
  @Trace initialized: boolean = false;
  @Trace saving: boolean = false;
  @Trace subscriptionAddress: string = '';
  @Trace subscriptionName: string = '';
  @Trace subscriptionUpdatedAt: string = '';
  @Trace subscriptionMessage?: Resource;
  @Trace subscriptionFailed: boolean = false;
  @Trace nodes: ProxyNode[] = [];
  @Trace selectedNodeId: string = '';
  @Trace vpnStatus: VpnStatus = VpnStatus.IDLE;
  @Trace connectionMessage?: Resource;
  @Trace nativeVersion: string = '';
  @Trace nativeAvailable: boolean = false;
  @Trace exitIp: string = '';
  @Trace exitIpv6: string = '';
  @Trace latencyRunning: boolean = false;
  @Trace latencyCancelling: boolean = false;
  @Trace latencyCompleted: number = 0;
  @Trace latencyTotal: number = 0;
  @Trace latencyResults: NodeLatency[] = [];
  @Trace latencyMessage?: Resource;

  selectedNode(): ProxyNode | undefined {
    return this.nodes.find((node: ProxyNode) => node.id === this.selectedNodeId);
  }
}
