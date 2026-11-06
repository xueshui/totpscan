/** 稳定错误码：宿主 App 可据此做分支，不应解析 message。 */
export enum TotpErrorCode {
  INVALID_ARGUMENT = 'INVALID_ARGUMENT',
  INVALID_QR = 'INVALID_QR',
  UNSUPPORTED_VERSION = 'UNSUPPORTED_VERSION',
  QR_EXPIRED = 'QR_EXPIRED',
  INSECURE_ADDRESS = 'INSECURE_ADDRESS',
  ADDRESS_MISMATCH = 'ADDRESS_MISMATCH',
  ACCOUNT_NOT_FOUND = 'ACCOUNT_NOT_FOUND',
  NOT_SCAN_ACCOUNT = 'NOT_SCAN_ACCOUNT',
  NOT_STANDARD_ACCOUNT = 'NOT_STANDARD_ACCOUNT',
  NOT_BOUND = 'NOT_BOUND',
  SCAN_CODE_HIDDEN = 'SCAN_CODE_HIDDEN',
  DUPLICATE_ACCOUNT = 'DUPLICATE_ACCOUNT',
  SECURE_STORAGE_ERROR = 'SECURE_STORAGE_ERROR',
  BIOMETRIC_UNAVAILABLE = 'BIOMETRIC_UNAVAILABLE',
  BIOMETRIC_FAILED = 'BIOMETRIC_FAILED',
  LOGIN_EXPIRED = 'LOGIN_EXPIRED',
  NETWORK_ERROR = 'NETWORK_ERROR',
  REMOTE_REJECTED = 'REMOTE_REJECTED',
  RATE_LIMITED = 'RATE_LIMITED',
  INTERNAL = 'INTERNAL'
}

/**
 * SDK 统一异常。
 *
 * 约束：message 只用于开发排查，绝不包含密钥、token、动态码；
 * 面向用户的文案放在 userMessage。
 */
export class TotpError extends Error {
  readonly code: TotpErrorCode;
  readonly userMessage: string;

  constructor(code: TotpErrorCode, message: string, userMessage?: string) {
    super(message);
    this.code = code;
    this.userMessage = userMessage === undefined ? TotpError.defaultUserMessage(code) : userMessage;
    this.name = 'TotpError';
  }

  static defaultUserMessage(code: TotpErrorCode): string {
    switch (code) {
      case TotpErrorCode.INVALID_QR:
        return '二维码内容无效，请确认后重试';
      case TotpErrorCode.UNSUPPORTED_VERSION:
        return '二维码版本不受支持，请升级应用';
      case TotpErrorCode.QR_EXPIRED:
        return '二维码已过期，请重新获取';
      case TotpErrorCode.INSECURE_ADDRESS:
        return '二维码中的服务器地址不安全，已拒绝';
      case TotpErrorCode.ADDRESS_MISMATCH:
        return '该二维码不属于已绑定的服务器';
      case TotpErrorCode.ACCOUNT_NOT_FOUND:
        return '账户不存在';
      case TotpErrorCode.NOT_SCAN_ACCOUNT:
        return '该账户不是扫码绑定账户';
      case TotpErrorCode.NOT_STANDARD_ACCOUNT:
        return '增强型账户不显示动态码，请使用扫码提交';
      case TotpErrorCode.NOT_BOUND:
        return '尚未绑定任何账户';
      case TotpErrorCode.SCAN_CODE_HIDDEN:
        return '未开启显示扫码型账户的动态码';
      case TotpErrorCode.DUPLICATE_ACCOUNT:
        return '账户已存在';
      case TotpErrorCode.SECURE_STORAGE_ERROR:
        return '安全存储不可用，无法保存或读取密钥';
      case TotpErrorCode.BIOMETRIC_UNAVAILABLE:
        return '设备未设置可用的指纹或人脸识别';
      case TotpErrorCode.BIOMETRIC_FAILED:
        return '身份验证未通过';
      case TotpErrorCode.LOGIN_EXPIRED:
        return '登录二维码已过期，请在网页重新发起登录';
      case TotpErrorCode.NETWORK_ERROR:
        return '网络连接失败，请检查网络后重试';
      case TotpErrorCode.REMOTE_REJECTED:
        return '认证失败，请重新发起登录';
      case TotpErrorCode.RATE_LIMITED:
        return '请求过于频繁，请稍后再试';
      case TotpErrorCode.INTERNAL:
        return '操作失败，请稍后重试';
      default:
        return '操作失败，请稍后重试';
    }
  }
}
