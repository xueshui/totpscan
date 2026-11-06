import { router } from '@kit.ArkUI';
import { BindingPreview, TotpError } from 'totpscan';
import { QrScanner } from '../components/QrScanner';
import { AppContext } from '../common/AppContext';
import { errorText } from '../common/Ui';

@Entry
@Component
struct BindScan {
  /** scan | parsing | error */
  @State private stage: string = 'scan';
  @State private visible: boolean = true;
  @State private errorMessage: string = '';
  @State private busy: boolean = false;

  onPageShow(): void {
    this.visible = true;
    // 从地址确认页返回时恢复扫码；正在校验时保持“校验中”，避免重复触发。
    if (this.stage === 'parsing' && !this.busy) {
      this.stage = 'scan';
    }
  }

  onPageHide(): void {
    this.visible = false;
  }

  private async handleQr(text: string): Promise<void> {
    if (this.busy) {
      return;
    }
    this.busy = true;
    this.stage = 'parsing';
    try {
      const client = await AppContext.ready();
      const preview: BindingPreview = await client.prepareBinding(text);
      router.pushUrl({
        url: 'pages/BindConfirm',
        params: {
          previewId: preview.previewId,
          bindingId: preview.bindingId,
          issuer: preview.issuer,
          account: preview.account,
          submitUrl: preview.submitUrl,
          pinnedDomain: preview.pinnedDomain,
          pinnedPathQuery: preview.pinnedPathQuery,
          algorithm: preview.algorithm,
          digits: preview.digits,
          period: preview.period,
          expiresAt: preview.expiresAt,
          looseSource: preview.looseSource,
          similarHints: preview.similarHints.join('\n')
        }
      });
    } catch (error) {
      this.errorMessage = errorText(error as TotpError);
      this.stage = 'error';
    } finally {
      this.busy = false;
    }
  }

  build() {
    Column() {
      Row({ space: 8 }) {
        Text('‹')
          .fontSize(28)
          .fontColor('#FFFFFF')
          .width(36)
          .textAlign(TextAlign.Center)
          .onClick(() => {
            router.back();
          })
        Text('扫码绑定')
          .fontSize(17)
          .fontWeight(FontWeight.Medium)
          .fontColor('#FFFFFF')
          .layoutWeight(1)
      }
      .width('100%')
      .padding({ left: 8, right: 16, top: 8, bottom: 4 })

      if (this.stage === 'error') {
        Column({ space: 14 }) {
          Text('无法添加该账户')
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor('#FFFFFF')
          Text(this.errorMessage)
            .fontSize(13)
            .fontColor('#C8D8D1')
            .textAlign(TextAlign.Center)
          Text('未写入任何数据，也未向服务器发送任何内容。')
            .fontSize(12)
            .fontColor('#2E7D5B')
            .textAlign(TextAlign.Center)
            .padding(12)
            .backgroundColor('#EDF6F1')
            .borderRadius(10)
          Button('重新扫描')
            .width('100%')
            .backgroundColor('#2E7D5B')
            .onClick(() => {
              this.errorMessage = '';
              this.stage = 'scan';
            })
          Button('返回')
            .width('100%')
            .backgroundColor(Color.Transparent)
            .fontColor('#B9C9C2')
            .onClick(() => {
              router.back();
            })
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .padding(24)
      } else if (this.stage === 'parsing') {
        Column({ space: 14 }) {
          LoadingProgress().width(44).height(44).color('#7CE0B0')
          Text('正在校验绑定二维码...')
            .fontSize(14)
            .fontColor('#D8E8E1')
          Text('域名、提交路径与地址会在本地校验')
            .fontSize(11)
            .fontColor('#8FA89E')
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else if (this.visible) {
        QrScanner({
          onResult: (text: string) => {
            this.handleQr(text);
          }
        })
          .layoutWeight(1)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#0B1915')
  }
}
