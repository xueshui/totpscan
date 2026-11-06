import { router } from '@kit.ArkUI';
import {
  LoginCandidate,
  LoginPreview,
  LoginResult,
  TotpError,
  TotpErrorCode
} from 'totpscan';
import { QrScanner } from '../components/QrScanner';
import { AppContext } from '../common/AppContext';
import { errorText, hostOf } from '../common/Ui';

@Entry
@Component
struct Login {
  /** scan | parsing | preview | submitting | success | zero | expired | error */
  @State private stage: string = 'scan';
  @State private visible: boolean = true;
  @State private preview: LoginPreview | null = null;
  @State private selectedId: string = '';
  @State private errorMessage: string = '';
  @State private errorCode: string = '';
  @State private resultMessage: string = '';
  @State private remaining: number = 0;
  @State private verifying: boolean = false;
  @State private busy: boolean = false;
  private expiryTimer: number = -1;

  aboutToAppear(): void {
    this.visible = true;
  }

  onPageShow(): void {
    this.visible = true;
  }

  onPageHide(): void {
    this.visible = false;
    this.stopExpiryTimer();
  }

  aboutToDisappear(): void {
    this.stopExpiryTimer();
    this.discardPending();
  }

  private discardPending(): void {
    const preview = this.preview;
    if (preview === null) {
      return;
    }
    try {
      AppContext.getClient().discardLogin(preview.loginId);
    } catch (error) {
      // 已提交或已过期的登录会话无需再次清理。
    }
    this.preview = null;
  }

  private startExpiryTimer(): void {
    this.stopExpiryTimer();
    this.expiryTimer = setInterval(() => {
      const preview = this.preview;
      if (preview === null) {
        return;
      }
      const left = preview.expiresAt - Math.floor(Date.now() / 1000);
      this.remaining = left > 0 ? left : 0;
      if (left <= 0) {
        this.stopExpiryTimer();
      }
    }, 1000);
  }

  private stopExpiryTimer(): void {
    if (this.expiryTimer >= 0) {
      clearInterval(this.expiryTimer);
      this.expiryTimer = -1;
    }
  }

  private resetToScan(): void {
    this.stopExpiryTimer();
    this.discardPending();
    this.selectedId = '';
    this.errorMessage = '';
    this.errorCode = '';
    this.resultMessage = '';
    this.remaining = 0;
    this.busy = false;
    this.stage = 'scan';
  }

  private async handleQr(text: string): Promise<void> {
    if (this.busy) {
      return;
    }
    this.busy = true;
    this.stage = 'parsing';
    try {
      const client = await AppContext.ready();
      const preview = await client.prepareLogin(text);
      this.preview = preview;
      this.selectedId = preview.selectedLocalId;
      this.remaining = Math.max(0, preview.expiresAt - Math.floor(Date.now() / 1000));
      this.stage = 'preview';
      this.startExpiryTimer();
    } catch (error) {
      const known = error as TotpError;
      this.errorCode = known.code;
      this.errorMessage = errorText(known);
      this.stage = known.code === TotpErrorCode.ADDRESS_MISMATCH ? 'zero' : 'error';
    } finally {
      this.busy = false;
    }
  }

  private selectCandidate(localId: string): void {
    this.selectedId = localId;
  }

  private async submit(): Promise<void> {
    const preview = this.preview;
    if (this.busy || preview === null || this.selectedId.length === 0) {
      return;
    }
    if (this.remaining <= 0) {
      this.stage = 'expired';
      return;
    }
    this.busy = true;
    this.stage = 'submitting';
    this.stopExpiryTimer();
    try {
      const client = await AppContext.ready();
      this.verifying = client.biometricRequired();
      if (preview.candidates.length > 1) {
        client.selectLoginCandidate(preview.loginId, this.selectedId);
      }
      const result: LoginResult = await client.authorizeLogin(preview.loginId, this.selectedId);
      if (result.success) {
        this.resultMessage = result.message;
        this.stage = 'success';
      } else {
        this.errorCode = '';
        this.errorMessage = result.message;
        this.stage = 'error';
      }
    } catch (error) {
      const known = error as TotpError;
      this.errorCode = known.code;
      this.errorMessage = errorText(known);
      this.stage = known.code === TotpErrorCode.LOGIN_EXPIRED ? 'expired' : 'error';
    } finally {
      this.busy = false;
    }
  }

  private candidateName(item: LoginCandidate): string {
    return item.displayName.length > 0 ? item.displayName : item.issuer;
  }

  private candidates(): LoginCandidate[] {
    return this.preview === null ? [] : this.preview.candidates;
  }

  private candidateCount(): number {
    return this.preview === null ? 0 : this.preview.candidates.length;
  }

  private firstSubmitHost(): string {
    const list = this.candidates();
    return list.length > 0 ? hostOf(list[0].submitUrl) : '';
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
  private candidateCard(item: LoginCandidate) {
    Row({ space: 12 }) {
      Radio({ value: item.localId, group: 'loginCandidates' })
        .checked(this.selectedId === item.localId)
        .onChange((checked: boolean) => {
          if (checked) {
            this.selectCandidate(item.localId);
          }
        })
      Column({ space: 4 }) {
        Text(this.candidateName(item))
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor('#16332A')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(item.issuer.length > 0 ? `${item.issuer} · ${item.account}` : item.account)
          .fontSize(12)
          .fontColor('#5F736B')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(hostOf(item.submitUrl))
          .fontSize(11)
          .fontColor('#7A8C84')
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
    }
    .width('100%')
    .padding(14)
    .backgroundColor(this.selectedId === item.localId ? '#EDF6F1' : Color.White)
    .borderRadius(12)
    .border({
      width: 1,
      color: this.selectedId === item.localId ? '#2E7D5B' : '#E2E8E5'
    })
    .onClick(() => {
      this.selectCandidate(item.localId);
    })
  }

  @Builder
  private scanStage() {
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
        Text('扫描登录二维码')
          .fontSize(17)
          .fontWeight(FontWeight.Medium)
          .fontColor('#FFFFFF')
          .layoutWeight(1)
      }
      .width('100%')
      .padding({ left: 8, right: 16, top: 8, bottom: 4 })

      if (this.visible) {
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

  @Builder
  private parsingStage() {
    Column({ space: 16 }) {
      LoadingProgress().width(44).height(44).color('#2E7D5B')
      Text('正在校验二维码...')
        .fontSize(14)
        .fontColor('#4A6B5E')
      Text('候选账户完全在本地匹配，未发送任何请求')
        .fontSize(11)
        .fontColor('#8A9A93')
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  private previewStage() {
    Column() {
      this.header('确认登录')
      Scroll() {
        Column({ space: 14 }) {
          if (this.preview !== null) {
            Column({ space: 8 }) {
              Text('即将向以下站点提交')
                .fontSize(12)
                .fontColor('#6B8077')
              Text(this.firstSubmitHost())
                .fontSize(18)
                .fontWeight(FontWeight.Bold)
                .fontColor('#16332A')
              Text('提交目标取自本地固化的完整地址；二维码只提供域名与会话标识。')
                .fontSize(11)
                .fontColor('#7A8C84')
                .textAlign(TextAlign.Center)
            }
            .width('100%')
            .padding(16)
            .backgroundColor(Color.White)
            .borderRadius(14)

            Row() {
              Text(this.remaining > 0 ? `二维码 ${this.remaining} 秒后失效` : '二维码已失效')
                .fontSize(12)
                .fontColor(this.remaining > 10 ? '#6B8077' : '#A0631C')
              Blank()
              Text('动态码不会显示')
                .fontSize(11)
                .fontColor('#8A9A93')
            }
            .width('100%')
            .padding({ left: 4, right: 4 })

            if (this.candidateCount() === 1) {
              Column({ space: 4 }) {
                Text('使用账户')
                  .fontSize(12)
                  .fontColor('#6B8077')
                  .width('100%')
                this.candidateCard(this.candidates()[0])
              }
              .alignItems(HorizontalAlign.Start)
              .width('100%')
            } else {
              Text(`该站点下有 ${this.candidateCount()} 个账户，请选择本次使用的账户`)
                .fontSize(13)
                .fontColor('#4A6B5E')
                .width('100%')
              ForEach(this.candidates(), (item: LoginCandidate) => {
                this.candidateCard(item)
              }, (item: LoginCandidate) => item.localId)
            }

            if (this.hasLooseCandidate()) {
              Text('注意：所选账户固化在站点根地址，匹配范围较宽，请确认站点可信。')
                .fontSize(11)
                .fontColor('#A0631C')
                .width('100%')
                .padding(12)
                .backgroundColor('#FBF1E2')
                .borderRadius(10)
            }

            Button('验证身份并提交')
              .width('100%')
              .height(46)
              .backgroundColor(this.selectedId.length > 0 && this.remaining > 0 ? '#2E7D5B' : '#B9C9C2')
              .enabled(this.selectedId.length > 0 && this.remaining > 0)
              .onClick(() => {
                this.submit();
              })
            Button('取消')
              .width('100%')
              .backgroundColor(Color.Transparent)
              .fontColor('#5F736B')
              .onClick(() => {
                router.back();
              })
          }
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

  private hasLooseCandidate(): boolean {
    if (this.preview === null) {
      return false;
    }
    for (let i = 0; i < this.preview.candidates.length; i += 1) {
      if (this.preview.candidates[i].looseSource) {
        return true;
      }
    }
    return false;
  }

  @Builder
  private submittingStage() {
    Column({ space: 16 }) {
      LoadingProgress().width(44).height(44).color('#2E7D5B')
      Text(this.verifying ? '请完成指纹或人脸验证' : '正在安全提交')
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor('#16332A')
      Text(this.verifying
        ? '验证通过后会在本机计算一次性动态码，并提交到已固化的地址。'
        : '正在本机计算一次性动态码，并提交到已固化的地址。')
        .fontSize(12)
        .fontColor('#6B8077')
        .textAlign(TextAlign.Center)
        .padding({ left: 32, right: 32 })
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  private successStage() {
    Column() {
      this.header('登录成功')
      Column({ space: 14 }) {
        Text('✓')
          .fontSize(44)
          .fontWeight(FontWeight.Bold)
          .fontColor('#2E7D5B')
        Text('登录成功')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor('#16332A')
        Text(this.resultMessage.length > 0 ? this.resultMessage : '网页将自动完成认证。')
          .fontSize(13)
          .fontColor('#5F736B')
          .textAlign(TextAlign.Center)
        Text('本次动态码已被使用，不可重复提交。')
          .fontSize(11)
          .fontColor('#8A9A93')
          .textAlign(TextAlign.Center)
        Button('完成')
          .width('100%')
          .height(44)
          .backgroundColor('#2E7D5B')
          .margin({ top: 10 })
          .onClick(() => {
            router.back();
          })
      }
      .width('100%')
      .padding(28)
      .backgroundColor(Color.White)
      .borderRadius(16)
      .margin({ left: 16, right: 16 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F5F7F6')
  }

  @Builder
  private zeroStage() {
    Column() {
      this.header('扫码登录')
      Column({ space: 14 }) {
        Text('未找到匹配的站点')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor('#8C2F2F')
        Text('本机没有任何已确认账户的注册域名与该二维码一致。')
          .fontSize(13)
          .fontColor('#5F736B')
          .textAlign(TextAlign.Center)
        Text('已在本地终止：没有计算动态码，也没有发送任何网络请求。')
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
            this.resetToScan();
          })
        Button('返回')
          .width('100%')
          .backgroundColor(Color.Transparent)
          .fontColor('#5F736B')
          .onClick(() => {
            router.back();
          })
      }
      .width('100%')
      .padding(24)
      .backgroundColor(Color.White)
      .borderRadius(16)
      .margin({ left: 16, right: 16 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F5F7F6')
  }

  @Builder
  private expiredStage() {
    Column() {
      this.header('扫码登录')
      Column({ space: 14 }) {
        Text('二维码已过期')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor('#16332A')
        Text('登录二维码有效期不超过 60 秒。请在网页上重新发起登录，然后再次扫码。')
          .fontSize(13)
          .fontColor('#5F736B')
          .textAlign(TextAlign.Center)
        Button('重新扫描')
          .width('100%')
          .backgroundColor('#2E7D5B')
          .onClick(() => {
            this.resetToScan();
          })
        Button('返回')
          .width('100%')
          .backgroundColor(Color.Transparent)
          .fontColor('#5F736B')
          .onClick(() => {
            router.back();
          })
      }
      .width('100%')
      .padding(24)
      .backgroundColor(Color.White)
      .borderRadius(16)
      .margin({ left: 16, right: 16 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F5F7F6')
  }

  @Builder
  private errorStage() {
    Column() {
      this.header('扫码登录')
      Column({ space: 14 }) {
        Text('未能完成登录')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor('#16332A')
        Text(this.errorMessage)
          .fontSize(13)
          .fontColor('#5F736B')
          .textAlign(TextAlign.Center)
        if (this.errorCode === TotpErrorCode.BIOMETRIC_UNAVAILABLE) {
          Text('请先在系统设置中录入指纹或人脸，再重试。')
            .fontSize(12)
            .fontColor('#A0631C')
            .textAlign(TextAlign.Center)
        }
        Button('重新扫描')
          .width('100%')
          .backgroundColor('#2E7D5B')
          .onClick(() => {
            this.resetToScan();
          })
        Button('返回')
          .width('100%')
          .backgroundColor(Color.Transparent)
          .fontColor('#5F736B')
          .onClick(() => {
            router.back();
          })
      }
      .width('100%')
      .padding(24)
      .backgroundColor(Color.White)
      .borderRadius(16)
      .margin({ left: 16, right: 16 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F5F7F6')
  }

  build() {
    Stack() {
      if (this.stage === 'scan') {
        this.scanStage()
      } else if (this.stage === 'parsing') {
        Column() {
          this.header('扫码登录')
          this.parsingStage()
        }
        .width('100%')
        .height('100%')
        .backgroundColor('#F5F7F6')
      } else if (this.stage === 'preview') {
        this.previewStage()
      } else if (this.stage === 'submitting') {
        Column() {
          this.header('正在提交')
          this.submittingStage()
        }
        .width('100%')
        .height('100%')
        .backgroundColor('#F5F7F6')
      } else if (this.stage === 'success') {
        this.successStage()
      } else if (this.stage === 'zero') {
        this.zeroStage()
      } else if (this.stage === 'expired') {
        this.expiredStage()
      } else {
        this.errorStage()
      }
    }
    .width('100%')
    .height('100%')
  }
}
