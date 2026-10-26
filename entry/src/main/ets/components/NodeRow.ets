import { ProxyNode } from '../subscription/ProxyNode';
import { AppIcon } from './AppIcon';
import { NodeLatency, LatencyStatus } from '../subscription/NodeLatency';

// Region badges use only an explicit name hint, never an inferred server location.
export function nodeRegion(node?: ProxyNode): string {
  if (!node) { return ''; }
  const name = node.name;
  if (/\u9999\u6e2f|🇭🇰|Hong\s*Kong|\bHK\b/i.test(name)) { return 'HK'; }
  if (/\u65e5\u672c|🇯🇵|Japan|\bJP\b/i.test(name)) { return 'JP'; }
  if (/\u65b0\u52a0\u5761|🇸🇬|Singapore|\bSG\b/i.test(name)) { return 'SG'; }
  if (/\u5fb7\u56fd|🇩🇪|Germany|\bDE\b/i.test(name)) { return 'DE'; }
  if (/\u7f8e\u56fd|🇺🇸|United\s*States|\bUS\b/i.test(name)) { return 'US'; }
  if (/\u82f1\u56fd|🇬🇧|United\s*Kingdom|\bUK\b/i.test(name)) { return 'GB'; }
  if (/\u53f0\u6e7e|🇹🇼|Taiwan|\bTW\b/i.test(name)) { return 'TW'; }
  return '';
}

export function nodeRegionColor(node?: ProxyNode): ResourceColor {
  switch (nodeRegion(node)) {
    case 'HK': return $r('app.color.region_hk');
    case 'JP': return $r('app.color.region_jp');
    case 'SG': return $r('app.color.region_sg');
    case 'DE': return $r('app.color.region_de');
    default: return $r('app.color.region_other');
  }
}

export function nodeRegionLabel(node?: ProxyNode): ResourceStr {
  switch (nodeRegion(node)) {
    case 'HK': return $r('app.string.region_hk');
    case 'JP': return $r('app.string.region_jp');
    case 'SG': return $r('app.string.region_sg');
    case 'DE': return $r('app.string.region_de');
    case 'US': return $r('app.string.region_us');
    case 'GB': return $r('app.string.region_gb');
    case 'TW': return $r('app.string.region_tw');
    default: return node?.server ?? $r('app.string.node_not_selected');
  }
}

@ComponentV2
export struct RegionBadge {
  @Param node: ProxyNode | undefined = undefined;

  build() {
    Stack() {
      if (nodeRegion(this.node).length > 0) {
        Text(nodeRegion(this.node))
          .fontSize(12)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.region_text'))
          .maxFontScale(1.3)
      } else {
        AppIcon({ source: $r('app.media.ic_globe'), iconSize: 20, tint: $r('app.color.region_text') })
      }
    }
    .width(44)
    .height(44)
    .borderRadius(15)
    .backgroundColor(nodeRegionColor(this.node))
    .accessibilityLevel('no')
  }
}

@ComponentV2
export struct NodeRow {
  @Param @Require node: ProxyNode;
  @Param selected: boolean = false;
  @Param locked: boolean = false;
  @Param sourceName: ResourceStr = $r('app.string.subscription_default_name');
  @Param latency: NodeLatency | undefined = undefined;
  @Event onSelect: () => void = () => {};

  private latencyLabel(): ResourceStr {
    switch (this.latency?.status) {
      case LatencyStatus.SUCCESS: return $r('app.string.latency_ms', this.latency.latencyMs);
      case LatencyStatus.PENDING: return $r('app.string.latency_pending');
      case LatencyStatus.TESTING: return $r('app.string.latency_testing');
      case LatencyStatus.TIMEOUT: return $r('app.string.latency_timeout');
      case LatencyStatus.FAILED: return $r('app.string.latency_failed');
      case LatencyStatus.CANCELLED: return $r('app.string.latency_cancelled');
      default: return $r('app.string.node_latency_unknown');
    }
  }

  build() {
    Button({ type: ButtonType.Normal }) {
      Row({ space: 12 }) {
        RegionBadge({ node: this.node })
        Column({ space: 5 }) {
          Text(this.node.name)
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text() {
            Span(this.node.protocol.toUpperCase())
            Span(' · ')
            Span(this.sourceName)
          }
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        Column({ space: 4 }) {
          if (this.latency?.status === LatencyStatus.TESTING) {
            LoadingProgress().width(16).height(16).color($r('app.color.accent'))
          }
          Text(this.latencyLabel()).fontSize(12).maxLines(2).textAlign(TextAlign.Center)
            .fontColor(this.latency?.status === LatencyStatus.SUCCESS ? $r('app.color.success') :
              this.latency?.status === LatencyStatus.TIMEOUT || this.latency?.status === LatencyStatus.FAILED ?
                $r('app.color.danger') : $r('app.color.text_secondary'))
        }.constraintSize({ minWidth: 48, maxWidth: 76 })
        Stack() {
          if (this.selected) {
            AppIcon({ source: $r('app.media.ic_check'), iconSize: 12, tint: $r('app.color.primary_button_text') })
          }
        }
        .width(22)
        .height(22)
        .borderRadius(11)
        .backgroundColor(this.selected ? $r('app.color.primary_button_background') : Color.Transparent)
        .border({ width: 1, color: this.selected ? $r('app.color.accent') : $r('app.color.outline') })
      }
      .padding(16)
      .width('100%')
      .constraintSize({ minHeight: 84 })
    }
    .id(this.node.id)
    .width('100%')
    .padding(0)
    .borderRadius(20)
    .backgroundColor(this.selected ? $r('app.color.selected_background') : $r('app.color.surface_background'))
    .border({ width: 1, color: this.selected ? $r('app.color.selected_outline') : $r('app.color.surface_outline'),
      radius: 20 })
    .enabled(!this.locked)
    .accessibilityDescription(this.selected ? $r('app.string.node_selected') : $r('app.string.node_select'))
    .onClick(() => this.onSelect())
  }
}
