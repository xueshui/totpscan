import { router } from '@kit.ArkUI';
import { BiometricGate, ClockStatus, TotpError, TotpScanClient, TrustedSite } from 'totpscan';
import { AppContext } from '../common/AppContext';
import { errorText, toast } from '../common/Ui';

/** 开启「显示扫码型账户的动态码」前的风险确认。 */
@CustomDialog
struct RevealRiskDialog {
  controller: CustomDialogController;
  @State private agreed: boolean = false;
  onConfirm: () => void = () => {
  };

  aboutToAppear(): void {
    this.agreed = false;
  }

  build() {
    Column({ space: 12 }) {
      Text('开启「显示扫码型账户的动态码」')
        .fontSize(17)
        .fontWeight(FontWeight.Medium)
        .fontColor('#16332A')
        .width('100%')
      Text('开启后，扫码型账户的六位动态码会直接在首页与账户详情中显示，并可复制。\n' +
        '旁人可见，防钓鱼优势下降：钓鱼页面可能诱导你读出或输入该动态码。\n' +
        '扫码提交路径保持不变；可随时在设置中关闭。')
        .fontSize(12)
        .fontColor('#5F736B')
        .lineHeight(19)
        .width('100%')
      Row({ space: 8 }) {
        Checkbox({ name: 'reveal-risk' })
          .select(this.agreed)
          .selectedColor('#C0392B')
          .onChange((value: boolean) => {
            this.agreed = value;
          })
        Text('我已了解风险，仍要开启')
          .fontSize(12)
          .fontColor('#16332A')
          .layoutWeight(1)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      Row({ space: 10 }) {
        Button('取消')
          .layoutWeight(1)
          .height(40)
          .backgroundColor('#F0F3F1')
          .fontColor('#4A6B5E')
          .onClick(() => {
            this.controller.close();
          })
        Button('确认开启')
          .layoutWeight(1)
          .height(40)
          .backgroundColor(this.agreed ? '#C0392B' : '#E6D3D3')
          .fontColor('#FFFFFF')
          .enabled(this.agreed)
          .onClick(() => {
            this.controller.close();
            this.onConfirm();
          })
      }
      .width('100%')
    }
    .width('100%')
    .padding(20)
    .backgroundColor(Color.White)
    .borderRadius(16)
  }
}

@Entry
@Component
struct Settings {
  @State private loading: boolean = true;
  @State private fatal: string = '';
  @State private biometric: boolean = true;
  @State private biometricAvailable: boolean = false;
  @State private revealScanCodes: boolean = false;
  @State private clockLabel: string = '尚未校准';
  @State private offsetLabel: string = '—';
  @State private skewWarning: boolean = false;
  @State private sites: TrustedSite[] = [];
  @State private totalCount: number = 0;
  @State private scanCount: number = 0;
  @State private standardCount: number = 0;
  @State private calibrating: boolean = false;
  @State private clearing: boolean = false;
  private client: TotpScanClient | null = null;
  revealDialog: CustomDialogController = new CustomDialogController({
    builder: RevealRiskDialog({
      onConfirm: () => {
        this.enableReveal();
      }
    }),
    autoCancel: true,
    alignment: DialogAlignment.Center
  });

  aboutToAppear(): void {
    this.load();
  }

  private async load(): Promise<void> {
    this.loading = true;
    this.fatal = '';
    try {
      const client = await AppContext.ready();
      this.client = client;
      this.biometricAvailable = BiometricGate.available();
      this.biometric = client.biometricRequired();
      this.revealScanCodes = client.scanCodeRevealEnabled();
      this.sites = client.trustedSites();
      const accounts = client.accounts();
      this.totalCount = accounts.length;
      this.scanCount = client.scanAccounts().length;
      this.standardCount = this.totalCount - this.scanCount;
      this.refreshClock(client.clockStatus());
      this.loading = false;
    } catch (error) {
      this.fatal = errorText(error as TotpError);
      this.loading = false;
    }
  }

  private refreshClock(status: ClockStatus): void {
    this.clockLabel = status.label;
    this.skewWarning = status.skewWarning;
    if (!status.known) {
      this.offsetLabel = '—';
      return;
    }
    const seconds = Math.round(status.offsetMs / 100) / 10;
    const sign = seconds > 0 ? '+' : '';
    this.offsetLabel = `${sign}${seconds} 秒`;
  }

  private toggleBiometric(on: boolean): void {
    const client = this.client;
    if (client === null) {
      return;
    }
    if (on && !this.biometricAvailable) {
      this.biometric = false;
      toast('设备未录入指纹或人脸，无法开启该保护');
      return;
    }
    const previous = this.biometric;
    this.biometric = on;
    client.setBiometricRequired(on).catch((error: Object) => {
      this.biometric = previous;
      toast(errorText(error as TotpError));
    });
  }

  private async enableReveal(): Promise<void> {
    const client = this.client;
    if (client === null) {
      return;
    }
    if (!BiometricGate.strongAvailable()) {
      toast('设备未设置锁屏密码或生物识别，无法开启');
      return;
    }
    try {
      await BiometricGate.authenticateStrong('验证身份以开启动态码显示');
      await client.setScanCodeRevealEnabled(true);
      this.revealScanCodes = true;
      toast('已开启：扫码型账户会直接显示动态码');
    } catch (error) {
      this.revealScanCodes = false;
      toast(errorText(error as TotpError));
    }
  }

  private disableReveal(): void {
    const client = this.client;
    if (client === null) {
      return;
    }
    // 先隐藏界面，再持久化；写入失败时恢复状态并提示。
    this.revealScanCodes = false;
    client.setScanCodeRevealEnabled(false).then(() => {
      toast('已关闭，动态码不再显示');
    }).catch((error: Object) => {
      this.revealScanCodes = true;
      toast(errorText(error as TotpError));
    });
  }

  private async calibrate(): Promise<void> {
    const client = this.client;
    if (client === null || this.calibrating) {
      return;
    }
    if (this.scanCount === 0) {
      toast('请先绑定至少一个增强型账户，才能从服务器校准时间');
      return;
    }
    this.calibrating = true;
    try {
      const status = await client.calibrateClock();
      this.refreshClock(status);
      toast(status.known ? '已完成时间校准' : '暂时无法获取服务器时间，请稍后重试');
    } catch (error) {
      toast('校准失败，请稍后重试');
    } finally {
      this.calibrating = false;
    }
  }

  private confirmClear(): void {
    if (this.client === null || this.totalCount === 0) {
      toast('本机没有可清除的账户');
      return;
    }
    AlertDialog.show({
      title: '清除本机全部数据',
      message: `将删除本机的 ${this.totalCount} 个账户（标准 ${this.standardCount} 个、增强型 ${this.scanCount} 个）、备注与设置。` +
        '增强型账户在服务器端的绑定不会被撤销；如需彻底解绑，请到对应站点操作。此操作不可撤销。',
      primaryButton: {
        value: '取消',
        action: () => {
        }
      },
      secondaryButton: {
        value: '确认清除',
        fontColor: '#C0392B',
        action: () => {
          this.doClear();
        }
      }
    });
  }

  private async doClear(): Promise<void> {
    const client = this.client;
    if (client === null || this.clearing) {
      return;
    }
    this.clearing = true;
    try {
      await client.clearAll();
      this.biometric = client.biometricRequired();
      this.revealScanCodes = client.scanCodeRevealEnabled();
      this.sites = client.trustedSites();
      this.totalCount = 0;
      this.scanCount = 0;
      this.standardCount = 0;
      this.refreshClock(client.clockStatus());
      toast('本机数据已清除');
    } catch (error) {
      toast(errorText(error as TotpError));
    } finally {
      this.clearing = false;
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
      Text('设置')
        .fontSize(17)
        .fontWeight(FontWeight.Medium)
        .fontColor('#16332A')
        .layoutWeight(1)
    }
    .width('100%')
    .padding({ left: 8, right: 16, top: 8, bottom: 8 })
  }

  @Builder
  private sectionTitle(text: string) {
    Text(text)
      .fontSize(12)
      .fontColor('#6B8077')
      .width('100%')
      .padding({ left: 4, top: 6 })
  }

  @Builder
  private labelRow(title: string, value: string, valueColor: string) {
    Row({ space: 12 }) {
      Text(title)
        .fontSize(13)
        .fontColor('#16332A')
        .layoutWeight(1)
      Text(value)
        .fontSize(12)
        .fontColor(valueColor)
        .textAlign(TextAlign.End)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .padding({ top: 4, bottom: 4 })
  }

  @Builder
  private securitySection() {
    Column({ space: 6 }) {
      Row({ space: 12 }) {
        Column({ space: 3 }) {
          Text('提交前验证身份')
            .fontSize(14)
            .fontColor('#16332A')
          Text(this.biometricAvailable ? '使用系统指纹或人脸识别' : '当前设备未录入可用的生物识别')
            .fontSize(11)
            .fontColor(this.biometricAvailable ? '#6B8077' : '#A0631C')
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: this.biometric })
          .selectedColor('#2E7D5B')
          .enabled(this.biometricAvailable)
          .onChange((on: boolean) => {
            this.toggleBiometric(on);
          })
      }
      .width('100%')
      Text('开启后，每次扫码提交动态码前都需要通过系统身份验证。关闭会降低本机被他人操作时的保护。')
        .fontSize(10)
        .fontColor('#8A9A93')
        .lineHeight(16)
        .width('100%')

      Divider().color('#EEF2F0').margin({ top: 4, bottom: 4 })

      Row({ space: 12 }) {
        Column({ space: 3 }) {
          Text('显示扫码型账户的动态码')
            .fontSize(14)
            .fontColor('#16332A')
          Text(this.revealScanCodes ? '已开启：六位码直接显示，旁人可见' : '默认关闭，扫码型账户不显示动态码')
            .fontSize(11)
            .fontColor(this.revealScanCodes ? '#A0631C' : '#6B8077')
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: this.revealScanCodes })
          .selectedColor('#C0392B')
          .onChange((on: boolean) => {
            if (on && !this.revealScanCodes) {
              this.revealDialog.open();
            } else if (!on && this.revealScanCodes) {
              this.disableReveal();
            }
          })
      }
      .width('100%')
      Text('开启后扫码型账户的六位码会直接显示并可复制，旁人可见，防钓鱼优势下降。' +
        '开启前需要通过本地身份验证并确认风险；关闭后立即隐藏并清空。')
        .fontSize(10)
        .fontColor('#8A9A93')
        .lineHeight(16)
        .width('100%')
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding(16)
    .backgroundColor(Color.White)
    .borderRadius(14)
  }

  @Builder
  private clockSection() {
    Column({ space: 8 }) {
      this.labelRow('设备时间偏移', this.offsetLabel, this.skewWarning ? '#A0631C' : '#16332A')
      Text(this.clockLabel)
        .fontSize(11)
        .fontColor(this.skewWarning ? '#A0631C' : '#6B8077')
        .width('100%')
      Button(this.calibrating ? '正在校准...' : '立即校准')
        .width('100%')
        .height(40)
        .backgroundColor(this.scanCount > 0 ? '#E3EEE8' : '#F0F3F1')
        .fontColor(this.scanCount > 0 ? '#2E7D5B' : '#9AAAA3')
        .enabled(!this.calibrating)
        .onClick(() => {
          this.calibrate();
        })
      Text(this.scanCount > 0
        ? '通过已绑定站点的健康检查接口读取服务器时间，不提交任何账户数据。动态码的时间窗口始终以服务器为准。'
        : '绑定增强型账户后，可从对应站点读取服务器时间进行校准。标准账户仅使用设备本地时间。')
        .fontSize(10)
        .fontColor('#8A9A93')
        .lineHeight(16)
        .width('100%')
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding(16)
    .backgroundColor(Color.White)
    .borderRadius(14)
  }

  @Builder
  private trustSection() {
    Column({ space: 8 }) {
      Text('已绑定站点（按注册域名归并）')
        .fontSize(13)
        .fontColor('#16332A')
        .width('100%')
      if (this.sites.length === 0) {
        Text('还没有绑定任何站点。绑定后会固定该站点的注册域名与提交路径。')
          .fontSize(11)
          .fontColor('#6B8077')
          .lineHeight(17)
          .width('100%')
      } else {
        ForEach(this.sites, (site: TrustedSite) => {
          Column({ space: 2 }) {
            Row({ space: 8 }) {
              Text(site.domain)
                .fontSize(13)
                .fontWeight(FontWeight.Medium)
                .fontColor('#16332A')
                .layoutWeight(1)
              Text(`${site.accountCount} 个账户`)
                .fontSize(11)
                .fontColor('#6B8077')
            }
            .width('100%')
            if (site.firstSeenAtMs > 0) {
              Text(`首次绑定于 ${new Date(site.firstSeenAtMs).toLocaleString()}`)
                .fontSize(10)
                .fontColor('#8A9A93')
                .width('100%')
            }
          }
          .alignItems(HorizontalAlign.Start)
          .width('100%')
          .padding(10)
          .backgroundColor('#F3F6F5')
          .borderRadius(8)
        }, (site: TrustedSite) => site.domain)
      }
      Text('登录二维码只用注册域名与提交路径前缀定位账户：域名相同、路径在钉住前缀之内才会提交。' +
        '相似域名只提示，不拦截。')
        .fontSize(10)
        .fontColor('#8A9A93')
        .lineHeight(16)
        .width('100%')
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding(16)
    .backgroundColor(Color.White)
    .borderRadius(14)
  }

  @Builder
  private dataSection() {
    Column({ space: 10 }) {
      this.labelRow('标准 TOTP 账户', `${this.standardCount} 个`, '#16332A')
      this.labelRow('增强型扫码账户', `${this.scanCount} 个`, '#16332A')
      Button(this.clearing ? '正在清除...' : '清除本机全部数据')
        .width('100%')
        .height(42)
        .backgroundColor('#FBEDEC')
        .fontColor('#C0392B')
        .enabled(!this.clearing && this.totalCount > 0)
        .onClick(() => {
          this.confirmClear();
        })
      Text('删除后本机将不再保存任何密钥。增强型账户需要重新扫码绑定才能再次使用；标准账户需要重新导入或手动录入。')
        .fontSize(10)
        .fontColor('#8A9A93')
        .lineHeight(16)
        .width('100%')
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding(16)
    .backgroundColor(Color.White)
    .borderRadius(14)
  }

  @Builder
  private aboutSection() {
    Column({ space: 8 }) {
      this.labelRow('应用', '扫码认证器 1.0.0', '#16332A')
      this.labelRow('协议', 'TOTPSCAN/v1 · RFC 6238', '#16332A')
      Text('已知局限')
        .fontSize(12)
        .fontWeight(FontWeight.Medium)
        .fontColor('#16332A')
        .width('100%')
        .padding({ top: 4 })
      Text('· 扫码型账户默认不显示、不复制动态码，离线时无法使用；开启显示开关后防钓鱼优势下降。\n' +
        '· 导出的 otpauth 二维码包含账户密钥，只在本机屏幕短暂显示，请勿截屏或转交他人。\n' +
        '· 标准账户没有地址比对防护，动态码可能被钓鱼页面诱导输入。\n' +
        '· 二维码展示页面本身不可信；本应用只能保证不把动态码发往陌生地址。\n' +
        '· 提交失败时服务端统一返回相同错误，本应用无法区分具体原因。')
        .fontSize(11)
        .fontColor('#5F736B')
        .lineHeight(19)
        .width('100%')
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding(16)
    .backgroundColor(Color.White)
    .borderRadius(14)
  }

  build() {
    Column() {
      this.header()
      if (this.loading) {
        Column({ space: 10 }) {
          LoadingProgress().width(36).height(36).color('#2E7D5B')
          Text('正在读取设置...').fontSize(12).fontColor('#6B8077')
        }
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else if (this.fatal.length > 0) {
        Column({ space: 12 }) {
          Text('无法读取本地数据').fontSize(17).fontColor('#8C2F2F')
          Text(this.fatal).fontSize(12).fontColor('#6B4B4B').textAlign(TextAlign.Center)
          Button('重试')
            .backgroundColor('#2E7D5B')
            .onClick(() => {
              this.load();
            })
        }
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .padding(24)
      } else {
        Scroll() {
          Column({ space: 10 }) {
            this.sectionTitle('安全')
            this.securitySection()

            this.sectionTitle('时间')
            this.clockSection()

            this.sectionTitle('已信任站点')
            this.trustSection()

            this.sectionTitle('数据')
            this.dataSection()

            this.sectionTitle('关于')
            this.aboutSection()

            Text('所有密钥保存在系统安全存储中；日志不记录密钥、一次性扫码令牌或动态码。')
              .fontSize(10)
              .fontColor('#8A9A93')
              .textAlign(TextAlign.Center)
              .width('100%')
              .padding({ top: 8, bottom: 26 })
          }
          .width('100%')
          .padding({ left: 16, right: 16 })
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
