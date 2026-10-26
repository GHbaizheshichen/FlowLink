import { http } from '@kit.NetworkKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { SubscriptionParser } from './SubscriptionParser';
import { SubscriptionParseResult } from './ProxyNode';
export class SubscriptionClient {
  static async load(address: string): Promise<SubscriptionParseResult> {
    const request = http.createHttp();
    try {
      const response = await request.request(address, {
        method: http.RequestMethod.GET, expectDataType: http.HttpDataType.STRING,
        header: { 'User-Agent': 'HarmonyProxy/0.2 (Xray; HarmonyOS)', 'Accept': 'text/plain, */*' },
        connectTimeout: 15000, readTimeout: 20000, usingCache: false, usingProxy: false, maxLimit: 2 * 1024 * 1024
      });
      if (response.responseCode !== 200 || typeof response.result !== 'string') {
        hilog.error(0, 'HarmonyProxySubscription', 'HTTP status %{public}d', response.responseCode);
        throw new Error('subscription_fetch_failed');
      }
      return SubscriptionParser.parse(response.result);
    } catch (error) {
      const code = (error as BusinessError).code ?? -1;
      hilog.error(0, 'HarmonyProxySubscription', 'Subscription request failed: %{public}d', code);
      throw new Error('subscription_fetch_failed');
    } finally { request.destroy(); }
  }
}
