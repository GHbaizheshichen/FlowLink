import { vpnExtension } from '@kit.NetworkKit';

// Keep system TUN addresses and Hev's configuration in one place.
export class TunnelConfig {
  static readonly IPV4: string = '198.18.0.1';
  static readonly IPV6: string = 'fdfe:dcba:9876::1';
  static readonly MTU: number = 1500;

  static create(): vpnExtension.VpnConfig {
    return {
      addresses: [
        { address: { address: TunnelConfig.IPV4, family: 1 }, prefixLength: 30 },
        { address: { address: TunnelConfig.IPV6, family: 2 }, prefixLength: 126 }
      ],
      routes: [
        { interface: '', destination: { address: { address: '0.0.0.0', family: 1 }, prefixLength: 0 },
          gateway: { address: '0.0.0.0', family: 1 }, hasGateway: false, isDefaultRoute: true },
        { interface: '', destination: { address: { address: '::', family: 2 }, prefixLength: 0 },
          gateway: { address: '::', family: 2 }, hasGateway: false, isDefaultRoute: true }
      ],
      dnsAddresses: ['1.1.1.1', '2606:4700:4700::1111'], mtu: TunnelConfig.MTU,
      isIPv4Accepted: true, isIPv6Accepted: true, isBlocking: false
    };
  }
}
