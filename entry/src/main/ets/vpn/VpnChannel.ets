import { commonEventManager } from '@kit.BasicServicesKit';
import { VpnStatus } from './VpnState';
export const BUNDLE: string = 'com.example.hmproxy';
export const VPN_COMMAND: string = 'com.example.hmproxy.vpn.COMMAND';
export const VPN_STATE: string = 'com.example.hmproxy.vpn.STATE';
export class VpnSnapshot {
  session: string = '';
  status: VpnStatus = VpnStatus.IDLE;
  ip: string = '';
  ipv6: string = '';
  error: string = '';
}
export function publishVpn(event: string, data: string): Promise<void> {
  return new Promise<void>((resolve, reject) => {
    commonEventManager.publish(event, { bundleName: BUNDLE, data: data }, (error) => {
      if (error) { reject(new Error('vpn_event_failed')); } else { resolve(); }
    });
  });
}
