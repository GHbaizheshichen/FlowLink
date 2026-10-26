@ComponentV2
export struct AppIcon {
  @Param @Require source: Resource;
  @Param iconSize: number = 20;
  @Param tint: ResourceColor = $r('app.color.text_primary');

  build() {
    Image(this.source)
      .width(this.iconSize)
      .height(this.iconSize)
      .objectFit(ImageFit.Contain)
      .fillColor(this.tint)
      .draggable(false)
      .accessibilityLevel('no')
  }
}
