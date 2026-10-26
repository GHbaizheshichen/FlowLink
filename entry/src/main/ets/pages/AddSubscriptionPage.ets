import { pasteboard } from '@kit.BasicServicesKit';
import { url } from '@kit.ArkTS';
import { ProxyAppState } from '../state/ProxyAppState';
import { VpnStatus } from '../vpn/VpnState';
import { PageScaffold } from '../components/PageScaffold';

@ComponentV2
export struct AddSubscriptionPage {
  @Param @Require state: ProxyAppState;
  @Event onBack: () => void = () => {};
  @Event onSave: (address: string, name: string) => Promise<boolean> = async () => false;
  @Local private name: string = '';
  @Local private address: string = '';
  @Local private nameError: boolean = false;
  @Local private addressError: boolean = false;

  aboutToAppear(): void {
    this.name = this.state.subscriptionName;
    this.address = this.state.subscriptionAddress;
  }
  private locked(): boolean {
    return this.state.saving || this.state.latencyRunning ||
      (this.state.vpnStatus !== VpnStatus.IDLE && this.state.vpnStatus !== VpnStatus.ERROR);
  }
  private back(): void {
    if (this.state.saving) { return; }
    if (this.name === this.state.subscriptionName && this.address === this.state.subscriptionAddress) { this.onBack(); return; }
    this.getUIContext().showAlertDialog({ title: $r('app.string.discard_title'), message: $r('app.string.discard_message'),
      primaryButton: { value: $r('app.string.cancel'), action: () => {} },
      secondaryButton: { value: $r('app.string.discard_confirm'), action: () => this.onBack() } });
  }
  private async paste(): Promise<void> {
    try {
      const data = await pasteboard.getSystemPasteboard().getData();
      this.address = data.getPrimaryText().trim().slice(0, 4096);
      this.addressError = false;
    } catch { this.getUIContext().getPromptAction().showToast({ message: $r('app.string.paste_failed') }); }
  }
  private async save(): Promise<void> {
    this.nameError = this.name.trim().length === 0;
    try {
      const parsed = new url.URL(this.address.trim());
      this.addressError = !['http:', 'https:'].includes(parsed.protocol) || !parsed.hostname ||
        parsed.username.length > 0 || parsed.password.length > 0;
    } catch { this.addressError = true; }
    if (this.nameError || this.addressError || this.locked()) { return; }
    if (await this.onSave(this.address, this.name)) { this.onBack(); }
  }
  @Builder body() {
    Scroll() {
      Column({ space: 20 }) {
        Text(this.state.subscriptionAddress ? $r('app.string.edit_subscription') : $r('app.string.add_subscription'))
          .fontSize(26).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary'))
        Text($r('app.string.subscription_form_desc')).fontSize(14).lineHeight(22).fontColor($r('app.color.text_secondary'))
        Column({ space: 12 }) {
          Text($r('app.string.subscription_name')).fontSize(14).fontColor($r('app.color.text_primary'))
          TextInput({ text: this.name, placeholder: $r('app.string.subscription_name_placeholder') })
            .id('subscription-name').maxLength(80).constraintSize({ minHeight: 52 }).fontSize(15)
            .fontColor($r('app.color.text_primary')).placeholderColor($r('app.color.input_placeholder'))
            .backgroundColor($r('app.color.input_background')).borderRadius(14).enabled(!this.locked())
            .onChange((value: string) => { this.name = value; this.nameError = false; })
          if (this.nameError) { Text($r('app.string.subscription_name_required')).fontSize(13).fontColor($r('app.color.danger')) }
          Text($r('app.string.subscription_address')).fontSize(14).fontColor($r('app.color.text_primary'))
          TextInput({ text: this.address, placeholder: $r('app.string.subscription_address_placeholder') })
            .id('subscription-address').type(InputType.Password).showPasswordIcon(true).maxLength(4096)
            .constraintSize({ minHeight: 52 }).fontSize(14).fontColor($r('app.color.text_primary'))
            .placeholderColor($r('app.color.input_placeholder')).backgroundColor($r('app.color.input_background'))
            .borderRadius(14).enabled(!this.locked())
            .onChange((value: string) => { this.address = value; this.addressError = false; })
          if (this.addressError) { Text($r('app.string.subscription_address_invalid')).fontSize(13).fontColor($r('app.color.danger')) }
          Text($r('app.string.subscription_privacy')).fontSize(12).lineHeight(20).fontColor($r('app.color.text_secondary'))
          if (!this.locked()) {
            PasteButton({ icon: PasteIconStyle.LINES, text: PasteDescription.PASTE, buttonType: ButtonType.Normal })
              .id('paste-subscription').fontSize(14).constraintSize({ minHeight: 48 }).borderRadius(14)
              .fontColor($r('app.color.text_primary')).iconColor($r('app.color.text_primary'))
              .backgroundColor($r('app.color.surface_background'))
              .onClick((_event: ClickEvent, result: PasteButtonOnClickResult) => {
                if (result === PasteButtonOnClickResult.SUCCESS) { this.paste(); }
              })
          }
          Button($r('app.string.import_config'), { type: ButtonType.Normal }).constraintSize({ minHeight: 48 })
            .backgroundColor($r('app.color.surface_background')).fontColor($r('app.color.text_secondary'))
            .borderRadius(14).onClick(() => this.getUIContext().getPromptAction().showToast({ message: $r('app.string.import_unavailable') }))
          Text($r('app.string.import_unavailable')).fontSize(12).lineHeight(20).fontColor($r('app.color.text_secondary'))
        }.width('100%').alignItems(HorizontalAlign.Start)
        if (this.state.subscriptionMessage) {
          Text(this.state.subscriptionMessage).id('subscription-form-feedback').fontSize(13).lineHeight(21)
            .fontColor(this.state.subscriptionFailed ? $r('app.color.danger') : $r('app.color.success'))
        }
        Button(this.state.saving ? $r('app.string.saving_address') : $r('app.string.save_address'), { type: ButtonType.Normal })
          .id('save-subscription').constraintSize({ minHeight: 52 }).width('100%').padding(16).borderRadius(14)
          .fontSize(16).fontColor($r('app.color.primary_button_text')).backgroundColor($r('app.color.primary_button_background'))
          .enabled(this.state.initialized && !this.locked()).onClick(() => this.save())
        if (this.state.saving) { LoadingProgress().width(28).height(28).color($r('app.color.accent')) }
      }.width('100%').constraintSize({ maxWidth: 640 }).padding({ left: 20, right: 20, top: 24, bottom: 32 })
        .alignItems(HorizontalAlign.Start)
    }.width('100%').height('100%').align(Alignment.Top)
  }
  build() {
    NavDestination() {
      PageScaffold({ state: this.state, title: this.state.subscriptionAddress ?
        $r('app.string.edit_subscription') : $r('app.string.add_subscription'), secondary: true,
        content: () => { this.body(); }, onBack: () => this.back() })
    }.hideTitleBar(true).backgroundColor($r('app.color.page_background'))
      .onBackPressed(() => { this.back(); return true; })
  }
}
