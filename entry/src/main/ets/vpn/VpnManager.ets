import { common, wantAgent } from '@kit.AbilityKit';
import { commonEventManager, BusinessError } from '@kit.BasicServicesKit';
import { http, vpnExtension } from '@kit.NetworkKit';
import { util } from '@kit.ArkTS';
import { backgroundTaskManager } from '@kit.BackgroundTasksKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { ProxyNode } from '../subscription/ProxyNode';
import { XrayConfig } from '../native/XrayConfig';
import { ProxyAppState } from '../state/ProxyAppState';
import { VpnStatus } from './VpnState';
import { IpAddress } from './IpAddress';
import { BUNDLE, VPN_COMMAND, VPN_STATE, VpnSnapshot, publishVpn } from './VpnChannel';

export class VpnManager {
  private state: ProxyAppState;
  private context?: common.UIAbilityContext;
  private subscriber?: commonEventManager.CommonEventSubscriber;
  private session: string = '';
  private verification: string = '';
  private timer: number = -1;
  private deadline: number = 0;
  private background: boolean = false;
  constructor(state: ProxyAppState) { this.state = state; }
  async initialize(context: common.UIAbilityContext): Promise<void> {
    this.context = context;
    this.subscriber = await commonEventManager.createSubscriber({ events: [VPN_STATE], publisherBundleName: BUNDLE });
    commonEventManager.subscribe(this.subscriber, (error, event) => {
      if (!error && event.data) { this.receive(event.data); }
    });
    await publishVpn(VPN_COMMAND, 'query');
  }
  async toggle(node?: ProxyNode): Promise<void> {
    if (this.state.vpnStatus === VpnStatus.CONNECTED || this.state.vpnStatus === VpnStatus.VERIFYING) {
      this.state.vpnStatus = VpnStatus.STOPPING;
      this.deadline = Date.now() + 30000;
      await publishVpn(VPN_COMMAND, `stop:${this.session}`);
      return;
    }
    if (this.state.vpnStatus === VpnStatus.STARTING || this.state.vpnStatus === VpnStatus.STOPPING) { return; }
    if (!node) { this.state.connectionMessage = $r('app.string.vpn_select_node'); return; }
    this.session = util.generateRandomUUID(true);
    this.verification = '';
    this.state.exitIp = '';
    this.state.exitIpv6 = '';
    this.state.vpnStatus = VpnStatus.STARTING;
    this.state.connectionMessage = undefined;
    this.deadline = Date.now() + 90000;
    this.startPolling();
    const token = util.generateRandomUUID(true).replace(/-/g, '');
    try {
      await vpnExtension.startVpnExtensionAbility({ bundleName: BUNDLE, abilityName: 'ProxyVpnAbility',
        parameters: { session: this.session, token: token, config: XrayConfig.create(node, token) } });
    } catch { this.showError(); }
  }
  private receive(data: string): void {
    try {
      if (data.length > 2048) { return; }
      const snapshot = JSON.parse(data) as VpnSnapshot;
      if (!snapshot.session || (this.session && snapshot.session !== this.session)) { return; }
      this.session = snapshot.session;
      this.state.vpnStatus = snapshot.status;
      this.state.exitIp = snapshot.ip;
      this.state.exitIpv6 = snapshot.ipv6 ?? '';
      if (snapshot.status === VpnStatus.VERIFYING) {
        if (this.verification !== snapshot.session) {
          this.verification = snapshot.session;
          this.verify(snapshot.session, snapshot.ip, snapshot.ipv6 ?? '');
        }
      } else if (snapshot.status === VpnStatus.CONNECTED) {
        this.deadline = Date.now() + 15000;
        this.startPolling();
      } else if (snapshot.status === VpnStatus.ERROR || snapshot.status === VpnStatus.IDLE) {
        clearInterval(this.timer); this.timer = -1;
        this.stopBackground();
        if (snapshot.status === VpnStatus.ERROR) { this.state.connectionMessage = $r('app.string.vpn_connection_failed'); }
      }
    } catch { this.showError(); }
  }
  private startPolling(): void {
    if (this.timer !== -1) { return; }
    this.timer = setInterval(() => {
      if (Date.now() > this.deadline) {
        publishVpn(VPN_COMMAND, `stop:${this.session}`).catch(() => {});
        vpnExtension.stopVpnExtensionAbility({ bundleName: BUNDLE, abilityName: 'ProxyVpnAbility' }).catch(() => {});
        this.showError();
      } else { publishVpn(VPN_COMMAND, 'query').catch(() => {}); }
    }, 3000);
  }
  private async verifyFamily(session: string, expectedIp: string, family: number): Promise<void> {
    const request = http.createHttp();
    try {
      // This request originates in the UI process, so it must traverse the system TUN.
      const host = family === 4 ? 'api4.ipify.org' : 'api6.ipify.org';
      const response = await request.request(`https://${host}?check=${session}`, {
        method: http.RequestMethod.GET, expectDataType: http.HttpDataType.STRING,
        usingCache: false, usingProxy: false, connectTimeout: 10000, readTimeout: 15000, maxLimit: 1024
      });
      if (session !== this.session || this.state.vpnStatus !== VpnStatus.VERIFYING) { return; }
      if (response.responseCode !== 200 || typeof response.result !== 'string' ||
        IpAddress.normalize(response.result, family) !== expectedIp) {
        hilog.error(0, 'HarmonyProxyVpn', 'System VPN egress check failed: HTTP %{public}d', response.responseCode);
        throw new Error('egress_mismatch');
      }
    } finally { request.destroy(); }
  }
  private async verify(session: string, expectedIp: string, expectedIpv6: string): Promise<void> {
    let stage: string = 'https_dual_stack';
    try {
      if (!expectedIp && !expectedIpv6) { throw new Error('no_exit_address'); }
      const checks: Promise<void>[] = [];
      if (expectedIp) { checks.push(this.verifyFamily(session, expectedIp, 4)); }
      if (expectedIpv6) { checks.push(this.verifyFamily(session, expectedIpv6, 6)); }
      await Promise.all(checks);
      if (session !== this.session || this.state.vpnStatus !== VpnStatus.VERIFYING) { return; }
      stage = 'background_task';
      await this.startBackground();
      await publishVpn(VPN_COMMAND, `verified:${session}`);
    } catch (error) {
      hilog.error(0, 'HarmonyProxyVpn', 'System VPN check failed at %{public}s, code %{public}d',
        stage, (error as BusinessError).code ?? -1);
      if (session === this.session && this.state.vpnStatus === VpnStatus.VERIFYING) {
        await publishVpn(VPN_COMMAND, `failed:${session}`).catch(() => {});
      }
    }
  }
  private async startBackground(): Promise<void> {
    if (this.background || !this.context) { return; }
    const agent = await wantAgent.getWantAgent({
      wants: [{ bundleName: BUNDLE, abilityName: 'EntryAbility' }],
      actionType: wantAgent.OperationType.START_ABILITY, requestCode: 1,
      wantAgentFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
    });
    await backgroundTaskManager.startBackgroundRunning(this.context, backgroundTaskManager.BackgroundMode.DATA_TRANSFER, agent);
    this.background = true;
  }
  private async stopBackground(): Promise<void> {
    if (this.background && this.context) {
      try { await backgroundTaskManager.stopBackgroundRunning(this.context); } catch {}
      this.background = false;
    }
  }
  private showError(): void {
    clearInterval(this.timer); this.timer = -1;
    this.state.vpnStatus = VpnStatus.ERROR;
    this.state.connectionMessage = $r('app.string.vpn_connection_failed');
    this.stopBackground();
  }
}
