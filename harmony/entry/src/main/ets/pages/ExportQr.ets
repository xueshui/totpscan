import { router, window } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { image } from '@kit.ImageKit';
import { scanBarcode, scanCore } from '@kit.ScanKit';
import { AccountKind, AccountView, TotpError, TotpScanClient } from 'totpscan';
import { AppContext } from '../common/AppContext';
import { consumeExportGrant, revokeExportGrant } from '../common/ExportGrant';
import { errorText, toast } from '../common/Ui';

interface ExportParams {
  localId: string;
}

const AUTO_CLOSE_SECONDS = 60;
const QR_SIZE = 260;

/**
 * 单账户导出 otpauth 二维码（仅屏幕展示）。
 *
 * - 只接收 localId，URI 在页面内即时生成，生成后立即清空内存字符串；
 * - 不提供复制密钥/复制链接，不写剪贴板、不写日志、不落盘；
 * - 打开时开启窗口隐私模式（防截屏），离开时关闭；
 * - 二维码默认模糊遮罩，点击后显示，60 秒自动关闭并清空。
 */
@Entry
@Component
struct ExportQr {
  @State private loading: boolean = true;
  @State private fatal: string = '';
  @State private title: string = '';
  @State private subtitle: string = '';
  @State private isScanAccount: boolean = false;
  @State private qr: image.PixelMap | null = null;
  @State private revealed: boolean = false;
  @State private remaining: number = AUTO_CLOSE_SECONDS;
  private localId: string = '';
  private timerId: number = -1;
  private win: window.Window | null = null;

  aboutToAppear(): void {
    this.enablePrivacyMode();
    const params = router.getParams() as ExportParams;
    if (params !== null && params !== undefined) {
      this.localId = params.localId;
    }
    this.prepare();
  }

  aboutToDisappear(): void {
    this.stopTimer();
    this.clearSensitive();
    revokeExportGrant();
    this.disablePrivacyMode();
  }

  private enablePrivacyMode(): void {
    const context = getContext(this) as common.UIAbilityContext;
    window.getLastWindow(context).then((win: window.Window) => {
      this.win = win;
      win.setWindowPrivacyMode(true).catch(() => {
        // 隐私模式不可用时仍继续，但界面不展示明文以外的内容。
      });
    }).catch(() => {
    });
  }

  private disablePrivacyMode(): void {
    const win = this.win;
    this.win = null;
    if (win !== null) {
      win.setWindowPrivacyMode(false).catch(() => {
      });
    }
  }

  private async prepare(): Promise<void> {
    if (this.localId.length === 0 || !consumeExportGrant(this.localId)) {
      this.fatal = '身份验证已失效，请返回账户详情重新发起导出';
      this.loading = false;
      return;
    }
    try {
      const client: TotpScanClient = await AppContext.ready();
      const account: AccountView = client.account(this.localId);
      this.title = account.displayName;
      this.subtitle = account.issuer.length > 0
        ? `${account.issuer} · ${account.account}`
        : account.account;
      this.isScanAccount = account.kind === AccountKind.SCAN;
      let uri: string = client.exportOtpauthUri(this.localId);
      try {
        const options: scanBarcode.GenerateBarcodeOptions = {
          scanType: scanCore.ScanType.QR_CODE,
          width: QR_SIZE,
          height: QR_SIZE,
          margin: 1
        };
        this.qr = await scanBarcode.generateBarcode(uri, options);
      } finally {
        // 二维码生成后立即丢弃 URI 字符串，只保留位图。
        uri = '';
      }
      this.loading = false;
    } catch (error) {
      this.fatal = errorText(error as TotpError);
      this.loading = false;
    }
  }

  private reveal(): void {
    if (this.qr === null || this.revealed) {
      return;
    }
    this.revealed = true;
    this.remaining = AUTO_CLOSE_SECONDS;
    this.stopTimer();
    this.timerId = setInterval(() => {
      this.remaining = this.remaining - 1;
      if (this.remaining <= 0) {
        this.closeAndClear(true);
      }
    }, 1000);
  }

  private stopTimer(): void {
    if (this.timerId >= 0) {
      clearInterval(this.timerId);
      this.timerId = -1;
    }
  }

  private clearSensitive(): void {
    this.revealed = false;
    this.remaining = AUTO_CLOSE_SECONDS;
    const qr = this.qr;
    this.qr = null;
    if (qr !== null) {
      qr.release().catch(() => {
      });
    }
  }

  private closeAndClear(notify: boolean): void {
    this.stopTimer();
    this.clearSensitive();
    if (notify) {
      toast('二维码已自动关闭');
    }
    router.back();
  }

  @Builder
  private header() {
    Row({ space: 8 }) {
      Text('‹')
        .fontSize(28)
        .fontColor('#16332A')
        .width(32)
        .textAlign(TextAlign.Center)
        .onClick(() => {
          this.closeAndClear(false);
        })
      Text('导出二维码')
        .fontSize(17)
        .fontWeight(FontWeight.Medium)
        .fontColor('#16332A')
        .layoutWeight(1)
    }
    .width('100%')
    .padding({ left: 8, right: 16, top: 8, bottom: 8 })
  }

  @Builder
  private qrArea() {
    Column({ space: 12 }) {
      Column() {
        Stack() {
          Image(this.qr as image.PixelMap)
            .width(QR_SIZE)
            .height(QR_SIZE)
            .objectFit(ImageFit.Contain)
            .blur(this.revealed ? 0 : 18)
          if (!this.revealed) {
            Column({ space: 6 }) {
              Text('点击显示二维码')
                .fontSize(14)
                .fontColor('#16332A')
                .fontWeight(FontWeight.Medium)
              Text('默认模糊，防止旁人与截屏获取')
                .fontSize(10)
                .fontColor('#5F736B')
            }
            .width('100%')
            .height('100%')
            .justifyContent(FlexAlign.Center)
            .backgroundColor('#CCF2F5F3')
          }
        }
        .width(QR_SIZE)
        .height(QR_SIZE)
        .borderRadius(12)
        .clip(true)
        .onClick(() => {
          this.reveal();
        })

        if (this.revealed) {
          Text(`二维码将在 ${this.remaining} 秒后自动关闭`)
            .fontSize(11)
            .fontColor('#A0631C')
            .padding({ top: 10 })
        }
      }
      .width('100%')
      .padding(16)
      .backgroundColor(Color.White)
      .borderRadius(16)
      .alignItems(HorizontalAlign.Center)

      Text('页面已请求开启窗口隐私模式；支持的设备上将阻止截屏与录屏。本页不提供复制功能，二维码只在本机屏幕上显示。')
        .fontSize(10)
        .fontColor('#8A9A93')
        .lineHeight(16)
        .width('100%')
        .padding({ left: 6, right: 6 })
    }
    .width('100%')
  }

  build() {
    Column() {
      this.header()
      if (this.loading) {
        Column({ space: 10 }) {
          LoadingProgress().width(36).height(36).color('#2E7D5B')
          Text('正在生成二维码...').fontSize(12).fontColor('#6B8077')
        }
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else if (this.fatal.length > 0 || this.qr === null) {
        Column({ space: 12 }) {
          Text('无法导出二维码').fontSize(17).fontColor('#8C2F2F')
          Text(this.fatal.length > 0 ? this.fatal : '二维码生成失败，请升级系统后重试')
            .fontSize(12)
            .fontColor('#6B4B4B')
            .textAlign(TextAlign.Center)
          Button('返回')
            .backgroundColor('#2E7D5B')
            .onClick(() => {
              this.clearSensitive();
              router.back();
            })
        }
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .padding(24)
      } else {
        Scroll() {
          Column({ space: 14 }) {
            Column({ space: 4 }) {
              Text(this.title)
                .fontSize(16)
                .fontWeight(FontWeight.Medium)
                .fontColor('#16332A')
                .width('100%')
              Text(this.subtitle)
                .fontSize(11)
                .fontColor('#5F736B')
                .width('100%')
            }
            .width('100%')
            .padding(14)
            .backgroundColor(Color.White)
            .borderRadius(12)
            .alignItems(HorizontalAlign.Start)

            this.qrArea()

            if (this.isScanAccount) {
              Text('该账户为增强型账户：导出后其防钓鱼优势失效，任何扫码者都能独立生成动态码。')
                .fontSize(11)
                .fontColor('#A0631C')
                .lineHeight(17)
                .width('100%')
                .padding(12)
                .backgroundColor('#FBF1E2')
                .borderRadius(10)
            } else {
              Text('该二维码包含账户密钥，可被任意兼容的认证器导入。请勿展示给他人。')
                .fontSize(11)
                .fontColor('#A0631C')
                .lineHeight(17)
                .width('100%')
                .padding(12)
                .backgroundColor('#FBF1E2')
                .borderRadius(10)
            }
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 8, bottom: 24 })
        }
        .layoutWeight(1)
        .scrollBar(BarState.Off)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F5F7F6')
  }
}
