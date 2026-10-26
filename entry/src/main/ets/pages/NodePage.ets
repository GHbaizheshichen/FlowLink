import { ProxyAppState } from '../state/ProxyAppState';
import { ProxyNode } from '../subscription/ProxyNode';
import { VpnStatus } from '../vpn/VpnState';
import { AppRoute } from '../navigation/AppRoute';
import { PageScaffold } from '../components/PageScaffold';
import { NodeRow, nodeRegion } from '../components/NodeRow';
import { AppIcon } from '../components/AppIcon';
import { NodeLatency, compareNodeLatency } from '../subscription/NodeLatency';

@ComponentV2
export struct NodePage {
  @Param @Require state: ProxyAppState;
  @Event onNavigate: (route: AppRoute) => void = () => {};
  @Event onSelect: (id: string) => void = () => {};
  @Event onOpenSubscription: () => void = () => {};
  @Event onTest: (nodes: ProxyNode[]) => void = () => {};
  @Local private query: string = '';
  @Local private group: number = 0;
  @Local private sortOrder: number = 0;
  private locked(): boolean {
    return this.state.saving || this.state.latencyRunning ||
      (this.state.vpnStatus !== VpnStatus.IDLE && this.state.vpnStatus !== VpnStatus.ERROR);
  }
  private filteredNodes(): ProxyNode[] {
    const nodes = this.state.nodes.filter((node: ProxyNode) => {
      const region = nodeRegion(node);
      return node.name.toLowerCase().includes(this.query.trim().toLowerCase()) &&
        (this.group === 0 || (this.group === 1 && ['HK', 'JP', 'SG', 'TW'].includes(region)) ||
          (this.group === 2 && ['DE', 'GB'].includes(region)));
    });
    if (this.sortOrder === 1) { return nodes.sort((a: ProxyNode, b: ProxyNode) => a.name.localeCompare(b.name)); }
    if (this.sortOrder === 2) {
      const latencies = new Map<string, NodeLatency>();
      this.state.latencyResults.forEach((result: NodeLatency) => latencies.set(result.nodeId, result));
      return nodes.sort((a: ProxyNode, b: ProxyNode) => {
        return compareNodeLatency(latencies.get(a.id), latencies.get(b.id));
      });
    }
    return nodes;
  }
  @Builder chip(label: Resource, value: number) {
    Button(label, { type: ButtonType.Normal }).fontSize(13).padding({ left: 16, right: 16, top: 12, bottom: 12 })
      .constraintSize({ minHeight: 48 }).borderRadius(24)
      .margin({ right: 8, bottom: 8 })
      .fontColor(this.group === value ? $r('app.color.primary_button_text') : $r('app.color.text_secondary'))
      .backgroundColor(this.group === value ? $r('app.color.primary_button_background') : $r('app.color.surface_background'))
      .onClick(() => { this.group = value; })
  }
  @Builder body() {
    Column({ space: 16 }) {
      Column({ space: 8 }) {
        Text($r('app.string.nodes_title')).fontSize(26).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary'))
        Text($r('app.plural.node_count', this.state.nodes.length, this.state.nodes.length))
          .id('node-count').fontSize(13).fontColor($r('app.color.text_secondary'))
      }.alignItems(HorizontalAlign.Start).width('100%')
      Row({ space: 8 }) {
        AppIcon({ source: $r('app.media.ic_search'), iconSize: 18, tint: $r('app.color.text_secondary') })
        TextInput({ text: this.query, placeholder: $r('app.string.node_search') }).id('node-search')
          .layoutWeight(1).constraintSize({ minHeight: 48 }).fontSize(14).fontColor($r('app.color.text_primary'))
          .placeholderColor($r('app.color.input_placeholder')).backgroundColor(Color.Transparent)
          .padding({ left: 0, right: 8 }).onChange((value: string) => { this.query = value; })
      }.width('100%').padding({ left: 14 }).backgroundColor($r('app.color.input_background')).borderRadius(14)
      Flex({ wrap: FlexWrap.Wrap }) {
        this.chip($r('app.string.nodes_all'), 0)
        this.chip($r('app.string.nodes_asia'), 1)
        this.chip($r('app.string.nodes_europe'), 2)
      }.width('100%')
      Text($r('app.string.source_subscription')).fontSize(12).fontColor($r('app.color.text_secondary')).width('100%')
      Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.SpaceBetween }) {
        Text(this.state.subscriptionAddress ? (this.state.subscriptionName || $r('app.string.subscription_default_name')) :
          $r('app.string.source_all')).fontSize(14)
          .fontColor($r('app.color.text_primary')).padding(14).constraintSize({ minHeight: 48 })
          .backgroundColor($r('app.color.surface_background')).borderRadius(14)
        Button(this.sortOrder === 1 ? $r('app.string.sort_name') : this.sortOrder === 2 ?
          $r('app.string.sort_latency') : $r('app.string.sort_original'), { type: ButtonType.Normal })
          .id('sort-nodes').fontSize(13).fontColor($r('app.color.text_secondary')).padding(14)
          .constraintSize({ minHeight: 48 }).borderRadius(14).backgroundColor($r('app.color.surface_background'))
          .bindMenu([
            { value: $r('app.string.sort_original'), action: () => { this.sortOrder = 0; } },
            { value: $r('app.string.sort_name'), action: () => { this.sortOrder = 1; } },
            { value: $r('app.string.sort_latency'), action: () => { this.sortOrder = 2; } }
          ])
      }.width('100%')
      Button(this.state.latencyCancelling ? $r('app.string.latency_cancelling') : this.state.latencyRunning ?
        $r('app.string.latency_cancel') : $r('app.string.speed_test'), { type: ButtonType.Normal }).id('test-latency')
        .width('100%').constraintSize({ minHeight: 48 }).borderRadius(14)
        .fontColor($r('app.color.secondary_button_text')).backgroundColor($r('app.color.secondary_button_background'))
        .enabled(!this.state.latencyCancelling && (this.state.latencyRunning || (!this.locked() &&
          this.state.initialized && this.state.nativeAvailable && this.filteredNodes().length > 0)))
        .onClick(() => this.onTest(this.filteredNodes()))
      Text($r('app.string.latency_description')).fontSize(12).lineHeight(20).fontColor($r('app.color.text_secondary'))
      if (this.state.latencyRunning) {
        Text($r('app.string.latency_progress', this.state.latencyCompleted, this.state.latencyTotal))
          .id('latency-progress').fontSize(13).fontColor($r('app.color.accent'))
      }
      if (this.state.latencyMessage) {
        Text(this.state.latencyMessage).id('latency-feedback').fontSize(13).lineHeight(20)
          .fontColor($r('app.color.text_secondary'))
      }
      if (this.state.latencyRunning) {
        Text($r('app.string.latency_busy')).fontSize(13).fontColor($r('app.color.accent'))
      } else if (this.state.vpnStatus !== VpnStatus.IDLE && this.state.vpnStatus !== VpnStatus.ERROR) {
        Text($r('app.string.disconnect_before_select')).fontSize(13).fontColor($r('app.color.accent'))
      }
      if (this.state.saving) { LoadingProgress().width(32).height(32).color($r('app.color.accent')) }
      if (this.state.nodes.length === 0) {
        Column({ space: 16 }) {
          Text($r('app.string.nodes_empty_title')).fontSize(20).fontColor($r('app.color.text_primary'))
          Text($r('app.string.nodes_empty_description')).fontSize(14).fontColor($r('app.color.text_secondary'))
          Button($r('app.string.open_subscriptions')).constraintSize({ minHeight: 48 })
            .fontColor($r('app.color.primary_button_text')).backgroundColor($r('app.color.primary_button_background'))
            .onClick(() => this.onOpenSubscription())
        }.padding({ top: 24, bottom: 24 }).width('100%')
      } else if (this.filteredNodes().length === 0) {
        Text($r('app.string.no_search_results')).fontSize(16).fontColor($r('app.color.text_secondary')).padding(20)
        Button($r('app.string.reset_filters')).onClick(() => { this.query = ''; this.group = 0; })
      } else {
        GridRow({ columns: 2, gutter: { x: 16, y: 12 },
          breakpoints: { value: ['720vp'], reference: BreakpointsReference.ComponentSize } }) {
          ForEach(this.filteredNodes(), (node: ProxyNode) => {
            GridCol({ span: { xs: 2, sm: 1 } }) {
              NodeRow({ node: node, sourceName: this.state.subscriptionName || $r('app.string.subscription_default_name'),
                latency: this.state.latencyResults.find((result) => result.nodeId === node.id),
                selected: this.state.selectedNodeId === node.id, locked: this.locked(), onSelect: () => this.onSelect(node.id) })
            }
          }, (node: ProxyNode) => node.id)
        }.id('node-list')
      }
    }.width('100%').constraintSize({ maxWidth: 1120 }).padding({ left: 20, right: 20, top: 20, bottom: 28 })
      .alignItems(HorizontalAlign.Start)
  }
  @Builder scrollBody() { Scroll() { this.body() }.width('100%').height('100%').align(Alignment.Top) }
  build() {
    NavDestination() {
      PageScaffold({ state: this.state, active: AppRoute.NODES, content: () => { this.scrollBody(); },
        onNavigate: (route: AppRoute) => this.onNavigate(route) })
    }.hideTitleBar(true).backgroundColor($r('app.color.page_background'))
  }
}
