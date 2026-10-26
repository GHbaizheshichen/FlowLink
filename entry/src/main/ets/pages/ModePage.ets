import { ProxyAppState } from '../state/ProxyAppState';
import { PageScaffold } from '../components/PageScaffold';
import { AppIcon } from '../components/AppIcon';

@ComponentV2
export struct ModePage {
  @Param @Require state: ProxyAppState;
  @Event onBack: () => void = () => {};
  @Builder option(title: Resource, description: Resource, applied: boolean) {
    Row({ space: 14 }) {
      Stack() {
        if (applied) { Stack().width(10).height(10).borderRadius(5).backgroundColor($r('app.color.accent')) }
      }.width(22).height(22).borderRadius(11).border({ width: 1, color: applied ? $r('app.color.accent') : $r('app.color.outline') })
      Column({ space: 8 }) {
        Text(title).fontSize(16).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
        Text(description).fontSize(13).lineHeight(20).fontColor($r('app.color.text_secondary'))
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      if (applied) { Text($r('app.string.mode_applied')).fontSize(12).fontColor($r('app.color.success')) }
    }.width('100%').padding(20).constraintSize({ minHeight: 96 }).borderRadius(20)
      .backgroundColor(applied ? $r('app.color.selected_background') : $r('app.color.surface_background'))
      .border({ width: 1, color: applied ? $r('app.color.selected_outline') : $r('app.color.surface_outline') })
      .opacity(applied ? 1 : 0.6)
  }
  @Builder body() {
    Scroll() {
      Column({ space: 16 }) {
        AppIcon({ source: $r('app.media.ic_mode'), iconSize: 32, tint: $r('app.color.accent') })
        Text($r('app.string.proxy_mode')).fontSize(26).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary'))
        Text($r('app.string.mode_subtitle')).fontSize(14).lineHeight(22).fontColor($r('app.color.text_secondary'))
        this.option($r('app.string.mode_rule'), $r('app.string.mode_rule_desc'), false)
        this.option($r('app.string.mode_global'), $r('app.string.mode_global_desc'), true)
        this.option($r('app.string.mode_direct'), $r('app.string.mode_direct_desc'), false)
        Text($r('app.string.mode_supported_hint')).fontSize(13).lineHeight(22).fontColor($r('app.color.text_secondary'))
          .width('100%').padding(16).borderRadius(14).backgroundColor($r('app.color.icon_background'))
        Text($r('app.string.mode_current')).fontSize(12).fontColor($r('app.color.text_secondary'))
        Text($r('app.string.mode_global')).fontSize(16).fontColor($r('app.color.text_primary'))
        Button($r('app.string.mode_apply'), { type: ButtonType.Normal }).width('100%').constraintSize({ minHeight: 52 })
          .borderRadius(14).fontColor($r('app.color.primary_button_text'))
          .backgroundColor($r('app.color.primary_button_background')).enabled(false)
      }.width('100%').constraintSize({ maxWidth: 760 }).padding({ left: 20, right: 20, top: 24, bottom: 32 })
    }.height('100%').width('100%').align(Alignment.Top)
  }
  build() {
    NavDestination() {
      PageScaffold({ state: this.state, secondary: true, title: $r('app.string.proxy_mode'),
        content: () => { this.body(); }, onBack: () => this.onBack() })
    }.hideTitleBar(true).backgroundColor($r('app.color.page_background'))
  }
}
