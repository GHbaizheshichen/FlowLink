export enum ProxyProtocol {
  SOCKS5 = 'socks5', SHADOWSOCKS = 'ss', VMESS = 'vmess', VLESS = 'vless', TROJAN = 'trojan'
}
export interface ProxyNode {
  id: string;
  name: string;
  protocol: ProxyProtocol;
  server: string;
  port: number;
  uuid: string;
  serverName: string;
  publicKey: string;
  shortId: string;
  fingerprint: string;
  spiderX: string;
}
export class SubscriptionParseResult {
  nodes: ProxyNode[] = [];
  skipped: number = 0;
  message?: Resource;
}
