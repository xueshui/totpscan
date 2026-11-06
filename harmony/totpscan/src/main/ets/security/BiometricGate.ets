import { userAuth } from '@kit.UserAuthenticationKit';
import { randomBytes } from '../core/Bytes';
import { TotpError, TotpErrorCode } from '../core/TotpError';

/**
 * 本地身份认证门禁。
 *
 * - `authenticate`：提交动态码前的门禁（指纹/人脸，ATL3）；
 * - `authenticateStrong`：导出密钥、开启动态码显示等高风险操作前的强制认证，
 *   优先生物识别，设备未录入生物识别时回退到锁屏密码（PIN）。
 * - 设备既无生物识别也无锁屏密码时 fail-closed。
 * - 认证 challenge 为 32 字节 CSPRNG，不复用、不落盘。
 */
export class BiometricGate {
  static available(): boolean {
    try {
      userAuth.getAvailableStatus(userAuth.UserAuthType.FINGERPRINT, userAuth.AuthTrustLevel.ATL3);
      return true;
    } catch (error) {
      // 指纹不可用时继续探测人脸。
    }
    try {
      userAuth.getAvailableStatus(userAuth.UserAuthType.FACE, userAuth.AuthTrustLevel.ATL3);
      return true;
    } catch (error) {
      return false;
    }
  }

  /** 是否设置了可用的锁屏密码。PIN 只支持 ATL4（部分设备也提供 ATL3）。 */
  static pinAvailable(): boolean {
    try {
      userAuth.getAvailableStatus(userAuth.UserAuthType.PIN, userAuth.AuthTrustLevel.ATL3);
      return true;
    } catch (error) {
      // 继续探测 ATL4。
    }
    try {
      userAuth.getAvailableStatus(userAuth.UserAuthType.PIN, userAuth.AuthTrustLevel.ATL4);
      return true;
    } catch (error) {
      return false;
    }
  }

  /** 强认证是否可用（生物识别或锁屏密码任一）。 */
  static strongAvailable(): boolean {
    return BiometricGate.available() || BiometricGate.pinAvailable();
  }

  static authenticate(reason: string): Promise<void> {
    if (!BiometricGate.available()) {
      return Promise.reject(new TotpError(TotpErrorCode.BIOMETRIC_UNAVAILABLE, 'BIOMETRIC_NOT_ENROLLED'));
    }
    return BiometricGate.run(
      reason,
      [userAuth.UserAuthType.FINGERPRINT, userAuth.UserAuthType.FACE],
      userAuth.AuthTrustLevel.ATL3
    );
  }

  /**
   * 强制本地认证（生物识别 / 锁屏密码）。失败时抛出 BIOMETRIC_UNAVAILABLE / BIOMETRIC_FAILED，
   * 调用方必须保持敏感内容不渲染、不落盘。
   */
  static authenticateStrong(reason: string): Promise<void> {
    if (BiometricGate.available()) {
      return BiometricGate.run(
        reason,
        [userAuth.UserAuthType.FINGERPRINT, userAuth.UserAuthType.FACE],
        userAuth.AuthTrustLevel.ATL3
      );
    }
    if (BiometricGate.pinAvailable()) {
      return BiometricGate.run(
        reason,
        [userAuth.UserAuthType.PIN],
        BiometricGate.pinTrustLevel()
      );
    }
    return Promise.reject(new TotpError(
      TotpErrorCode.BIOMETRIC_UNAVAILABLE,
      'STRONG_AUTH_NOT_ENROLLED',
      '设备未设置锁屏密码或生物识别，无法继续'
    ));
  }

  private static pinTrustLevel(): userAuth.AuthTrustLevel {
    try {
      userAuth.getAvailableStatus(userAuth.UserAuthType.PIN, userAuth.AuthTrustLevel.ATL3);
      return userAuth.AuthTrustLevel.ATL3;
    } catch (error) {
      return userAuth.AuthTrustLevel.ATL4;
    }
  }

  private static run(
    reason: string,
    authType: userAuth.UserAuthType[],
    trustLevel: userAuth.AuthTrustLevel
  ): Promise<void> {
    return new Promise<void>((resolve, reject) => {
      const authParam: userAuth.AuthParam = {
        challenge: randomBytes(32),
        authType: authType,
        authTrustLevel: trustLevel
      };
      const widgetParam: userAuth.WidgetParam = {
        title: reason
      };
      let instance: userAuth.UserAuthInstance;
      try {
        instance = userAuth.getUserAuthInstance(authParam, widgetParam);
      } catch (error) {
        reject(new TotpError(TotpErrorCode.BIOMETRIC_UNAVAILABLE, 'BIOMETRIC_INSTANCE_UNAVAILABLE'));
        return;
      }
      instance.on('result', {
        onResult: (result: userAuth.UserAuthResult) => {
          if (result.result === userAuth.UserAuthResultCode.SUCCESS) {
            resolve();
          } else {
            reject(new TotpError(TotpErrorCode.BIOMETRIC_FAILED, 'BIOMETRIC_NOT_PASSED'));
          }
        }
      });
      try {
        instance.start();
      } catch (error) {
        reject(new TotpError(TotpErrorCode.BIOMETRIC_FAILED, 'BIOMETRIC_START_FAILED'));
      }
    });
  }
}
