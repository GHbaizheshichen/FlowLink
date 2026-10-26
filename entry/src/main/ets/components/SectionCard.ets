@Builder
export function SectionCard(title: ResourceStr, description: ResourceStr) {
  Column({ space: 8 }) {
    Text(title)
      .fontSize(16)
      .fontWeight(FontWeight.Medium)
      .fontColor($r('app.color.text_primary'))
    Text(description)
      .fontSize(14)
      .fontColor($r('app.color.text_secondary'))
      .lineHeight(22)
  }
  .alignItems(HorizontalAlign.Start)
  .padding(20)
  .width('100%')
  .borderRadius(20)
  .backgroundColor($r('app.color.surface_background'))
}
