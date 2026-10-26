import { url } from '@kit.ArkTS';

export class IpAddress {
  static normalize(value: string, family: number): string {
    const text = value.trim();
    if (text.length === 0 || text.length > 64) { return ''; }
    if (family === 4) {
      const parts = text.split('.');
      return parts.length === 4 && parts.every((part: string) => /^\d{1,3}$/.test(part) &&
        Number(part) <= 255 && String(Number(part)) === part) ? text : '';
    }
    if (!/^[0-9a-f:]+$/i.test(text) || !text.includes(':')) { return ''; }
    try {
      const normalized = new url.URL(`http://[${text}]/`).hostname.replace(/^\[|\]$/g, '').toLowerCase();
      return normalized.startsWith('::ffff:') ? '' : normalized;
    } catch { return ''; }
  }
}
