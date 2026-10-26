import { ProxyAppState } from '../state/ProxyAppState';
import { VpnStatus } from '../vpn/VpnState';
import { AppRoute } from '../navigation/AppRoute';
import { PageScaffold } from '../components/PageScaffold';
import { AppIcon } from '../components/AppIcon';

@ComponentV2
export struct SubscriptionPage {
  @Param @Require state: ProxyAppState;
  @Event onNavigate: (route: AppRoute) => void = () => {};
  @Event onAdd: () => void = () => {};
  @Event onUpdate: () => void = () => {};
  @Event onClear: () => void = () => {};

  private locked(): boolean {
    return this.state.latencyRunning || (this.state.vpnStatus !== VpnStatus.IDLE && this.state.vpnStatus !== VpnStatus.ERROR);
  }
  private confirmClear(): void {
    this.getUIContext().showAlertDialog({ title: $r('app.string.subscription_delete'),
      message: $r('app.string.clear_address_confirmation'),
      primaryButton: { value: $r('app.string.cancel'), action: () => {} },
      secondaryButton: { value: $r('app.string.confirm_clear'), fontColor: $r('app.color.danger'),
        action: () => { if (!this.locked() && !this.state.saving) { this.onClear(); } } } });
  }
  @Builder field(label: Resource, value: ResourceStr) {
    Column({ space: 8 }) {
      Text(label).fontSize(12).fontColor($r('app.color.text_secondary'))
      Text(value).fontSize(14).fontColor($r('app.color.text_primary'))
    }.alignItems(HorizontalAlign.Start).padding({ top: 8, bottom: 8 }).width('100%')
  }
  @Builder card() {
    Column({ space: 16 }) {
      Row({ space: 12 }) {
        AppIcon({ source: $r('app.media.ic_link'), iconSize: 24, tint: $r('app.color.accent') })
        Column({ space: 6 }) {
          Text(this.state.subscriptionName || $r('app.string.subscription_default_name')).fontSize(18)
            .fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary')).maxLines(2)
          Text($r('app.plural.node_count', this.state.nodes.length, this.state.nodes.length))
            .fontSize(12).fontColor($r('app.color.text_secondary'))
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      }.width('100%')
      this.field($r('app.string.subscription_usage'), $r('app.string.data_unknown'))
      Divider().color($r('app.color.outline'))
      GridRow({ columns: 2, gutter: 16, breakpoints: { value: ['400vp'], reference: BreakpointsReference.ComponentSize } }) {
        GridCol({ span: { xs: 2, sm: 1 } }) { this.field($r('app.string.subscription_expiry'), $r('app.string.data_unknown')) }
        GridCol({ span: { xs: 2, sm: 1 } }) {
          this.field($r('app.string.subscription_last_update'), this.state.subscriptionUpdatedAt || $r('app.string.data_unknown'))
        }
      }
      Button(this.state.saving ? $r('app.string.saving_address') : $r('app.string.subscription_update'),
        { type: ButtonType.Normal }).id('update-subscription').width('100%').constraintSize({ minHeight: 48 })
        .padding(14).fontSize(14).borderRadius(14).fontColor($r('app.color.secondary_button_text'))
        .backgroundColor($r('app.color.secondary_button_background')).enabled(!this.state.saving && !this.locked())
        .onClick(() => this.onUpdate())
      Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.SpaceBetween }) {
        Button($r('app.string.subscription_edit'), { type: ButtonType.Normal }).id('edit-subscription')
          .constraintSize({ minHeight: 48 }).fontSize(14).fontColor($r('app.color.accent'))
          .backgroundColor(Color.Transparent).enabled(!this.state.saving && !this.locked()).onClick(() => this.onAdd())
        Button($r('app.string.subscription_delete'), { type: ButtonType.Normal }).id('clear-subscription')
          .constraintSize({ minHeight: 48 }).fontSize(14).fontColor($r('app.color.danger'))
          .backgroundColor(Color.Transparent).enabled(!this.state.saving && !this.locked()).onClick(() => this.confirmClear())
      }.width('100%')
    }.width('100%').padding(20).borderRadius(20).backgroundColor($r('app.color.surface_background'))
      .border({ width: 1, color: $r('app.color.surface_outline') }).alignItems(HorizontalAlign.Start)
  }
  @Builder body() {
    Scroll() {
      Column({ space: 20 }) {
        Text($r('app.string.subscriptions_title')).fontSize(26).fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
        Text($r('app.string.subscription_sources', this.state.subscriptionAddress ? 1 : 0))
          .fontSize(13).fontColor($r('app.color.text_secondary'))
        Button(this.state.subscriptionAddress ? $r('app.string.edit_subscription') : $r('app.string.add_subscription'),
          { type: ButtonType.Normal }).id('add-subscription').constraintSize({ minHeight: 52 })
          .padding(16).fontSize(15).borderRadius(14).fontColor($r('app.color.primary_button_text'))
          .backgroundColor($r('app.color.primary_button_background'))
          .enabled(this.state.initialized && !this.state.saving && !this.locked()).onClick(() => this.onAdd())
        if (this.locked()) {
          Text(this.state.latencyRunning ? $r('app.string.latency_busy') : $r('app.string.disconnect_before_edit'))
            .fontSize(13).fontColor($r('app.color.accent'))
        }
        if (this.state.subscriptionAddress) { this.card() }
        else {
          Column({ space: 16 }) {
            AppIcon({ source: $r('app.media.ic_link'), iconSize: 40, tint: $r('app.color.accent') })
            Text($r('app.string.subscription_empty_title')).fontSize(20).fontColor($r('app.color.text_primary'))
            Text($r('app.string.subscription_empty_desc')).fontSize(14).fontColor($r('app.color.text_secondary'))
          }.width('100%').padding({ top: 40, bottom: 40 })
        }
        if (this.state.saving) { LoadingProgress().width(32).height(32).color($r('app.color.accent')) }
        if (this.state.subscriptionMessage) {
          Text(this.state.subscriptionMessage).id('subscription-feedback').fontSize(13).lineHeight(21)
            .fontColor(this.state.subscriptionFailed ? $r('app.color.danger') : $r('app.color.success'))
            .padding(16).width('100%').borderRadius(14)
            .backgroundColor(this.state.subscriptionFailed ? $r('app.color.danger_background') : $r('app.color.selected_background'))
        }
        Text($r('app.string.subscription_single_hint')).fontSize(12).lineHeight(20).fontColor($r('app.color.text_secondary'))
      }.alignItems(HorizontalAlign.Start).width('100%').constraintSize({ maxWidth: 800 })
        .padding({ left: 20, right: 20, top: 20, bottom: 28 })
    }.width('100%').height('100%').align(Alignment.Top)
  }
  build() {
    NavDestination() {
      PageScaffold({ state: this.state, active: AppRoute.SUBSCRIPTIONS, content: () => { this.body(); },
        onNavigate: (route: AppRoute) => this.onNavigate(route) })
    }.hideTitleBar(true).backgroundColor($r('app.color.page_background'))
  }
}
