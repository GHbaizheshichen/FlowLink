import { common, ConfigurationConstant } from '@kit.AbilityKit';
import { ProxyAppState } from '../state/ProxyAppState';
import { AppRoute } from '../navigation/AppRoute';
import { PageScaffold } from '../components/PageScaffold';

@ComponentV2
export struct SettingsPage {
  @Param @Require state: ProxyAppState;
  @Event onNavigate: (route: AppRoute) => void = () => {};
  private appearance(mode: number): void {
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      context.getApplicationContext().setColorMode(mode);
      this.state.appearance = mode;
    } catch { this.getUIContext().getPromptAction().showToast({ message: $r('app.string.appearance_failed') }); }
  }
  @Builder theme(label: Resource, mode: number) {
    Button(label, { type: ButtonType.Normal }).constraintSize({ minHeight: 48 }).padding(14)
      .fontColor(this.state.appearance === mode ? $r('app.color.accent') : $r('app.color.text_secondary'))
      .backgroundColor(this.state.appearance === mode ? $r('app.color.selected_background') : $r('app.color.surface_background'))
      .borderRadius(14).onClick(() => this.appearance(mode))
  }
  @Builder body() {
    Scroll() {
      Column({ space: 20 }) {
        Text($r('app.string.tab_settings')).fontSize(26).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary'))
        Text($r('app.string.settings_subtitle')).fontSize(14).fontColor($r('app.color.text_secondary'))
        Column({ space: 16 }) {
          Text($r('app.string.appearance')).fontSize(18).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
          Text($r('app.string.appearance_description')).fontSize(14).fontColor($r('app.color.text_secondary'))
          Flex({ wrap: FlexWrap.Wrap }) {
            this.theme($r('app.string.theme_system'), ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET)
            this.theme($r('app.string.theme_light'), ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT)
            this.theme($r('app.string.theme_dark'), ConfigurationConstant.ColorMode.COLOR_MODE_DARK)
          }
        }.width('100%').padding(20).borderRadius(20).backgroundColor($r('app.color.surface_background'))
          .alignItems(HorizontalAlign.Start)
        Column({ space: 12 }) {
          Text($r('app.string.core_title')).fontSize(18).fontColor($r('app.color.text_primary'))
          Text(this.state.nativeAvailable ? this.state.nativeVersion : $r('app.string.vpn_core_unavailable'))
            .fontSize(14).fontColor($r('app.color.text_secondary'))
        }.width('100%').padding(20).borderRadius(20).backgroundColor($r('app.color.surface_background'))
          .alignItems(HorizontalAlign.Start)
      }.width('100%').constraintSize({ maxWidth: 800 }).padding(20).alignItems(HorizontalAlign.Start)
    }.width('100%').height('100%').align(Alignment.Top)
  }
  build() {
    NavDestination() {
      PageScaffold({ state: this.state, active: AppRoute.SETTINGS, content: () => { this.body(); },
        onNavigate: (route: AppRoute) => this.onNavigate(route) })
    }.hideTitleBar(true).backgroundColor($r('app.color.page_background'))
  }
}
