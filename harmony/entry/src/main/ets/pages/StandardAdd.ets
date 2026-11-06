import { pasteboard } from '@kit.BasicServicesKit';
import { router } from '@kit.ArkUI';
import {
  DEFAULT_TOTP_SCAN_CONFIG,
  OtpauthUri,
  StandardAccountInput,
  TotpError
} from 'totpscan';
import { AppContext } from '../common/AppContext';
import { errorText, toast } from '../common/Ui';

interface StandardAddParams {
  mode: string;
}

@Entry
@Component
struct StandardAdd {
  @State private mode: string = 'manual';
  @State private uriText: string = '';
  @State private issuer: string = '';
  @State private account: string = '';
  @State private secret: string = '';
  @State private algorithm: string = 'SHA1';
  @State private digits: number = 6;
  @State private periodText: string = '30';
  @State private note: string = '';
  @State private busy: boolean = false;
  @State private uriNote: string = '';
  private readonly maxNote: number = DEFAULT_TOTP_SCAN_CONFIG.maxNoteLength;

  aboutToAppear(): void {
    const params = router.getParams() as StandardAddParams;
    if (params !== null && params !== undefined && params.mode === 'uri') {
      this.mode = 'uri';
    }
  }

  private async pasteUri(): Promise<void> {
    try {
      const data = await pasteboard.getSystemPasteboard().getData();
      const text = data.getPrimaryText();
      if (text.length === 0) {
        toast('剪贴板中没有文本');
        return;
      }
      this.uriText = text;
    } catch (error) {
      toast('读取剪贴板失败');
    }
  }

  private async addFromUri(): Promise<void> {
    if (this.busy) {
      return;
    }
    if (this.uriText.trim().length === 0) {
      toast('请先粘贴 otpauth 链接');
      return;
    }
    this.busy = true;
    try {
      const client = await AppContext.ready();
      const input: StandardAccountInput = OtpauthUri.parse(this.uriText.trim());
      if (this.uriNote.trim().length > 0) {
        input.note = this.uriNote.trim();
      }
      await client.addStandardAccount(input);
      toast('标准账户已添加');
      router.back({ url: 'pages/Index' });
    } catch (error) {
      toast(errorText(error as TotpError));
    } finally {
      this.busy = false;
    }
  }

  private async addManual(): Promise<void> {
    if (this.busy) {
      return;
    }
    if (this.account.trim().length === 0) {
      toast('请填写账户标识');
      return;
    }
    if (this.secret.trim().length === 0) {
      toast('请填写 Base32 密钥');
      return;
    }
    const period = Number.parseInt(this.periodText, 10);
    if (!Number.isInteger(period) || period < 1 || period > 3600) {
      toast('时间步长需为 1–3600 秒');
      return;
    }
    this.busy = true;
    try {
      const client = await AppContext.ready();
      const input: StandardAccountInput = {
        issuer: this.issuer.trim(),
        account: this.account.trim(),
        secretBase32: this.secret.trim(),
        algorithm: this.algorithm,
        digits: this.digits,
        period: period,
        note: this.note.trim()
      };
      await client.addStandardAccount(input);
      toast('标准账户已添加');
      router.back({ url: 'pages/Index' });
    } catch (error) {
      toast(errorText(error as TotpError));
    } finally {
      this.busy = false;
    }
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
          router.back();
        })
      Text(this.mode === 'uri' ? '导入 otpauth 链接' : '手动添加标准账户')
        .fontSize(17)
        .fontWeight(FontWeight.Medium)
        .fontColor('#16332A')
        .layoutWeight(1)
    }
    .width('100%')
    .padding({ left: 8, right: 16, top: 8, bottom: 8 })
  }

  @Builder
  private fieldLabel(text: string, optional: boolean) {
    Row({ space: 6 }) {
      Text(text)
        .fontSize(12)
        .fontColor('#4A6B5E')
      if (optional) {
        Text('可选')
          .fontSize(10)
          .fontColor('#8A9A93')
      }
    }
    .width('100%')
  }

  @Builder
  private uriForm() {
    Column({ space: 10 }) {
      this.fieldLabel('otpauth 链接', false)
      TextArea({ text: this.uriText, placeholder: 'otpauth://totp/Issuer:account?secret=...&issuer=...' })
        .height(120)
        .backgroundColor(Color.White)
        .borderRadius(10)
        .onChange((value: string) => {
          this.uriText = value;
        })
      Row({ space: 10 }) {
        Button('从剪贴板粘贴')
          .layoutWeight(1)
          .backgroundColor('#E3EEE8')
          .fontColor('#2E7D5B')
          .fontSize(13)
          .onClick(() => {
            this.pasteUri();
          })
        Button('导入')
          .layoutWeight(1)
          .backgroundColor('#2E7D5B')
          .fontSize(13)
          .enabled(!this.busy)
          .onClick(() => {
            this.addFromUri();
          })
      }
      .width('100%')

      this.fieldLabel('本地备注', true)
      TextInput({ text: this.uriNote, placeholder: '例如：工作邮箱' })
        .maxLength(this.maxNote)
        .backgroundColor(Color.White)
        .borderRadius(10)
        .height(44)
        .onChange((value: string) => {
          this.uriNote = value;
        })
      Text('备注仅保存在本机，不会写入 URI 或发送给服务器。')
        .fontSize(10)
        .fontColor('#8A9A93')
        .width('100%')

      Text('链接中的密钥属于敏感数据。导入后仅保存在系统安全存储中，界面不会再次展示完整密钥。')
        .fontSize(11)
        .fontColor('#A0631C')
        .lineHeight(17)
        .padding(12)
        .width('100%')
        .backgroundColor('#FBF1E2')
        .borderRadius(10)
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
  }

  @Builder
  private manualForm() {
    Column({ space: 10 }) {
      this.fieldLabel('签发方', true)
      TextInput({ text: this.issuer, placeholder: '例如：Example Corp' })
        .height(44)
        .backgroundColor(Color.White)
        .borderRadius(10)
        .onChange((value: string) => {
          this.issuer = value;
        })

      this.fieldLabel('账户', false)
      TextInput({ text: this.account, placeholder: '邮箱或用户名' })
        .height(44)
        .backgroundColor(Color.White)
        .borderRadius(10)
        .onChange((value: string) => {
          this.account = value;
        })

      this.fieldLabel('密钥（Base32）', false)
      TextInput({ text: this.secret, placeholder: '例如：JBSWY3DPEHPK3PXP' })
        .height(44)
        .backgroundColor(Color.White)
        .borderRadius(10)
        .onChange((value: string) => {
          this.secret = value;
        })
      Text('支持空格、短横线与小写；长度需解码后不少于 10 字节。')
        .fontSize(10)
        .fontColor('#8A9A93')
        .width('100%')

      this.fieldLabel('算法', false)
      Select([{ value: 'SHA1' }, { value: 'SHA256' }, { value: 'SHA512' }])
        .selected(this.algorithm === 'SHA1' ? 0 : (this.algorithm === 'SHA256' ? 1 : 2))
        .value(this.algorithm)
        .width('100%')
        .backgroundColor(Color.White)
        .onSelect((index: number, value: string) => {
          this.algorithm = value;
        })

      this.fieldLabel('动态码位数', false)
      Row({ space: 10 }) {
        Button('6 位')
          .layoutWeight(1)
          .backgroundColor(this.digits === 6 ? '#2E7D5B' : '#E3EEE8')
          .fontColor(this.digits === 6 ? '#FFFFFF' : '#2E7D5B')
          .fontSize(13)
          .onClick(() => {
            this.digits = 6;
          })
        Button('8 位')
          .layoutWeight(1)
          .backgroundColor(this.digits === 8 ? '#2E7D5B' : '#E3EEE8')
          .fontColor(this.digits === 8 ? '#FFFFFF' : '#2E7D5B')
          .fontSize(13)
          .onClick(() => {
            this.digits = 8;
          })
      }
      .width('100%')

      this.fieldLabel('时间步长（秒）', false)
      TextInput({ text: this.periodText, placeholder: '30' })
        .type(InputType.Number)
        .height(44)
        .backgroundColor(Color.White)
        .borderRadius(10)
        .onChange((value: string) => {
          this.periodText = value;
        })
      Row({ space: 10 }) {
        Text('30 秒')
          .fontSize(12)
          .fontColor(this.periodText === '30' ? '#FFFFFF' : '#2E7D5B')
          .backgroundColor(this.periodText === '30' ? '#2E7D5B' : '#E3EEE8')
          .borderRadius(8)
          .padding({ left: 12, right: 12, top: 6, bottom: 6 })
          .onClick(() => {
            this.periodText = '30';
          })
        Text('60 秒')
          .fontSize(12)
          .fontColor(this.periodText === '60' ? '#FFFFFF' : '#2E7D5B')
          .backgroundColor(this.periodText === '60' ? '#2E7D5B' : '#E3EEE8')
          .borderRadius(8)
          .padding({ left: 12, right: 12, top: 6, bottom: 6 })
          .onClick(() => {
            this.periodText = '60';
          })
      }
      .width('100%')

      this.fieldLabel('本地备注', true)
      TextInput({ text: this.note, placeholder: '例如：工作邮箱' })
        .maxLength(this.maxNote)
        .height(44)
        .backgroundColor(Color.White)
        .borderRadius(10)
        .onChange((value: string) => {
          this.note = value;
        })
      Text('备注仅保存在本机，列表与详情中会优先显示。')
        .fontSize(10)
        .fontColor('#8A9A93')
        .width('100%')

      Button('添加账户')
        .width('100%')
        .height(46)
        .backgroundColor('#2E7D5B')
        .margin({ top: 6 })
        .enabled(!this.busy)
        .onClick(() => {
          this.addManual();
        })

      Text('标准账户不支持扫码提交，也不具备地址比对防护；动态码需要手动复制到网页。')
        .fontSize(11)
        .fontColor('#6B8077')
        .lineHeight(17)
        .padding(12)
        .width('100%')
        .backgroundColor('#EDF2F0')
        .borderRadius(10)
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
  }

  build() {
    Column() {
      this.header()
      Scroll() {
        Column({ space: 12 }) {
          if (this.mode === 'uri') {
            this.uriForm()
          } else {
            this.manualForm()
          }
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
}
