import { ProxyNode } from '../subscription/ProxyNode';
import { TunnelConfig } from '../vpn/TunnelConfig';
interface XrayLog { loglevel: string; access: string; error: string; }
interface SocksAccount { user: string; pass: string; }
interface SocksSettings { auth: string; accounts: SocksAccount[]; udp: boolean; ip: string; }
interface SocksInbound { tag: string; listen: string; port: number; protocol: string; settings: SocksSettings; }
interface VlessUser { id: string; encryption: string; flow: string; }
interface VlessServer { address: string; port: number; users: VlessUser[]; }
interface VlessSettings { vnext: VlessServer[]; }
interface RealitySettings { serverName: string; fingerprint: string; publicKey: string; shortId: string; spiderX: string; }
interface StreamSettings { network: string; security: string; realitySettings: RealitySettings; }
interface VlessOutbound { tag: string; protocol: string; settings: VlessSettings; streamSettings: StreamSettings; }
interface DnsOutboundSettings { nonIPQuery: string; blockTypes: number[]; }
interface DnsOutbound { tag: string; protocol: string; settings: DnsOutboundSettings; }
interface DnsSettings { servers: string[]; queryStrategy: string; }
interface RoutingRule { type: string; port: string; network: string; outboundTag: string; }
interface RoutingSettings { rules: RoutingRule[]; }
interface XrayRoot {
  log: XrayLog; dns: DnsSettings; routing: RoutingSettings;
  inbounds: SocksInbound[]; outbounds: (VlessOutbound | DnsOutbound)[];
}
export class XrayConfig {
  static create(node: ProxyNode, token: string): string {
    const config: XrayRoot = {
      log: { loglevel: 'none', access: 'none', error: 'none' },
      dns: { servers: ['https://1.1.1.1/dns-query'], queryStrategy: 'UseIP' },
      routing: { rules: [{ type: 'field', port: '53', network: 'udp,tcp', outboundTag: 'dns-out' }] },
      inbounds: [{ tag: 'tun-socks', listen: '127.0.0.1', port: 10808, protocol: 'socks',
        settings: { auth: 'password', accounts: [{ user: 'harmony', pass: token }], udp: true, ip: '127.0.0.1' } }],
      outbounds: [{ tag: 'proxy', protocol: 'vless', settings: {
        vnext: [{ address: node.server, port: node.port,
          users: [{ id: node.uuid, encryption: 'none', flow: 'xtls-rprx-vision' }] }]
      }, streamSettings: { network: 'tcp', security: 'reality', realitySettings: {
        serverName: node.serverName, fingerprint: node.fingerprint, publicKey: node.publicKey,
        shortId: node.shortId, spiderX: node.spiderX
      } } }, { tag: 'dns-out', protocol: 'dns', settings: { nonIPQuery: 'drop', blockTypes: [65] } }]
    };
    return JSON.stringify(config);
  }
  static tunnel(token: string): string {
    return `tunnel:\n  mtu: ${TunnelConfig.MTU}\n  ipv4: ${TunnelConfig.IPV4}\n  ipv6: '${TunnelConfig.IPV6}'\nsocks5:\n  address: 127.0.0.1\n  port: 10808\n  username: harmony\n  password: '${token}'\n  udp: udp\nmisc:\n  log-level: error\n  connect-timeout: 10000\n`;
  }
  static forLatency(node: ProxyNode): string {
    const config = JSON.parse(XrayConfig.create(node, '')) as XrayRoot;
    config.inbounds = [];
    return JSON.stringify(config);
  }
}
