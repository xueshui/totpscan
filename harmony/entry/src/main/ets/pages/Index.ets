import { pasteboard } from '@kit.BasicServicesKit';
import { router } from '@kit.ArkUI';
import {
  AccountKind,
  AccountView,
  ClockStatus,
  CodeSnapshot,
  TotpScanClient
} from 'totpscan';
import { AppContext } from '../common/AppContext';
import { errorText, hostOf, toast } from '../common/Ui';

@Entry
@Component
struct Index {
  @State private accounts: AccountView[] = [];
  @State private loading: boolean = true;
  @State private fatal: string = '';
  @State private clockLabel: string = '';
  @State private skewWarning: boolean = false;
  @State private scanAccountCount: number = 0;
  @State private revealScanCodes: boolean = false;
  @State private codes: Map<string, CodeSnapshot> = new Map<string, CodeSnapshot>();
  private client: TotpScanClient | null = null;
  private timerId: number = -1;

  aboutToAppear(): void {
    this.load();
  }

  onPageShow(): void {
    if (this.client !== null) {
      this.refreshAccounts();
      this.tick();
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
    this.fatal = '';
    try {
      const client = await AppContext.ready();
      this.client = client;
      this.refreshAccounts();
      this.loading = false;
      this.tick();
      this.startTimer();
    } catch (error) {
      this.fatal = errorText(error as Object);
      this.loading = false;
    }
  }

  private refreshAccounts(): void {
    const client = this.client;
    if (client === null) {
      return;
    }
    try {
      this.accounts = client.accounts();
      this.scanAccountCount = client.scanAccounts().length;
      this.revealScanCodes = client.scanCodeRevealEnabled();
    } catch (error) {
      this.fatal = errorText(error as Object);
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

  /**
   * 标准账户始终计算动态码；增强型账户仅在用户开启显示开关后才计算。
   * 开关关闭时不会调用 scanCode，列表中也不保留任何增强型账户的码。
   */
  private tick(): void {
    const client = this.client;
    if (client === null) {
      return;
    }
    const next = new Map<string, CodeSnapshot>();
    for (let i = 0; i < this.accounts.length; i += 1) {
      const account = this.accounts[i];
      if (account.kind === AccountKind.STANDARD) {
        try {
          next.set(account.localId, client.code(account.localId));
        } catch (error) {
          // 单个账户计算失败不影响其他账户展示。
        }
      } else if (this.revealScanCodes) {
        try {
          next.set(account.localId, client.scanCode(account.localId));
        } catch (error) {
          // 开关关闭或账户状态变化时静默跳过。
        }
      }
    }
    this.codes = next;
    const status: ClockStatus = client.clockStatus();
    this.clockLabel = status.label;
    this.skewWarning = status.skewWarning;
  }

  private codeOf(localId: string): string {
    const snapshot = this.codes.get(localId);
    return snapshot === undefined ? '------' : snapshot.code;
  }

  private remainingOf(localId: string): number {
    const snapshot = this.codes.get(localId);
    return snapshot === undefined ? 0 : snapshot.remainingSeconds;
  }

  private periodOf(item: AccountView): number {
    return item.period;
  }

  private copyCode(localId: string): void {
    const code = this.codeOf(localId);
    if (code === '------') {
      return;
    }
    const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, code);
    pasteboard.getSystemPasteboard().setData(data).then(() => {
      toast('动态码已复制');
    }).catch(() => {
      toast('复制失败，请重试');
    });
  }

  private async calibrate(): Promise<void> {
    const client = this.client;
    if (client === null) {
      return;
    }
    await client.calibrateClock();
    this.tick();
    toast('已完成时间校准');
  }

  @Builder
  private tag(text: string, color: string, background: string) {
    Text(text)
      .fontSize(11)
      .fontColor(color)
      .backgroundColor(background)
      .borderRadius(6)
      .padding({ left: 8, right: 8, top: 3, bottom: 3 })
  }

  @Builder
  private standardCode(item: AccountView) {
    Row({ space: 10 }) {
      Text(this.codeOf(item.localId))
        .fontSize(26)
        .fontWeight(FontWeight.Bold)
        .fontColor('#16332A')
        .letterSpacing(4)
        .onClick((event: ClickEvent) => {
          event.stopPropagation();
          this.copyCode(item.localId);
        })
      Stack() {
        Progress({
          value: this.remainingOf(item.localId),
          total: this.periodOf(item),
          type: ProgressType.Ring
        })
          .width(42)
          .height(42)
          .color('#2E7D5B')
          .backgroundColor('#E3EEE8')
          .style({ strokeWidth: 4 })
        Text(`${this.remainingOf(item.localId)}`)
          .fontSize(11)
          .fontColor('#4A6B5E')
      }
      .width(42)
      .height(42)
    }
  }

  @Builder
  private scanBadge() {
    Column({ space: 4 }) {
      Text('扫码提交')
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor('#2E7D5B')
        .backgroundColor('#E3F1EA')
        .borderRadius(8)
        .padding({ left: 10, right: 10, top: 5, bottom: 5 })
      Text(this.revealScanCodes ? '动态码暂不可用' : '不显示动态码')
        .fontSize(10)
        .fontColor('#8A9A93')
    }
    .alignItems(HorizontalAlign.End)
  }

  @Builder
  private accountCard(item: AccountView) {
    Row({ space: 12 }) {
      Column({ space: 6 }) {
        Row({ space: 8 }) {
          Text(item.displayName)
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor('#16332A')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .constraintSize({ maxWidth: '58%' })
          if (item.kind === AccountKind.STANDARD) {
            this.tag('标准 TOTP', '#3A6EA5', '#E8F0F8')
          } else {
            this.tag('增强型', '#2E7D5B', '#E3F1EA')
          }
        }
        .width('100%')

        Text(item.issuer.length > 0 ? `${item.issuer} · ${item.account}` : item.account)
          .fontSize(12)
          .fontColor('#5F736B')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        if (item.kind === AccountKind.STANDARD) {
          if (item.weakSecret) {
            Text('密钥强度不足，建议在服务端更换更长的密钥')
              .fontSize(10)
              .fontColor('#A0631C')
          }
        } else {
          Text(item.pinnedDomain.length > 0
            ? `${item.pinnedDomain}${item.pinnedPathQuery}`
            : hostOf(item.submitUrl))
            .fontSize(11)
            .fontColor('#7A8C84')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      if (item.kind === AccountKind.STANDARD ||
        (this.revealScanCodes && this.codeOf(item.localId) !== '------')) {
        this.standardCode(item)
      } else {
        this.scanBadge()
      }
    }
    .width('100%')
    .padding(16)
    .backgroundColor(Color.White)
    .borderRadius(14)
    .border({
      width: { left: 4 },
      color: item.kind === AccountKind.STANDARD ? '#3A6EA5' : '#2E7D5B'
    })
    .onClick(() => {
      router.pushUrl({ url: 'pages/AccountDetail', params: { localId: item.localId } });
    })
  }

  @Builder
  private emptyState() {
    Column({ space: 14 }) {
      Text('还没有账户')
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .fontColor('#16332A')
      Text('扫描服务端提供的绑定二维码添加增强型账户，或导入标准 TOTP 账户。')
        .fontSize(13)
        .fontColor('#5F736B')
        .textAlign(TextAlign.Center)
        .padding({ left: 16, right: 16 })
      Button('扫码绑定（增强型）')
        .width('86%')
        .backgroundColor('#2E7D5B')
        .onClick(() => {
          router.pushUrl({ url: 'pages/BindScan' });
        })
      Button('添加标准账户')
        .width('86%')
        .backgroundColor('#E3EEE8')
        .fontColor('#2E7D5B')
        .onClick(() => {
          router.pushUrl({ url: 'pages/AddAccount' });
        })
    }
    .width('100%')
    .padding({ top: 36, bottom: 36 })
    .backgroundColor(Color.White)
    .borderRadius(16)
  }

  build() {
    Column() {
      Row() {
        Column({ space: 2 }) {
          Text('扫码认证器')
            .fontSize(22)
            .fontWeight(FontWeight.Bold)
            .fontColor('#16332A')
          Text('多站点 TOTP 认证器')
            .fontSize(12)
            .fontColor('#6B8077')
        }
        .alignItems(HorizontalAlign.Start)
        Blank()
        Text('设置')
          .fontSize(14)
          .fontColor('#2E7D5B')
          .padding(8)
          .onClick(() => {
            router.pushUrl({ url: 'pages/Settings' });
          })
      }
      .width('100%')
      .padding({ left: 20, right: 20, top: 16, bottom: 12 })

      Scroll() {
        Column({ space: 14 }) {
          Column({ space: 10 }) {
            Text('扫码登录')
              .fontSize(17)
              .fontWeight(FontWeight.Medium)
              .fontColor('#FFFFFF')
            Text('扫描网页上的登录二维码。只有注册域名与钉住域名一致、且路径以钉住路径为前缀时才会提交一次性动态码。')
              .fontSize(12)
              .fontColor('#D8E8E1')
              .lineHeight(18)
            Button('打开扫码')
              .width('100%')
              .height(42)
              .backgroundColor('#FFFFFF')
              .fontColor('#1C5140')
              .fontWeight(FontWeight.Medium)
              .onClick(() => {
                router.pushUrl({ url: 'pages/Login' });
              })
            if (this.scanAccountCount === 0) {
              Text('尚未绑定增强型账户。请先在网页完成绑定，再扫描登录二维码。')
                .fontSize(11)
                .fontColor('#C9DFD5')
            }
          }
          .alignItems(HorizontalAlign.Start)
          .width('100%')
          .padding(18)
          .borderRadius(18)
          .backgroundColor('#1F5C46')

          if (this.skewWarning) {
            Row({ space: 10 }) {
              Text(this.clockLabel)
                .fontSize(12)
                .fontColor('#7A4B12')
                .layoutWeight(1)
              Text('校准')
                .fontSize(12)
                .fontColor('#A0631C')
                .fontWeight(FontWeight.Medium)
                .onClick(() => {
                  this.calibrate();
                })
            }
            .width('100%')
            .padding(12)
            .backgroundColor('#FBF1E2')
            .borderRadius(10)
          }

          Row() {
            Text('我的账户')
              .fontSize(15)
              .fontWeight(FontWeight.Medium)
              .fontColor('#16332A')
            Blank()
            Text('添加账户')
              .fontSize(13)
              .fontColor('#2E7D5B')
              .onClick(() => {
                router.pushUrl({ url: 'pages/AddAccount' });
              })
          }
          .width('100%')
          .padding({ top: 4 })

          if (this.loading) {
            Column({ space: 10 }) {
              LoadingProgress().width(36).height(36).color('#2E7D5B')
              Text('正在读取安全存储...').fontSize(12).fontColor('#6B8077')
            }
            .width('100%')
            .padding(40)
          } else if (this.fatal.length > 0) {
            Column({ space: 12 }) {
              Text('无法打开本地账户')
                .fontSize(16)
                .fontWeight(FontWeight.Medium)
                .fontColor('#8C2F2F')
              Text(this.fatal)
                .fontSize(12)
                .fontColor('#6B4B4B')
                .textAlign(TextAlign.Center)
              Button('重试')
                .backgroundColor('#2E7D5B')
                .onClick(() => {
                  this.load();
                })
            }
            .width('100%')
            .padding(28)
            .backgroundColor(Color.White)
            .borderRadius(14)
          } else if (this.accounts.length === 0) {
            this.emptyState()
          } else {
            ForEach(this.accounts, (item: AccountView) => {
              this.accountCard(item)
            }, (item: AccountView) => item.localId)
          }

          Text(this.revealScanCodes
            ? '已开启「显示扫码型账户的动态码」：增强型账户的码会直接显示，旁人可见，防钓鱼优势下降。'
            : '增强型账户只在扫码提交时于安全环境内计算动态码，界面与 SDK 均不提供即时码。')
            .fontSize(10)
            .fontColor('#8A9A93')
            .textAlign(TextAlign.Center)
            .padding({ left: 16, right: 16, top: 6, bottom: 24 })
        }
        .width('100%')
        .padding({ left: 16, right: 16 })
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F5F7F6')
  }
}
