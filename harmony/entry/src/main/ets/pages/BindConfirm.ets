import { router } from '@kit.ArkUI';
import { BindOutcome, DEFAULT_TOTP_SCAN_CONFIG, TotpError } from 'totpscan';
import { AppContext } from '../common/AppContext';
import { errorText, hostOf, toast } from '../common/Ui';

interface BindParams {
  previewId: string;
  bindingId: string;
  issuer: string;
  account: string;
  submitUrl: string;
  pinnedDomain: string;
  pinnedPathQuery: string;
  algorithm: string;
  digits: number;
  period: number;
  expiresAt: number;
  looseSource: boolean;
  similarHints: string;
}

@Entry
@Component
struct BindConfirm {
  @State private previewId: string = '';
  @State private bindingId: string = '';
  @State private issuer: string = '';
  @State private account: string = '';
  @State private submitUrl: string = '';
  @State private pinnedDomain: string = '';
  @State private pinnedPathQuery: string = '';
  @State private algorithm: string = 'SHA1';
  @State private digits: number = 6;
  @State private period: number = 30;
  @State private expiresAt: number = -1;
  @State private looseSource: boolean = false;
  @State private similarHints: string = '';
  @State private note: string = '';
  /** confirm | working | done | unconfirmed */
  @State private stage: string = 'confirm';
  @State private outcomeMessage: string = '';
  @State private localId: string = '';
  @State private saving: boolean = false;
  private readonly maxNote: number = DEFAULT_TOTP_SCAN_CONFIG.maxNoteLength;

  aboutToAppear(): void {
    const params = router.getParams() as BindParams;
    if (params === null || params === undefined) {
      return;
    }
    this.previewId = params.previewId;
    this.bindingId = params.bindingId;
    this.issuer = params.issuer;
    this.account = params.account;
    this.submitUrl = params.submitUrl;
    this.pinnedDomain = params.pinnedDomain;
    this.pinnedPathQuery = params.pinnedPathQuery;
    this.algorithm = params.algorithm;
    this.digits = params.digits;
    this.period = params.period;
    this.expiresAt = params.expiresAt;
    this.looseSource = params.looseSource;
    this.similarHints = params.similarHints;
  }

  onBackPress(): boolean {
    this.discard();
    return false;
  }

  private discard(): void {
    const id = this.previewId;
    if (id.length === 0) {
      return;
    }
    AppContext.ready().then((client) => {
      client.discardBinding(id);
    }).catch(() => {
    });
  }

  private async confirm(): Promise<void> {
    if (this.saving || this.previewId.length === 0) {
      return;
    }
    this.saving = true;
    this.stage = 'working';
    try {
      const client = await AppContext.ready();
      const outcome: BindOutcome = await client.confirmBinding(this.previewId, this.note);
      this.localId = outcome.account.localId;
      this.outcomeMessage = outcome.message;
      this.stage = outcome.confirmed ? 'done' : 'unconfirmed';
    } catch (error) {
      this.stage = 'confirm';
      toast(errorText(error as TotpError));
    } finally {
      this.saving = false;
    }
  }

  private async retryConfirm(): Promise<void> {
    if (this.saving || this.localId.length === 0) {
      return;
    }
    this.saving = true;
    this.stage = 'working';
    try {
      const client = await AppContext.ready();
      const outcome = await client.retryBindingConfirm(this.localId);
      this.outcomeMessage = outcome.message;
      this.stage = outcome.confirmed ? 'done' : 'unconfirmed';
      if (outcome.confirmed) {
        toast('绑定已确认');
      }
    } catch (error) {
      this.stage = 'unconfirmed';
      this.outcomeMessage = errorText(error as TotpError);
    } finally {
      this.saving = false;
    }
  }

  private finish(): void {
    router.back({ url: 'pages/Index' });
  }

  @Builder
  private header(title: string) {
    Row({ space: 8 }) {
      Text('‹')
        .fontSize(28)
        .fontColor('#16332A')
        .width(32)
        .textAlign(TextAlign.Center)
        .onClick(() => {
          this.discard();
          router.back();
        })
      Text(title)
        .fontSize(17)
        .fontWeight(FontWeight.Medium)
        .fontColor('#16332A')
        .layoutWeight(1)
    }
    .width('100%')
    .padding({ left: 8, right: 16, top: 8, bottom: 8 })
  }

  @Builder
  private infoRow(label: string, value: string) {
    Row({ space: 12 }) {
      Text(label)
        .fontSize(12)
        .fontColor('#6B8077')
        .width(72)
      Text(value)
        .fontSize(12)
        .fontColor('#16332A')
        .layoutWeight(1)
        .textAlign(TextAlign.End)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .padding({ top: 7, bottom: 7 })
  }

  @Builder
  private confirmStage() {
    Column() {
      this.header('确认绑定')
      Scroll() {
        Column({ space: 14 }) {
          Column({ space: 4 }) {
            Text('即将绑定的站点')
              .fontSize(12)
              .fontColor('#6B8077')
              .width('100%')
            Text(this.issuer.length > 0 ? this.issuer :
              (this.pinnedDomain.length > 0 ? this.pinnedDomain : hostOf(this.submitUrl)))
              .fontSize(20)
              .fontWeight(FontWeight.Bold)
              .fontColor('#16332A')
              .width('100%')
            Text(this.account)
              .fontSize(13)
              .fontColor('#5F736B')
              .width('100%')
          }
          .width('100%')
          .padding(16)
          .backgroundColor(Color.White)
          .borderRadius(14)

          Column() {
            this.infoRow('钉住域名', this.pinnedDomain.length > 0 ? this.pinnedDomain : '—')
            Divider().color('#EEF2F0')
            this.infoRow('提交路径', this.pinnedPathQuery)
            Divider().color('#EEF2F0')
            this.infoRow('提交地址', this.submitUrl)
            Divider().color('#EEF2F0')
            this.infoRow('绑定标识', this.bindingId)
            Divider().color('#EEF2F0')
            this.infoRow('算法', `${this.algorithm} · ${this.digits} 位 · ${this.period} 秒`)
            Divider().color('#EEF2F0')
            this.infoRow('有效期', this.expiresAt > 0 ? new Date(this.expiresAt * 1000).toLocaleString() : '未设置')
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 6, bottom: 6 })
          .backgroundColor(Color.White)
          .borderRadius(14)

          Text('绑定后固定「注册域名 + 提交路径」：登录二维码只需域名与上面一致。' +
            '提交时始终使用上面的完整提交地址，登录二维码不会提供或改写提交目标。')
            .fontSize(11)
            .fontColor('#5F736B')
            .lineHeight(17)
            .padding(12)
            .width('100%')
            .backgroundColor('#EDF6F1')
            .borderRadius(10)

          if (this.similarHints.length > 0) {
            Text(`注意：与已信任站点相似\n${this.similarHints}\n仅作提示，仍需你自行确认站点是否可信。`)
              .fontSize(12)
              .fontColor('#7A4B12')
              .lineHeight(18)
              .padding(12)
              .width('100%')
              .backgroundColor('#FBF1E2')
              .borderRadius(10)
          }

          if (this.looseSource) {
            Text('该绑定将固化到站点根地址，匹配范围较宽。仅在你完全信任该站点时继续。')
              .fontSize(12)
              .fontColor('#A0631C')
              .lineHeight(18)
              .padding(12)
              .width('100%')
              .backgroundColor('#FBF1E2')
              .borderRadius(10)
          }

          Column({ space: 6 }) {
            Row() {
              Text('本地备注（可选）')
                .fontSize(12)
                .fontColor('#6B8077')
              Blank()
              Text(`${this.note.length}/${this.maxNote}`)
                .fontSize(11)
                .fontColor('#8A9A93')
            }
            .width('100%')
            TextInput({ text: this.note, placeholder: '例如：公司邮箱、测试环境' })
              .maxLength(this.maxNote)
              .height(44)
              .backgroundColor(Color.White)
              .borderRadius(10)
              .onChange((value: string) => {
                this.note = value;
              })
            Text('备注仅保存在本机，不进入二维码，也不会上送服务器。')
              .fontSize(10)
              .fontColor('#8A9A93')
              .width('100%')
          }
          .alignItems(HorizontalAlign.Start)
          .width('100%')

          Button('确认绑定')
            .width('100%')
            .height(46)
            .backgroundColor('#2E7D5B')
            .onClick(() => {
              this.confirm();
            })
          Button('取消')
            .width('100%')
            .backgroundColor(Color.Transparent)
            .fontColor('#5F736B')
            .onClick(() => {
              this.discard();
              router.back();
            })
        }
        .width('100%')
        .padding({ left: 16, right: 16, bottom: 28 })
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F5F7F6')
  }

  @Builder
  private workingStage() {
    Column({ space: 16 }) {
      LoadingProgress().width(44).height(44).color('#2E7D5B')
      Text('正在保存并确认绑定...')
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor('#16332A')
      Text('密钥会写入系统安全存储；确认请求只发送到上面的固化地址。')
        .fontSize(12)
        .fontColor('#6B8077')
        .textAlign(TextAlign.Center)
        .padding({ left: 32, right: 32 })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  private doneStage() {
    Column({ space: 14 }) {
      Text('✓')
        .fontSize(44)
        .fontWeight(FontWeight.Bold)
        .fontColor('#2E7D5B')
      Text('绑定已确认')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor('#16332A')
      Text(this.issuer.length > 0 ? `${this.issuer} · ${this.account}` : this.account)
        .fontSize(13)
        .fontColor('#5F736B')
      Text('该账户现在可用于扫码登录。界面不会显示它的动态码。')
        .fontSize(11)
        .fontColor('#8A9A93')
        .textAlign(TextAlign.Center)
      Button('完成')
        .width('100%')
        .height(44)
        .backgroundColor('#2E7D5B')
        .margin({ top: 10 })
        .onClick(() => {
          this.finish();
        })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .padding(28)
  }

  @Builder
  private unconfirmedStage() {
    Column({ space: 14 }) {
      Text('!')
        .fontSize(40)
        .fontWeight(FontWeight.Bold)
        .fontColor('#A0631C')
      Text('已保存到本机，但服务器未确认')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor('#16332A')
        .textAlign(TextAlign.Center)
      Text(this.outcomeMessage.length > 0 ? this.outcomeMessage : '服务器暂时未能确认绑定。绑定信息已保存在本机，可以稍后重试。')
        .fontSize(12)
        .fontColor('#6B8077')
        .textAlign(TextAlign.Center)
      Text('服务器确认前，扫码登录可能被拒绝；可稍后重试确认。动态码不会显示。')
        .fontSize(11)
        .fontColor('#8A9A93')
        .textAlign(TextAlign.Center)
      Button('重试确认')
        .width('100%')
        .height(44)
        .backgroundColor('#2E7D5B')
        .onClick(() => {
          this.retryConfirm();
        })
      Button('稍后处理')
        .width('100%')
        .backgroundColor(Color.Transparent)
        .fontColor('#5F736B')
        .onClick(() => {
          this.finish();
        })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .padding(28)
  }

  build() {
    Stack() {
      if (this.stage === 'confirm') {
        this.confirmStage()
      } else if (this.stage === 'working') {
        this.workingStage()
      } else if (this.stage === 'done') {
        this.doneStage()
      } else {
        this.unconfirmedStage()
      }
    }
    .width('100%')
    .height('100%')
  }
}
