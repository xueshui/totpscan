import { ClockStatus } from '../model/Models';
import { VaultSettings } from '../store/Vault';

const MAX_TRUSTED_OFFSET_MS = 3600 * 1000;

/**
 * 设备时钟校准。
 *
 * 只要向已固化服务器发过请求，就读取响应的 Date 头作为服务器时间，
 * 计算并持久化偏移（钳制在 ±1 小时，异常值忽略）。
 * 动态码按校准后的时间计算，同时把偏差展示给用户。
 */
export class ClockService {
  private offsetMs = 0;
  private known = false;
  private syncedAtMs = 0;

  load(settings: VaultSettings): void {
    this.offsetMs = settings.clockOffsetMs;
    this.known = settings.clockKnown;
    this.syncedAtMs = settings.clockSyncedAtMs;
  }

  nowMs(): number {
    return Date.now() + (this.known ? this.offsetMs : 0);
  }

  nowSeconds(): number {
    return Math.floor(this.nowMs() / 1000);
  }

  /** 返回是否接受本次服务器时间。 */
  updateFromServer(serverTimeMs: number): boolean {
    if (!Number.isFinite(serverTimeMs) || serverTimeMs <= 0) {
      return false;
    }
    const offset = serverTimeMs - Date.now();
    if (Math.abs(offset) > MAX_TRUSTED_OFFSET_MS) {
      return false;
    }
    this.offsetMs = offset;
    this.known = true;
    this.syncedAtMs = Date.now();
    return true;
  }

  toSettings(settings: VaultSettings): VaultSettings {
    return {
      biometricRequired: settings.biometricRequired,
      revealScanCodes: settings.revealScanCodes,
      clockOffsetMs: this.offsetMs,
      clockSyncedAtMs: this.syncedAtMs,
      clockKnown: this.known
    };
  }

  status(warnSeconds: number): ClockStatus {
    if (!this.known) {
      return {
        known: false,
        offsetMs: 0,
        syncedAtMs: 0,
        skewWarning: false,
        label: '尚未与服务器校准时间'
      };
    }
    const offsetSeconds = Math.round(this.offsetMs / 1000);
    const warning = Math.abs(this.offsetMs) >= warnSeconds * 1000;
    return {
      known: true,
      offsetMs: this.offsetMs,
      syncedAtMs: this.syncedAtMs,
      skewWarning: warning,
      label: warning ? `设备时间与服务器相差 ${offsetSeconds} 秒` : `时间已校准（偏差 ${offsetSeconds} 秒）`
    };
  }
}
