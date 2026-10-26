import { url, util } from '@kit.ArkTS';
import { ProxyNode, ProxyProtocol, SubscriptionParseResult } from './ProxyNode';

export class SubscriptionParser {
  static parse(content: string): SubscriptionParseResult {
    const result = new SubscriptionParseResult();
    let text = content.trim();
    if (!text) {
      result.message = $r('app.string.subscription_content_empty');
      return result;
    }
    if (!text.includes('://')) {
      try {
        const normalized = text.replace(/\s/g, '').replace(/-/g, '+').replace(/_/g, '/');
        text = util.TextDecoder.create('utf-8', { fatal: true }).decodeToString(
          new util.Base64Helper().decodeSync(normalized.padEnd(Math.ceil(normalized.length / 4) * 4, '=')));
      } catch {
        result.message = $r('app.string.subscription_parse_unavailable');
        return result;
      }
    }
    const lines = text.split(/\r?\n/).filter((line: string) => line.trim().length > 0);
    if (lines.length > 2000) {
      result.message = $r('app.string.subscription_parse_unavailable');
      return result;
    }
    lines.forEach((line: string, index: number) => {
      try {
        const parsed = new url.URL(line.trim());
        const params = parsed.params;
        const uuid = decodeURIComponent(parsed.username);
        const key = params.get('pbk') ?? '';
        const shortId = params.get('sid') ?? '';
        const sni = params.get('sni') ?? params.get('servername') ?? '';
        const fingerprint = params.get('fp') ?? 'chrome';
        const spiderX = params.get('spx') || '/';
        const port = Number(parsed.port);
        if (parsed.protocol !== 'vless:' || !/^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$/i.test(uuid) ||
          !parsed.hostname || parsed.password || !Number.isInteger(port) || port < 1 || port > 65535 ||
          params.get('security') !== 'reality' || params.get('type') !== 'tcp' ||
          params.get('flow') !== 'xtls-rprx-vision' || (params.get('encryption') ?? 'none') !== 'none' ||
          !/^[A-Za-z0-9_-]{43}$/.test(key) || !/^(?:[0-9a-f]{2}){0,8}$/i.test(shortId) ||
          !/^[a-z0-9.-]+$/i.test(sni) || !['chrome', 'firefox', 'safari'].includes(fingerprint) ||
          !spiderX.startsWith('/') || spiderX.length > 2048 || /[\r\n]/.test(spiderX)) {
          result.skipped++;
          return;
        }
        const node: ProxyNode = {
          id: `node-${index}`, name: decodeURIComponent(parsed.hash.slice(1)) || `VLESS ${index + 1}`,
          protocol: ProxyProtocol.VLESS, server: parsed.hostname.replace(/^\[|\]$/g, ''), port: port,
          uuid: uuid, serverName: sni, publicKey: key, shortId: shortId, fingerprint: fingerprint, spiderX: spiderX
        };
        result.nodes.push(node);
      } catch { result.skipped++; }
    });
    result.message = result.nodes.length > 0 ?
      $r('app.string.subscription_loaded', result.nodes.length, result.skipped) :
      $r('app.string.subscription_parse_unavailable');
    return result;
  }
}
