import { ProxyAppState } from '../state/ProxyAppState';
import { VpnStatus, vpnStatusLabel } from '../vpn/VpnState';
import { AppRoute } from '../navigation/AppRoute';
import { PageScaffold } from '../components/PageScaffold';
import { AppIcon } from '../components/AppIcon';
import { RegionBadge } from '../components/NodeRow';

@ComponentV2
export struct HomePage {
  @Param @Require state: ProxyAppState;
  @Event onNavigate: (route: AppRoute) => void = () => {};
  @Event onOpenNodes: () => void = () => {};
  @Event onOpenSubscription: () => void = () => {};
  @Event onOpenMode: () => void = () => {};
  @Event onConnect: () => void = () => {};

  private connected(): boolean { return this.state.vpnStatus === VpnStatus.CONNECTED; }
  private busy(): boolean {
    return this.state.vpnStatus === VpnStatus.STARTING || this.state.vpnStatus === VpnStatus.STOPPING;
  }
  private disconnectable(): boolean { return this.connected() || this.state.vpnStatus === VpnStatus.VERIFYING; }

  @Builder connectionControl() {
    Column({ space: 16 }) {
      Text($r('app.string.home_subtitle')).fontSize(13).fontColor($r('app.color.text_secondary'))
        .width('100%').textAlign(TextAlign.Start)
      Stack() {
        Stack().width(180).height(180).borderRadius(90)
          .border({ width: 1, color: this.disconnectable() ? $r('app.color.success') : $r('app.color.outline') })
        Stack().width(156).height(156).borderRadius(78).border({ width: 1, color: $r('app.color.outline') })
        Stack().width(116).height(116).borderRadius(58)
          .backgroundColor(this.disconnectable() ? $r('app.color.power_center_active') : $r('app.color.power_center'))
          .border({ width: 1, color: $r('app.color.outline') })
        if (this.busy() || this.state.vpnStatus === VpnStatus.VERIFYING) {
          LoadingProgress().width(40).height(40).color($r('app.color.accent'))
        } else {
          AppIcon({ source: $r('app.media.ic_shield'), iconSize: 40,
            tint: this.connected() ? $r('app.color.success') : $r('app.color.text_secondary') })
        }
      }.height(200).width('100%').accessibilityLevel('no-hide-descendants')
      Text(this.connected() ? $r('app.string.home_connected_hint') : $r('app.string.home_connection_hint'))
        .fontSize(12).fontColor(this.connected() ? $r('app.color.success') : $r('app.color.text_secondary'))
        .textAlign(TextAlign.Center)
      Text(this.state.vpnStatus === VpnStatus.IDLE ? $r('app.string.connection_idle_title') :
        this.connected() ? $r('app.string.connection_active_title') : vpnStatusLabel(this.state.vpnStatus))
        .id('vpn-status').fontSize(26).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary'))
        .textAlign(TextAlign.Center)
      Button(this.disconnectable() ? $r('app.string.disconnect_vpn') :
        this.state.vpnStatus === VpnStatus.ERROR ? $r('app.string.retry_connection') : $r('app.string.connect_vpn'),
        { type: ButtonType.Normal })
        .id('connect-vpn').width('100%').constraintSize({ minHeight: 52 }).padding(16).borderRadius(14)
        .fontSize(16).fontWeight(FontWeight.Medium)
        .fontColor(this.disconnectable() ? $r('app.color.secondary_button_text') : $r('app.color.primary_button_text'))
        .backgroundColor(this.disconnectable() ? $r('app.color.secondary_button_background') :
          $r('app.color.primary_button_background'))
        .enabled(this.state.initialized && !this.busy() && !this.state.saving && !this.state.latencyRunning)
        .onClick(() => {
          if (this.disconnectable()) { this.onConnect(); }
          else if (!this.state.subscriptionAddress) { this.onOpenSubscription(); }
          else if (!this.state.selectedNode()) { this.onOpenNodes(); }
          else { this.onConnect(); }
        })
      if (this.state.connectionMessage) {
        Text(this.state.connectionMessage).id('connection-feedback').fontSize(13).lineHeight(21)
          .fontColor($r('app.color.danger')).textAlign(TextAlign.Center)
      }
      if (this.state.latencyRunning) {
        Text($r('app.string.latency_busy')).fontSize(13).lineHeight(21).fontColor($r('app.color.text_secondary'))
          .textAlign(TextAlign.Center)
      }
      if (!this.state.nativeAvailable && this.state.initialized) {
        Text($r('app.string.core_unavailable_hint')).fontSize(13).fontColor($r('app.color.danger'))
      }
    }.width('100%').padding({ top: 4, bottom: 12 })
  }

  @Builder metric(label: Resource, icon: Resource) {
    Column({ space: 10 }) {
      Row({ space: 6 }) {
        AppIcon({ source: icon, iconSize: 16, tint: $r('app.color.accent') })
        Text(label).fontSize(12).fontColor($r('app.color.text_secondary'))
      }
      Text($r('app.string.data_unknown')).fontSize(16).fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
    }.alignItems(HorizontalAlign.Start).padding(16).width('100%')
      .borderRadius(20).backgroundColor($r('app.color.surface_background'))
      .border({ width: 1, color: $r('app.color.surface_outline') })
  }

  @Builder details() {
    Column({ space: 14 }) {
      Column({ space: 12 }) {
        Text($r('app.string.current_node')).fontSize(12).fontColor($r('app.color.text_secondary'))
        Button({ type: ButtonType.Normal }) {
          Row({ space: 10 }) {
            RegionBadge({ node: this.state.selectedNode() })
            Column({ space: 5 }) {
              Text(this.state.selectedNode()?.name ?? $r('app.string.node_not_selected'))
                .fontSize(15).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
                .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
              Text(this.state.selectedNode()?.protocol.toUpperCase() ?? (this.state.nodes.length > 0 ?
                $r('app.string.vpn_select_node') : this.state.subscriptionAddress ?
                  $r('app.string.home_refresh_hint') : $r('app.string.home_empty_hint')))
                .fontSize(12).fontColor($r('app.color.text_secondary')).maxLines(2)
            }.alignItems(HorizontalAlign.Start).layoutWeight(1)
            Text($r('app.string.switch_node')).fontSize(13).fontColor($r('app.color.accent'))
              .padding(10).borderRadius(12).backgroundColor($r('app.color.icon_background'))
          }.width('100%').constraintSize({ minHeight: 52 })
        }.id('current-node').padding(0).width('100%').backgroundColor(Color.Transparent)
          .borderRadius(12).onClick(() => this.onOpenNodes())
        if (this.connected()) {
          Divider().color($r('app.color.outline'))
          Text($r('app.string.exit_ipv4')).fontSize(12).fontColor($r('app.color.success'))
          Text(this.state.exitIp || $r('app.string.ipv4_probe_unavailable')).id('verified-exit-ip')
            .fontSize(14).fontColor($r('app.color.text_primary'))
          Text($r('app.string.exit_ipv6')).fontSize(12).fontColor($r('app.color.success'))
          Text(this.state.exitIpv6 || $r('app.string.ipv6_probe_unavailable')).id('verified-exit-ipv6')
            .fontSize(14).fontColor($r('app.color.text_primary')).wordBreak(WordBreak.BREAK_ALL)
        }
      }.width('100%').alignItems(HorizontalAlign.Start).padding(20).borderRadius(20)
        .backgroundColor($r('app.color.surface_background')).border({ width: 1, color: $r('app.color.surface_outline'), radius: 20 })
      Button({ type: ButtonType.Normal }) {
        Row({ space: 12 }) {
          AppIcon({ source: $r('app.media.ic_mode'), tint: $r('app.color.accent') })
          Column({ space: 5 }) {
            Text($r('app.string.mode_global')).fontSize(15).fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_primary'))
            Text($r('app.string.mode_global_desc')).fontSize(12).fontColor($r('app.color.text_secondary'))
          }.layoutWeight(1).alignItems(HorizontalAlign.Start)
          AppIcon({ source: $r('app.media.ic_chevron'), iconSize: 16, tint: $r('app.color.text_secondary') })
        }.width('100%').padding(18).constraintSize({ minHeight: 72 })
      }.id('open-mode').width('100%').padding(0).borderRadius(20)
        .backgroundColor($r('app.color.surface_background')).border({ width: 1, color: $r('app.color.surface_outline'), radius: 20 })
        .onClick(() => this.onOpenMode())
      GridRow({ columns: 2, gutter: 12, breakpoints: { value: ['360vp'], reference: BreakpointsReference.ComponentSize } }) {
        GridCol({ span: { xs: 2, sm: 1 } }) { this.metric($r('app.string.download_rate'), $r('app.media.ic_download')) }
        GridCol({ span: { xs: 2, sm: 1 } }) { this.metric($r('app.string.upload_rate'), $r('app.media.ic_upload')) }
      }
      Text($r('app.string.metrics_pending')).fontSize(12).fontColor($r('app.color.text_secondary'))
    }.width('100%').padding({ top: 12 })
  }

  @Builder body() {
    Scroll() {
      GridRow({ columns: 12, gutter: { x: 32, y: 12 },
        breakpoints: { value: ['760vp'], reference: BreakpointsReference.ComponentSize } }) {
        GridCol({ span: { xs: 12, sm: 6 } }) { this.connectionControl() }
        GridCol({ span: { xs: 12, sm: 6 } }) { this.details() }
      }.width('100%').constraintSize({ maxWidth: 1120 }).padding({ left: 20, right: 20, top: 12, bottom: 28 })
    }.width('100%').height('100%').align(Alignment.Top).scrollBar(BarState.Auto)
  }
  build() {
    NavDestination() {
      PageScaffold({ state: this.state, active: AppRoute.HOME, content: () => { this.body(); },
        onNavigate: (route: AppRoute) => this.onNavigate(route) })
    }.hideTitleBar(true).backgroundColor($r('app.color.page_background'))
  }
}
