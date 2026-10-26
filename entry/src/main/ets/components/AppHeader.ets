import { common, ConfigurationConstant } from '@kit.AbilityKit';
import { ProxyAppState } from '../state/ProxyAppState';
import { AppIcon } from './AppIcon';

@ComponentV2
export struct AppHeader {
  @Param @Require state: ProxyAppState;
  @Param title: ResourceStr = $r('app.string.app_title');
  @Param home: boolean = false;
  @Event onBack: () => void = () => {};

  private setAppearance(mode: number): void {
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      context.getApplicationContext().setColorMode(mode);
      this.state.appearance = mode;
    } catch {
      try {
        this.getUIContext().getPromptAction().showToast({ message: $r('app.string.appearance_failed') });
      } catch {}
    }
  }

  build() {
    Row({ space: 8 }) {
      if (this.home) {
        Stack() {
          AppIcon({ source: $r('app.media.ic_brand'), iconSize: 24, tint: $r('app.color.accent') })
        }
        .width(30)
        .height(30)
        .borderRadius(10)
        .backgroundColor(Color.Transparent)
      } else {
        Button({ type: ButtonType.Normal }) {
          AppIcon({ source: $r('app.media.ic_back') })
        }
        .id('navigate-back')
        .width(48)
        .height(48)
        .backgroundColor(Color.Transparent)
        .borderRadius(16)
        .accessibilityText($r('app.string.go_back'))
        .onClick(() => this.onBack())
      }
      Text(this.home ? $r('app.string.brand_wordmark') : this.title)
        .id(this.home ? 'home-title' : 'page-title')
        .fontSize(this.home ? 18 : 16)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
        .textAlign(this.home ? TextAlign.Start : TextAlign.Center)
      Button({ type: ButtonType.Normal }) {
        AppIcon({ source: this.state.appearance === ConfigurationConstant.ColorMode.COLOR_MODE_DARK ?
          $r('app.media.ic_sun') : $r('app.media.ic_moon') })
      }
      .id('appearance-menu')
      .width(48)
      .height(48)
      .borderRadius(16)
      .backgroundColor(Color.Transparent)
      .accessibilityText($r('app.string.appearance'))
      .bindMenu([
        { value: $r('app.string.theme_system'), action: () =>
          this.setAppearance(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET) },
        { value: $r('app.string.theme_light'), action: () =>
          this.setAppearance(ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT) },
        { value: $r('app.string.theme_dark'), action: () =>
          this.setAppearance(ConfigurationConstant.ColorMode.COLOR_MODE_DARK) }
      ])
    }
    .width('100%')
    .constraintSize({ maxWidth: 1120, minHeight: 64 })
    .padding({ left: this.home ? 20 : 12, right: 12, top: 4, bottom: 4 })
    .backgroundColor($r('app.color.page_background'))
  }
}
