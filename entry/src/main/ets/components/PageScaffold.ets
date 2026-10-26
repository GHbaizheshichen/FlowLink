import { ProxyAppState } from '../state/ProxyAppState';
import { AppRoute } from '../navigation/AppRoute';
import { AppHeader } from './AppHeader';
import { AppIcon } from './AppIcon';

@ComponentV2
export struct PageScaffold {
  @Param @Require state: ProxyAppState;
  @Param active: AppRoute = AppRoute.HOME;
  @Param title: ResourceStr = $r('app.string.app_title');
  @Param secondary: boolean = false;
  @Event onNavigate: (route: AppRoute) => void = () => {};
  @Event onBack: () => void = () => {};
  @BuilderParam content: () => void = this.empty;
  @Local private wide: boolean = false;

  @Builder empty() {}

  @Builder
  destination(route: AppRoute, label: Resource, icon: Resource) {
    Button({ type: ButtonType.Normal }) {
      if (this.wide) {
        Row({ space: 12 }) {
          AppIcon({ source: icon, tint: this.active === route ? $r('app.color.accent') : $r('app.color.text_secondary') })
          Text(label).fontSize(14).fontColor(this.active === route ?
            $r('app.color.accent') : $r('app.color.text_secondary')).layoutWeight(1)
        }.width('100%').padding(16)
      } else {
        Column({ space: 6 }) {
          AppIcon({ source: icon, tint: this.active === route ? $r('app.color.accent') : $r('app.color.text_secondary') })
          Text(label).fontSize(11).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
            .fontColor(this.active === route ? $r('app.color.accent') : $r('app.color.text_secondary'))
        }.width('100%').padding({ top: 12, bottom: 12 })
      }
    }
    .id('tab-' + route)
    .layoutWeight(this.wide ? 0 : 1)
    .width(this.wide ? '100%' : undefined)
    .constraintSize({ minHeight: 56 })
    .borderRadius(this.wide ? 14 : 0)
    .backgroundColor(this.wide && this.active === route ? $r('app.color.selected_background') : Color.Transparent)
    .accessibilityText(label)
    .accessibilityDescription(this.active === route ? $r('app.string.node_selected') : label)
    .onClick(() => this.onNavigate(route))
  }

  @Builder tabs() {
    this.destination(AppRoute.HOME, $r('app.string.tab_home'), $r('app.media.ic_home'))
    this.destination(AppRoute.NODES, $r('app.string.nodes_title'), $r('app.media.ic_nodes'))
    this.destination(AppRoute.SUBSCRIPTIONS, $r('app.string.tab_subscriptions'), $r('app.media.ic_link'))
    this.destination(AppRoute.SETTINGS, $r('app.string.tab_settings'), $r('app.media.ic_settings'))
  }

  build() {
    Row() {
      if (this.wide && !this.secondary) {
        Column({ space: 12 }) {
          Row({ space: 10 }) {
            AppIcon({ source: $r('app.media.ic_brand'), tint: $r('app.color.accent') })
            Text($r('app.string.brand_wordmark')).fontSize(16).fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.text_primary'))
          }.padding({ top: 24, bottom: 28 })
          this.tabs()
          Blank()
        }.width(200).height('100%').padding(16)
          .backgroundColor($r('app.color.surface_background'))
      }
      Column() {
        AppHeader({ state: this.state, title: this.title, home: !this.secondary, onBack: () => this.onBack() })
        Column() { this.content() }.layoutWeight(1).width('100%')
        if (!this.wide && !this.secondary) {
          Row() { this.tabs() }.width('100%')
            .border({ width: { top: 1 }, color: $r('app.color.outline') })
            .backgroundColor($r('app.color.surface_background'))
        }
      }.layoutWeight(1).height('100%')
    }.width('100%').height('100%').backgroundColor($r('app.color.page_background'))
      .onAreaChange((_old: Area, area: Area) => { this.wide = Number(area.width) >= 840; })
  }
}
