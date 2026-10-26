export enum VpnStatus {
  IDLE = 'idle',
  STARTING = 'starting',
  VERIFYING = 'verifying',
  CONNECTED = 'connected',
  STOPPING = 'stopping',
  ERROR = 'error'
}

export function vpnStatusLabel(status: VpnStatus): Resource {
  switch (status) {
    case VpnStatus.STARTING:
      return $r('app.string.vpn_status_starting');
    case VpnStatus.CONNECTED:
      return $r('app.string.vpn_status_connected');
    case VpnStatus.VERIFYING:
      return $r('app.string.vpn_status_verifying');
    case VpnStatus.STOPPING:
      return $r('app.string.vpn_status_stopping');
    case VpnStatus.ERROR:
      return $r('app.string.vpn_status_error');
    default:
      return $r('app.string.vpn_status_idle');
  }
}
