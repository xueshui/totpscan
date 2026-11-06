import { abilityAccessCtrl, common, Permissions } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { customScan, scanBarcode, scanCore } from '@kit.ScanKit';
import { toast } from '../common/Ui';

const CAMERA_PERMISSION: Permissions = 'ohos.permission.CAMERA';

/**
 * 相机扫码组件。
 *
 * 优先使用 Scan Kit 自定义界面扫码（需要 CAMERA 运行时权限），
 * 权限被拒或相机不可用时提供“系统扫码”兜底（系统界面无需应用相机权限）。
 * 只回传二维码原始文本，不解析、不记录。
 */
@Component
export struct QrScanner {
  onResult: (text: string) => void = (text: string) => {
  };
  /** init | requesting | scanning | denied | unavailable */
  @State private status: string = 'init';
  @State private message: string = '';
  private options: customScan.ScanOptions = {
    scanTypes: [scanCore.ScanType.QR_CODE],
    enableMultiMode: false
  };
  private controller: XComponentController = new XComponentController();
  private started: boolean = false;
  private emitting: boolean = false;

  aboutToAppear(): void {
    this.requestCamera();
  }

  aboutToDisappear(): void {
    this.stopScan();
  }

  private async requestCamera(): Promise<void> {
    this.status = 'requesting';
    this.message = '';
    try {
      const context = getContext(this) as common.UIAbilityContext;
      const manager = abilityAccessCtrl.createAtManager();
      const result = await manager.requestPermissionsFromUser(context, [CAMERA_PERMISSION]);
      if (result.authResults.length > 0 && result.authResults[0] === 0) {
        this.status = 'scanning';
      } else {
        this.status = 'denied';
      }
    } catch (error) {
      this.status = 'denied';
    }
  }

  private startScan(): void {
    if (this.started) {
      return;
    }
    try {
      const surfaceId = this.controller.getXComponentSurfaceId();
      const viewControl: customScan.ViewControl = {
        surfaceId: surfaceId,
        width: 600,
        height: 600
      };
      customScan.init(this.options);
      customScan.start(viewControl, this.options, (error: BusinessError, result: Array<scanBarcode.ScanResult>) => {
        if (error !== null && error !== undefined && error.code !== 0) {
          this.status = 'unavailable';
          this.message = '相机预览启动失败';
          return;
        }
        if (result !== null && result !== undefined && result.length > 0) {
          this.emit(result[0].originalValue);
        }
      });
      this.started = true;
    } catch (error) {
      this.status = 'unavailable';
      this.message = '当前设备无法启动相机扫码';
    }
  }

  private stopScan(): void {
    if (!this.started) {
      return;
    }
    this.started = false;
    try {
      customScan.stop();
      customScan.release();
    } catch (error) {
      // 停止失败不影响页面退出。
    }
  }

  private emit(text: string): void {
    if (this.emitting || text.length === 0) {
      return;
    }
    this.emitting = true;
    this.stopScan();
    this.onResult(text);
  }

  private async systemScan(): Promise<void> {
    this.stopScan();
    try {
      const context = getContext(this) as common.UIAbilityContext;
      const options: scanBarcode.ScanOptions = {
        scanTypes: [scanCore.ScanType.QR_CODE],
        enableMultiMode: false,
        enableAlbum: true
      };
      const result = await scanBarcode.startScanForResult(context, options);
      this.emit(result.originalValue);
    } catch (error) {
      toast('未获取到二维码，请重试');
    }
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      if (this.status === 'scanning') {
        XComponent({
          id: 'totpScanSurface',
          type: XComponentType.SURFACE,
          controller: this.controller
        })
          .width('100%')
          .height('100%')
          .onLoad(() => {
            this.startScan();
          })
      } else {
        Column({ space: 10 }) {
          if (this.status === 'requesting' || this.status === 'init') {
            LoadingProgress().width(40).height(40).color('#7CE0B0')
            Text('正在准备相机...')
              .fontSize(13)
              .fontColor('#C8D8D1')
          } else if (this.status === 'denied') {
            Text('相机权限被拒绝')
              .fontSize(17)
              .fontWeight(FontWeight.Medium)
              .fontColor('#FFFFFF')
            Text('扫码需要相机权限。你可以在系统设置中开启，或直接使用系统扫码界面（无需本应用相机权限）。')
              .fontSize(12)
              .fontColor('#B9C9C2')
              .textAlign(TextAlign.Center)
              .padding({ left: 40, right: 40 })
              .lineHeight(18)
            Button('重新授权')
              .backgroundColor('#2E7D5B')
              .onClick(() => {
                this.requestCamera();
              })
            Button('使用系统扫码')
              .backgroundColor('#33564A')
              .onClick(() => {
                this.systemScan();
              })
          } else {
            Text('相机不可用')
              .fontSize(17)
              .fontWeight(FontWeight.Medium)
              .fontColor('#FFFFFF')
            Text(this.message.length > 0 ? this.message : '当前设备无法使用相机扫码，可改用系统扫码界面。')
              .fontSize(12)
              .fontColor('#B9C9C2')
              .textAlign(TextAlign.Center)
              .padding({ left: 40, right: 40 })
            Button('使用系统扫码')
              .backgroundColor('#2E7D5B')
              .onClick(() => {
                this.systemScan();
              })
          }
        }
        .justifyContent(FlexAlign.Center)
      }

      if (this.status === 'scanning') {
        Column() {
          Column()
            .width(240)
            .height(240)
            .border({ width: 2, color: '#7CE0B0', radius: 18 })
          Text('将二维码放入框内')
            .fontSize(13)
            .fontColor('#E6F2EC')
            .margin({ top: 18 })
          Button('无法扫码？使用系统扫码')
            .fontSize(12)
            .backgroundColor('#33FFFFFF')
            .fontColor('#FFFFFF')
            .margin({ top: 12 })
            .onClick(() => {
              this.systemScan();
            })
        }
        .justifyContent(FlexAlign.Center)
        .width('100%')
        .height('100%')
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#0B1915')
  }
}
