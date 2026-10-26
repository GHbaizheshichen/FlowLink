import { Want } from '@kit.AbilityKit';
import { vpnExtension, VpnExtensionAbility } from '@kit.NetworkKit';
import { commonEventManager, BusinessError } from '@kit.BasicServicesKit';
import { fileIo } from '@kit.CoreFileKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { NativeCore, CoreExitAddresses } from '../native/NativeCore';
import { XrayConfig } from '../native/XrayConfig';
import { BUNDLE, VPN_COMMAND, VPN_STATE, VpnSnapshot, publishVpn } from './VpnChannel';
import { VpnStatus } from './VpnState';
import { IpAddress } from './IpAddress';
import { TunnelConfig } from './TunnelConfig';

export default class ProxyVpnAbility extends VpnExtensionAbility {
  private connection?: vpnExtension.VpnConnection;
  private subscriber?: commonEventManager.CommonEventSubscriber;
  private snapshot: VpnSnapshot = new VpnSnapshot();
  private created: boolean = false;
  private fd: number = -1;
  private cancelled: boolean = false;
  private starting?: Promise<void>;
  private cleaning?: Promise<void>;
  private watchdog: number = -1;
  private monitor: number = -1;
  private stage: string = 'subscriber';

  onCreate(want: Want): void {
    this.starting = this.start(want);
  }
  private async start(want: Want): Promise<void> {
    try {
      this.subscriber = await commonEventManager.createSubscriber({
        events: [VPN_COMMAND], publisherBundleName: BUNDLE
      });
      commonEventManager.subscribe(this.subscriber, (error, event) => {
        if (!error) { this.command(event.data ?? ''); }
      });
      const params = want.parameters;
      this.stage = 'parameters';
      const session = params?.session;
      const config = params?.config;
      const token = params?.token;
      if (typeof session !== 'string' || typeof config !== 'string' || typeof token !== 'string' ||
        config.length > 65536 || !/^[a-f0-9]{32}$/.test(token)) { throw new Error('invalid_session'); }
      this.snapshot.session = session;
      await this.update(VpnStatus.STARTING);
      this.connection = vpnExtension.createVpnConnection(this.context);
      this.stage = 'protect';
      // All Go/Hev outbound sockets live in this dedicated VPN process.
      await this.connection.protectProcessNet();
      this.stage = 'core';
      const ip = await NativeCore.start(config);
      if (ip.startsWith('error:')) { this.stage = ip; throw new Error('core_failed'); }
      if (this.cancelled) { return; }
      const exits = JSON.parse(ip) as CoreExitAddresses;
      this.snapshot.ip = IpAddress.normalize(exits.ipv4, 4);
      this.snapshot.ipv6 = IpAddress.normalize(exits.ipv6, 6);
      if (!this.snapshot.ip && !this.snapshot.ipv6) { throw new Error('invalid_probe'); }
      this.stage = 'create_tun';
      const configVpn = TunnelConfig.create();
      this.fd = await this.connection.create(configVpn);
      this.created = true;
      this.stage = 'tunnel';
      if (this.cancelled) { return; }
      const result = await NativeCore.startTunnel(this.fd, XrayConfig.tunnel(token));
      if (result) { throw new Error('tunnel_init'); }
      if (this.cancelled) { return; }
      await this.update(VpnStatus.VERIFYING);
      this.watchdog = setTimeout(() => { this.fail('verification_timeout'); }, 30000);
    } catch (error) {
      // Never log an exception message from a network/configuration operation.
      hilog.error(0, 'HarmonyProxyVpn', 'VPN initialization failed at %{public}s, code %{public}d',
        this.stage, (error as BusinessError).code ?? -1);
      await this.fail('connection_failed');
    }
  }
  private command(data: string): void {
    if (data === 'query') { this.emit(); return; }
    if (data === `stop:${this.snapshot.session}`) {
      this.cancelled = true;
      this.update(VpnStatus.STOPPING);
      this.stopSession().catch(() => {});
    } else if (data === `verified:${this.snapshot.session}` && this.snapshot.status === VpnStatus.VERIFYING) {
      this.confirmTunnel().catch(() => { this.fail('tunnel_check'); });
    } else if (data === `failed:${this.snapshot.session}` && this.snapshot.status === VpnStatus.VERIFYING) {
      this.fail('verification_failed');
    }
  }
  private async confirmTunnel(): Promise<void> {
    const stats = await NativeCore.stats();
    if (this.cancelled || this.snapshot.status !== VpnStatus.VERIFYING) { return; }
    if (!stats.running || stats.tx === 0 || stats.rx === 0) { await this.fail('no_tunnel_traffic'); return; }
    if (this.snapshot.ip && (stats.tx4 === 0 || stats.rx4 === 0)) { await this.fail('no_ipv4_tunnel_traffic'); return; }
    if (this.snapshot.ipv6 && (stats.tx6 === 0 || stats.rx6 === 0)) { await this.fail('no_ipv6_tunnel_traffic'); return; }
    clearTimeout(this.watchdog);
    hilog.info(0, 'HarmonyProxyVpn', 'TUN verified: tx=%{public}d rx=%{public}d', stats.tx, stats.rx);
    hilog.info(0, 'HarmonyProxyVpn', 'TUN families: tx4=%{public}d rx4=%{public}d tx6=%{public}d rx6=%{public}d',
      stats.tx4, stats.rx4, stats.tx6, stats.rx6);
    await this.update(VpnStatus.CONNECTED);
    if (this.monitor === -1) {
      this.monitor = setInterval(() => {
        NativeCore.stats().then((current) => {
          if (!current.running && !this.cancelled) { this.fail('tunnel_stopped'); }
        }).catch(() => { this.fail('tunnel_check'); });
      }, 5000);
    }
  }
  private async stopSession(): Promise<void> {
    await this.starting;
    await this.cleanup();
    await this.update(VpnStatus.IDLE);
    await vpnExtension.stopVpnExtensionAbility({ bundleName: BUNDLE, abilityName: 'ProxyVpnAbility' });
  }
  private async fail(code: string): Promise<void> {
    hilog.error(0, 'HarmonyProxyVpn', 'VPN session failed: %{public}s', code);
    const stats = await NativeCore.stats();
    hilog.info(0, 'HarmonyProxyVpn', 'TUN state: running=%{public}s tx=%{public}d rx=%{public}d',
      stats.running ? 'true' : 'false', stats.tx, stats.rx);
    this.cancelled = true;
    this.snapshot.error = code;
    await this.cleanup();
    await this.update(VpnStatus.ERROR);
    vpnExtension.stopVpnExtensionAbility({ bundleName: BUNDLE, abilityName: 'ProxyVpnAbility' }).catch(() => {});
  }
  private cleanup(): Promise<void> {
    if (!this.cleaning) { this.cleaning = this.release(); }
    return this.cleaning;
  }
  private async release(): Promise<void> {
    clearTimeout(this.watchdog);
    clearInterval(this.monitor); this.monitor = -1;
    try { await NativeCore.stop(); } catch {}
    if (this.fd >= 0) {
      try { fileIo.closeSync(this.fd); } catch {}
      this.fd = -1;
    }
    if (this.connection && this.created) {
      try { await this.connection.destroy(); } catch {}
      this.created = false;
    }
  }
  private async update(status: VpnStatus): Promise<void> {
    this.snapshot.status = status;
    await this.emit();
  }
  private async emit(): Promise<void> {
    try { await publishVpn(VPN_STATE, JSON.stringify(this.snapshot)); } catch {}
  }
  onDestroy(): void {
    this.cancelled = true;
    clearTimeout(this.watchdog);
    const releaseAfterStart = async (): Promise<void> => { await this.starting; await this.cleanup(); };
    releaseAfterStart().catch(() => {});
    if (this.subscriber) { commonEventManager.unsubscribe(this.subscriber, () => {}); }
  }
}
