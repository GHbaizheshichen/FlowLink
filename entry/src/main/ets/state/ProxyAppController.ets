import { common } from '@kit.AbilityKit';
import { url } from '@kit.ArkTS';
import { NativeCore } from '../native/NativeCore';
import { SubscriptionRepository } from '../subscription/SubscriptionRepository';
import { SubscriptionClient } from '../subscription/SubscriptionClient';
import { VpnStatus } from '../vpn/VpnState';
import { VpnManager } from '../vpn/VpnManager';
import { ProxyAppState } from './ProxyAppState';
import { LatencyBatchController } from './LatencyBatchController';
import { ProxyNode } from '../subscription/ProxyNode';

export class ProxyAppController {
  private state: ProxyAppState;
  private repository: SubscriptionRepository = new SubscriptionRepository();
  private initializing: boolean = false;
  private vpn: VpnManager;
  private latency: LatencyBatchController;

  constructor(state: ProxyAppState) {
    this.state = state;
    this.vpn = new VpnManager(state);
    this.latency = new LatencyBatchController(state);
  }

  async initialize(context: common.UIAbilityContext): Promise<void> {
    if (this.initializing || this.state.initialized) {
      return;
    }
    this.initializing = true;
    try {
      const info = NativeCore.getInfo();
      this.state.nativeVersion = info.version;
      this.state.nativeAvailable = info.available;
      await this.repository.initialize(context);
      this.state.subscriptionAddress = await this.repository.readAddress();
      this.state.subscriptionName = await this.repository.readName();
      this.state.initialized = true;
      await this.vpn.initialize(context);
      if (this.state.subscriptionAddress) { await this.saveSubscription(this.state.subscriptionAddress); }
    } catch {
      this.state.subscriptionMessage = $r('app.string.initialization_failed');
      this.state.subscriptionFailed = true;
    } finally {
      this.initializing = false;
    }
  }

  async saveSubscription(input: string, name: string = this.state.subscriptionName): Promise<boolean> {
    if (this.state.latencyRunning) {
      this.state.subscriptionMessage = $r('app.string.latency_busy');
      this.state.subscriptionFailed = true;
      return false;
    }
    if (this.state.vpnStatus !== VpnStatus.IDLE && this.state.vpnStatus !== VpnStatus.ERROR) {
      this.state.subscriptionMessage = $r('app.string.disconnect_before_edit');
      this.state.subscriptionFailed = true;
      return false;
    }
    if (this.state.saving || !this.state.initialized) {
      return false;
    }
    const address = input.trim();
    if (address.length > 4096 || !this.isHttpAddress(address)) {
      this.state.subscriptionMessage = $r('app.string.subscription_address_invalid');
      this.state.subscriptionFailed = true;
      return false;
    }
    this.state.saving = true;
    this.state.subscriptionMessage = undefined;
    this.state.subscriptionFailed = false;
    try {
      const result = await SubscriptionClient.load(address);
      // Keep the last usable subscription and node selection when refresh fails.
      if (result.nodes.length === 0) {
        this.state.subscriptionMessage = result.message;
        this.state.subscriptionFailed = true;
        return false;
      }
      await this.repository.saveName(name.trim());
      await this.repository.saveAddress(address);
      const selected = address === this.state.subscriptionAddress ? this.state.selectedNode() : undefined;
      this.state.subscriptionAddress = address;
      this.state.subscriptionName = name.trim();
      this.state.nodes = result.nodes;
      this.state.latencyResults = [];
      this.state.latencyMessage = undefined;
      this.state.selectedNodeId = selected ? (result.nodes.find((node) => node.server === selected.server &&
        node.port === selected.port && node.uuid === selected.uuid)?.id ?? result.nodes[0].id) : result.nodes[0].id;
      this.state.subscriptionUpdatedAt = new Date().toLocaleString();
      this.state.subscriptionMessage = result.message;
      this.state.subscriptionFailed = result.nodes.length === 0;
      return true;
    } catch {
      this.state.subscriptionMessage = $r('app.string.subscription_save_failed');
      this.state.subscriptionFailed = true;
      return false;
    } finally {
      this.state.saving = false;
    }
  }

  async clearSubscription(): Promise<void> {
    if (this.state.latencyRunning) { return; }
    if (this.state.vpnStatus !== VpnStatus.IDLE && this.state.vpnStatus !== VpnStatus.ERROR) {
      this.state.subscriptionMessage = $r('app.string.disconnect_before_edit');
      this.state.subscriptionFailed = true;
      return;
    }
    if (this.state.saving || !this.state.initialized) {
      return;
    }
    this.state.saving = true;
    this.state.subscriptionMessage = undefined;
    this.state.subscriptionFailed = false;
    try {
      await this.repository.saveAddress('');
      await this.repository.saveName('');
      this.state.subscriptionAddress = '';
      this.state.subscriptionName = '';
      this.state.subscriptionUpdatedAt = '';
      this.state.nodes = [];
      this.state.latencyResults = [];
      this.state.latencyMessage = undefined;
      this.state.selectedNodeId = '';
      this.state.subscriptionMessage = $r('app.string.subscription_address_cleared');
    } catch {
      this.state.subscriptionMessage = $r('app.string.subscription_clear_failed');
      this.state.subscriptionFailed = true;
    } finally {
      this.state.saving = false;
    }
  }

  selectNode(id: string): void {
    if (this.state.saving || this.state.latencyRunning) { return; }
    if (this.state.vpnStatus !== VpnStatus.IDLE && this.state.vpnStatus !== VpnStatus.ERROR) { return; }
    if (this.state.nodes.some((node) => node.id === id)) {
      this.state.selectedNodeId = id;
      this.state.connectionMessage = undefined;
    }
  }

  explainConnection(): void {
    if (this.state.saving || this.state.latencyRunning) { return; }
    this.vpn.toggle(this.state.selectedNode()).catch(() => {
      this.state.connectionMessage = $r('app.string.vpn_connection_failed');
    });
  }

  toggleLatency(nodes: ProxyNode[]): void {
    if (this.state.latencyRunning) { this.latency.cancel(); }
    else { this.latency.start(nodes); }
  }

  private isHttpAddress(address: string): boolean {
    try {
      const parsed = new url.URL(address);
      return (parsed.protocol === 'https:' || parsed.protocol === 'http:') &&
        parsed.hostname.length > 0 && parsed.username.length === 0 && parsed.password.length === 0;
    } catch {
      return false;
    }
  }
}
