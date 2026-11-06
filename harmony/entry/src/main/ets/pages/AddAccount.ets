import { router } from '@kit.ArkUI';

@Entry
@Component
struct AddAccount {
  @Builder
  private optionCard(title: string, tagText: string, tagColor: string, desc: string, action: string,
    onTap: () => void) {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        Text(title)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor('#16332A')
        Text(tagText)
          .fontSize(10)
          .fontColor(tagColor)
          .backgroundColor(tagColor === '#2E7D5B' ? '#E3F1EA' : '#E8F0F8')
          .borderRadius(5)
          .padding({ left: 6, right: 6, top: 2, bottom: 2 })
      }
      .width('100%')
      Text(desc)
        .fontSize(12)
        .fontColor('#6B8077')
        .lineHeight(18)
        .width('100%')
      Text(action)
        .fontSize(13)
        .fontColor('#2E7D5B')
        .fontWeight(FontWeight.Medium)
        .width('100%')
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding(16)
    .backgroundColor(Color.White)
    .borderRadius(14)
    .onClick(onTap)
  }

  build() {
    Column() {
      Row({ space: 8 }) {
        Text('‹')
          .fontSize(28)
          .fontColor('#16332A')
          .width(32)
          .textAlign(TextAlign.Center)
          .onClick(() => {
            router.back();
          })
        Text('添加账户')
          .fontSize(17)
          .fontWeight(FontWeight.Medium)
          .fontColor('#16332A')
          .layoutWeight(1)
      }
      .width('100%')
      .padding({ left: 8, right: 16, top: 8, bottom: 8 })

      Scroll() {
        Column({ space: 14 }) {
          this.optionCard(
            '扫码绑定增强型账户',
            '增强型',
            '#2E7D5B',
            '扫描服务端提供的绑定二维码。确认域名与提交路径后固化在本机，之后可用扫码登录自动提交。',
            '开始扫码 →',
            () => {
              router.pushUrl({ url: 'pages/BindScan' });
            }
          )
          this.optionCard(
            '导入 otpauth 链接',
            '标准',
            '#3A6EA5',
            '粘贴 otpauth://totp 链接，支持 SHA1/SHA256/SHA512、6/8 位与自定义时间步长。',
            '粘贴并导入 →',
            () => {
              router.pushUrl({ url: 'pages/StandardAdd', params: { mode: 'uri' } });
            }
          )
          this.optionCard(
            '手动输入密钥',
            '标准',
            '#3A6EA5',
            '手动填写签发方、账户与 Base32 密钥，适合无法使用二维码的老服务。',
            '手动添加 →',
            () => {
              router.pushUrl({ url: 'pages/StandardAdd', params: { mode: 'manual' } });
            }
          )

          Column({ space: 6 }) {
            Text('两类账户的区别')
              .fontSize(13)
              .fontWeight(FontWeight.Medium)
              .fontColor('#16332A')
            Text('标准账户：显示动态码与倒计时，可复制，不参与扫码提交。')
              .fontSize(11)
              .fontColor('#6B8077')
            Text('增强型账户：有固化提交地址，仅通过扫码提交；界面与 SDK 都不提供其即时动态码。')
              .fontSize(11)
              .fontColor('#6B8077')
          }
          .alignItems(HorizontalAlign.Start)
          .width('100%')
          .padding(14)
          .backgroundColor('#EDF2F0')
          .borderRadius(12)
        }
        .width('100%')
        .padding({ left: 16, right: 16, bottom: 24 })
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F5F7F6')
  }
}
