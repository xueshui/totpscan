import { router } from '@kit.ArkUI';
import { pasteboard } from '@kit.BasicServicesKit';
import {
  AccountKind,
  AccountView,
  BiometricGate,
  CodeSnapshot,
  TotpError,
  TotpScanClient
} from 'totpscan';
import { AppContext } from '../common/AppContext';
import { grantExport } from '../common/ExportGrant';
import { errorText, toast } from '../common/Ui';

interface DetailParams {
  localId: string;
}

@Entry
@Component
struct AccountDetail {
  @State private localId: string = '';
  @State private account: AccountView = {
    localId: '',
    kind: AccountKind.STANDARD,
    issuer: '',
    account: '',
    displayName: '',
    algorithm: 'SHA1',
    digits: 6,
    period: 30,
    createdAtMs: 0,
    submitUrl: '',
    pinnedDomain: '',
    pinnedPathQuery: '',
    bindingId: '',
    bindingConfirmed: false,
    weakSecret: false
  };
  @State private loaded: boolean = false;
  @State private code: string = '------';
  @State private remaining: number = 0;
  @State private period: number = 30;
  @State private note: string = '';
  @State private loading: boolean = true;
  @State private fatal: string = '';
  @State private savingNote: boolean = false;
  @State private confirming: boolean = false;
  @State private exporting: boolean = false;
  @State private revealScanCodes: boolean = false;
  private client: TotpScanClient | null = null;
  private timerId: number = -1;
  private maxNote: number = 64;

  aboutToAppear(): void {
    const params = router.getParams() as DetailParams;
    if (params !== null && params !== undefined) {
      this.localId = params.localId;
    }
    this.load();
  }

  onPageShow(): void {
    if (this.client !== null) {
      this.refresh();
      this.startTimer();
    }
  }

  onPageHide(): void {
    this.stopTimer();
  }

  aboutToDisappear(): void {
    this.stopTimer();
  }

  private async load(): Promise<void> {
    this.loading = true;
    try {
      const client = await AppContext.ready();
      this.client = client;
      this.maxNote = client.maxNoteLength();
      this.refresh();
      this.loading = false;
      this.startTimer();
    } catch (error) {
      this.fatal = errorText(error as TotpError);
      this.loading = false;
    }
  }

  private refresh(): void {
    if (this.client === null) {
      return;
    }
    try {
      const account = this.client.account(this.localId);
      this.account = account;
      this.loaded = true;
      this.period = account.period;
      this.note = account.displayName;
      this.revealScanCodes = this.client.scanCodeRevealEnabled();
      this.tick();
    } catch (error) {
      this.fatal = errorText(error as TotpError);
    }
  }

  private startTimer(): void {
    this.stopTimer();
    this.timerId = setInterval(() => {
      this.tick();
    }, 1000);
  }

  private stopTimer(): void {
    if (this.timerId >= 0) {
      clearInterval(this.timerId);
      this.timerId = -1;
    }
  }

  private tick(): void {
    if (!this.loaded || this.client === null) {
      return;
    }
    if (this.account.kind !== AccountKind.STANDARD && !this.revealScanCodes) {
      // 增强型账户默认不计算、不缓存、不展示即时码。
      this.code = '------';
      this.remaining = 0;
      return;
    }
    try {
      const snapshot: CodeSnapshot = this.account.kind === AccountKind.STANDARD
        ? this.client.code(this.account.localId)
        : this.client.scanCode(this.account.localId);
      this.code = snapshot.code;
      this.remaining = snapshot.remainingSeconds;
    } catch (error) {
      this.code = '------';
      this.remaining = 0;
    }
  }

  /** 标准账户始终可复制；增强型账户仅在用户开启显示开关后可复制。 */
  private canCopy(): boolean {
    if (!this.loaded) {
      return false;
    }
    return this.account.kind === AccountKind.STANDARD || this.revealScanCodes;
  }

  private copyCode(): void {
    if (!this.canCopy() || this.code === '------') {
      return;
    }
    const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, this.code);
    pasteboard.getSystemPasteboard().setData(data).then(() => {
      toast('动态码已复制');
    }).catch(() => {
      toast('复制失败，请重试');
    });
  }

  private async saveNote(): Promise<void> {
    if (this.client === null || this.savingNote) {
      return;
    }
    this.savingNote = true;
    try {
      const updated = await this.client.renameAccount(this.localId, this.note);
      this.account = updated;
      this.note = updated.displayName;
      toast('备注已保存');
    } catch (error) {
      toast(errorText(error as TotpError));
    } finally {
      this.savingNote = false;
    }
  }

  private async retryConfirm(): Promise<void> {
    if (this.client === null || this.confirming) {
      return;
    }
    this.confirming = true;
    try {
      const outcome = await this.client.retryBindingConfirm(this.localId);
      this.refresh();
      toast(outcome.confirmed ? '绑定已确认' : outcome.message);
    } catch (error) {
      toast(errorText(error as TotpError));
    } finally {
      this.confirming = false;
    }
  }

  private exportQr(): void {
    if (!this.loaded || this.exporting) {
      return;
    }
    if (this.account.kind === AccountKind.SCAN) {
      AlertDialog.show({
        title: '导出增强型账户二维码',
        message: '导出后该账户的防钓鱼优势失效，任何扫码者都能独立生成动态码。' +
          '二维码只会显示在本机屏幕上，请勿展示给他人或在不可信环境截屏。',
        primaryButton: {
          value: '取消',
          action: () => {
          }
        },
        secondaryButton: {
          value: '继续导出',
          fontColor: '#C0392B',
          action: () => {
            this.doExport();
          }
        }
      });
      return;
    }
    this.doExport();
  }

  private async doExport(): Promise<void> {
    if (this.exporting) {
      return;
    }
    this.exporting = true;
    try {
      await BiometricGate.authenticateStrong('验证身份以导出账户二维码');
      grantExport(this.localId);
      router.pushUrl({ url: 'pages/ExportQr', params: { localId: this.localId } });
    } catch (error) {
      toast(errorText(error as TotpError));
    } finally {
      this.exporting = false;
    }
  }

  private deleteAccount(): void {
    const enhanced = this.loaded && this.account.kind === AccountKind.SCAN;
    AlertDialog.show({
      title: '删除账户',
      message: enhanced
        ? '仅删除本机的密钥与固化地址。服务器端的绑定仍然有效，如需彻底解绑，请在服务端管理界面撤销。'
        : '删除后本机将无法再生成该账户的动态码。请确认你仍能通过其他方式登录。',
      primaryButton: {
        value: '取消',
        action: () => {
        }
      },
      secondaryButton: {
        value: '删除',
        fontColor: '#C0392B',
        action: () => {
          this.doDelete();
        }
      }
    });
  }

  private async doDelete(): Promise<void> {
    if (this.client === null) {
      return;
    }
    try {
      await this.client.removeAccount(this.localId);
      toast('账户已删除');
      router.back();
    } catch (error) {
      toast(errorText(error as TotpError));
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
      Text('账户详情')
        .fontSize(17)
        .fontWeight(FontWeight.Medium)
        .fontColor('#16332A')
        .layoutWeight(1)
      Text('删除')
        .fontSize(14)
        .fontColor('#C0392B')
        .padding(8)
        .onClick(() => {
          this.deleteAccount();
        })
    }
    .width('100%')
    .padding({ left: 8, right: 12, top: 8, bottom: 8 })
  }

  @Builder
  private detailRow(name: string, content: string) {
    Row({ space: 12 }) {
      Text(name)
        .fontSize(11)
        .fontColor('#6B8077')
        .width(76)
      Text(content)
        .fontSize(13)
        .fontColor('#16332A')
        .textAlign(TextAlign.End)
        .maxLines(3)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
    .padding({ top: 8, bottom: 8 })
  }

  @Builder
  private standardSection(account: AccountView) {
    Column({ space: 10 }) {
      Row({ space: 12 }) {
        Text(this.code)
          .fontSize(34)
          .fontWeight(FontWeight.Bold)
          .fontColor('#16332A')
          .letterSpacing(6)
          .onClick(() => {
            this.copyCode();
          })
        Stack() {
          Progress({
            value: this.remaining,
            total: this.period,
            type: ProgressType.Ring
          })
            .width(46)
            .height(46)
            .color('#2E7D5B')
            .backgroundColor('#E3EEE8')
            .style({ strokeWidth: 4 })
          Text(`${this.remaining}`)
            .fontSize(11)
            .fontColor('#4A6B5E')
        }
        .width(46)
        .height(46)
      }
      .width('100%')
      Text('点击动态码即可复制。请勿把动态码提供给他人。')
        .fontSize(10)
        .fontColor('#8A9A93')
        .width('100%')
      if (account.weakSecret) {
        Text('该密钥不足 128 位，强度偏低。建议在服务端重新生成更长的密钥。')
          .fontSize(11)
          .fontColor('#A0631C')
          .lineHeight(17)
          .width('100%')
          .padding(10)
          .backgroundColor('#FBF1E2')
          .borderRadius(8)
      }
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding(18)
    .backgroundColor(Color.White)
    .borderRadius(14)
  }

  @Builder
  private scanSection() {
    Column({ space: 8 }) {
      if (this.revealScanCodes) {
        Row({ space: 12 }) {
          Text(this.code)
            .fontSize(34)
            .fontWeight(FontWeight.Bold)
            .fontColor('#16332A')
            .letterSpacing(6)
            .onClick(() => {
              this.copyCode();
            })
          Stack() {
            Progress({
              value: this.remaining,
              total: this.period,
              type: ProgressType.Ring
            })
              .width(46)
              .height(46)
              .color('#2E7D5B')
              .backgroundColor('#E3EEE8')
              .style({ strokeWidth: 4 })
            Text(`${this.remaining}`)
              .fontSize(11)
              .fontColor('#4A6B5E')
          }
          .width(46)
          .height(46)
        }
        .width('100%')
        Text('已开启「显示扫码型账户的动态码」：点击动态码即可复制，旁人可见，请注意周围环境。')
          .fontSize(10)
          .fontColor('#A0631C')
          .lineHeight(16)
          .width('100%')
        Text('扫码提交路径不受影响；也可继续从首页“扫码登录”使用该账户。')
          .fontSize(10)
          .fontColor('#8A9A93')
          .width('100%')
      } else {
        Text('动态码受保护')
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor('#16332A')
        Text('该账户的即时动态码不会在界面显示或复制，只在扫码提交时由安全模块内部计算，并发送到下面的固化地址。')
          .fontSize(12)
          .fontColor('#5F736B')
          .lineHeight(18)
        Text('请从首页“扫码登录”扫描网页上的登录二维码。')
          .fontSize(11)
          .fontColor('#2E7D5B')
      }
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding(18)
    .backgroundColor(Color.White)
    .borderRadius(14)
  }

  @Builder
  private noteSection() {
    Column({ space: 8 }) {
      Row() {
        Text('本地备注')
          .fontSize(12)
          .fontColor('#4A6B5E')
        Blank()
        Text(`${this.note.length}/${this.maxNote}`)
          .fontSize(10)
          .fontColor('#8A9A93')
      }
      .width('100%')
      TextInput({ text: this.note, placeholder: '可选，例如：公司邮箱' })
        .maxLength(this.maxNote)
        .height(44)
        .backgroundColor(Color.White)
        .borderRadius(10)
        .onChange((value: string) => {
          this.note = value;
        })
      Button('保存备注')
        .width('100%')
        .height(40)
        .backgroundColor('#E3EEE8')
        .fontColor('#2E7D5B')
        .enabled(!this.savingNote)
        .onClick(() => {
          this.saveNote();
        })
      Text('备注只保存在本机，不会进入二维码或任何请求。')
        .fontSize(10)
        .fontColor('#8A9A93')
        .width('100%')
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
  }

  @Builder
  private content(account: AccountView) {
    Scroll() {
      Column({ space: 14 }) {
        Row({ space: 8 }) {
          Text(account.displayName)
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor('#16332A')
            .layoutWeight(1)
          Text(account.kind === AccountKind.STANDARD ? '标准 TOTP' : '增强型')
            .fontSize(11)
            .fontColor(account.kind === AccountKind.STANDARD ? '#3A6EA5' : '#2E7D5B')
            .backgroundColor(account.kind === AccountKind.STANDARD ? '#E8F0F8' : '#E3F1EA')
            .borderRadius(6)
            .padding({ left: 8, right: 8, top: 3, bottom: 3 })
        }
        .width('100%')

        if (account.kind === AccountKind.STANDARD) {
          this.standardSection(account)
        } else {
          this.scanSection()
        }

        Column() {
          this.detailRow('签发方', account.issuer.length > 0 ? account.issuer : '—')
          Divider().color('#EEF2F0')
          this.detailRow('账户', account.account)
          Divider().color('#EEF2F0')
          this.detailRow('算法', `${account.algorithm} · ${account.digits} 位 · ${account.period} 秒`)
          if (account.kind === AccountKind.SCAN) {
            Divider().color('#EEF2F0')
            this.detailRow('提交地址', account.submitUrl)
            Divider().color('#EEF2F0')
            this.detailRow('钉住域名', account.pinnedDomain.length > 0 ? account.pinnedDomain : '—')
            Divider().color('#EEF2F0')
            this.detailRow('提交路径', account.pinnedPathQuery)
            Divider().color('#EEF2F0')
            this.detailRow('绑定状态', account.bindingConfirmed ? '已确认' : '未确认')
          }
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 6, bottom: 6 })
        .backgroundColor(Color.White)
        .borderRadius(14)

        Column({ space: 8 }) {
          Button(this.exporting ? '正在验证身份...' : '导出二维码')
            .width('100%')
            .height(42)
            .backgroundColor('#E3EEE8')
            .fontColor('#2E7D5B')
            .enabled(!this.exporting)
            .onClick(() => {
              this.exportQr();
            })
          Text(account.kind === AccountKind.SCAN
            ? '导出为 otpauth 二维码，供其他认证器导入。增强型账户导出后防钓鱼优势失效。'
            : '导出为 otpauth 二维码，供其他认证器导入。二维码包含账户密钥，请勿展示给他人。')
            .fontSize(10)
            .fontColor('#8A9A93')
            .lineHeight(16)
            .width('100%')
          Text('需要先通过本地身份验证；二维码只在屏幕上显示 60 秒，不提供复制，不写入剪贴板或文件。')
            .fontSize(10)
            .fontColor('#8A9A93')
            .lineHeight(16)
            .width('100%')
        }
        .alignItems(HorizontalAlign.Start)
        .width('100%')
        .padding(14)
        .backgroundColor(Color.White)
        .borderRadius(12)

        if (account.kind === AccountKind.SCAN && !account.bindingConfirmed) {
          Column({ space: 10 }) {
            Text('服务器尚未确认该绑定；确认前扫码登录可能被拒绝。')
              .fontSize(12)
              .fontColor('#A0631C')
              .width('100%')
            Button(this.confirming ? '正在确认...' : '重试绑定确认')
              .width('100%')
              .height(40)
              .backgroundColor('#2E7D5B')
              .enabled(!this.confirming)
              .onClick(() => {
                this.retryConfirm();
              })
          }
          .alignItems(HorizontalAlign.Start)
          .width('100%')
          .padding(14)
          .backgroundColor('#FBF1E2')
          .borderRadius(12)
        }

        this.noteSection()

        if (account.kind === AccountKind.SCAN) {
          Text(this.revealScanCodes
            ? '已开启「显示扫码型账户的动态码」：动态码会被他人看到，防钓鱼优势下降。可在设置中随时关闭。'
            : '此账户的动态码不会离开本机；服务器端撤销绑定需要在服务端管理界面完成。')
            .fontSize(10)
            .fontColor(this.revealScanCodes ? '#A0631C' : '#8A9A93')
            .lineHeight(16)
            .width('100%')
            .padding({ left: 4, right: 4 })
        } else {
          Text('标准账户不参与扫码提交；密钥只出现在导出的二维码中，界面不提供复制。')
            .fontSize(10)
            .fontColor('#8A9A93')
            .lineHeight(16)
            .width('100%')
            .padding({ left: 4, right: 4 })
        }
      }
      .width('100%')
      .padding({ left: 16, right: 16, bottom: 28 })
    }
    .layoutWeight(1)
    .scrollBar(BarState.Off)
  }

  build() {
    Column() {
      this.header()
      if (this.loading) {
        Column({ space: 10 }) {
          LoadingProgress().width(36).height(36).color('#2E7D5B')
          Text('正在读取账户...').fontSize(12).fontColor('#6B8077')
        }
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else if (!this.loaded || this.fatal.length > 0) {
        Column({ space: 12 }) {
          Text('无法打开账户').fontSize(17).fontColor('#8C2F2F')
          Text(this.fatal).fontSize(12).fontColor('#6B4B4B').textAlign(TextAlign.Center)
          Button('返回')
            .backgroundColor('#2E7D5B')
            .onClick(() => {
              router.back();
            })
        }
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .padding(24)
      } else {
        this.content(this.account)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F5F7F6')
  }
}
