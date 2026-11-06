export enum AccountKind {
  /** 标准 TOTP（RFC 6238），不含固化地址与扫码提交。 */
  STANDARD = 'standard',
  /** TOTPSCAN/v1 协议绑定账户，含固化提交地址。 */
  SCAN = 'scan'
}

/** 添加标准账户 / otpauth 导入的输入。 */
export interface StandardAccountInput {
  issuer: string;
  account: string;
  secretBase32: string;
  algorithm: string;
  digits: number;
  period: number;
  /** 可选本地备注（≤64 字符，仅存本地，不进 otpauth URI、不写日志）。 */
  note?: string;
}

/** 面向 UI 的账户视图（不含密钥）。 */
export interface AccountView {
  localId: string;
  kind: AccountKind;
  issuer: string;
  account: string;
  displayName: string;
  algorithm: string;
  digits: number;
  period: number;
  createdAtMs: number;
  /** 仅扫码账户非空：绑定时的完整提交地址（含 path+query）。 */
  submitUrl: string;
  /** 仅扫码账户非空：PSL 级注册域名，例如 `example.com`。 */
  pinnedDomain: string;
  /** 仅扫码账户非空：钉住的提交路径前缀（含查询串）。 */
  pinnedPathQuery: string;
  /** 仅扫码账户非空。 */
  bindingId: string;
  /** 绑定确认状态；标准账户恒为 false。 */
  bindingConfirmed: boolean;
  /** 标准账户：密钥解码后不足 16 字节时为 true，UI 应提示强度不足。 */
  weakSecret: boolean;
}

/** 储存在加密保险库中的账户记录。 */
export interface StoredAccount {
  localId: string;
  kind: AccountKind;
  issuer: string;
  account: string;
  displayName: string;
  secretBase32: string;
  algorithm: string;
  digits: number;
  period: number;
  createdAtMs: number;
  /** 扫码账户：绑定时的完整提交地址（含 path+query）；标准账户为空串。 */
  submitUrl: string;
  /** 扫码账户：PSL 级注册域名；标准账户为空串。 */
  pinnedDomain: string;
  /** 扫码账户：钉住的 path+query 前缀；标准账户为空串。 */
  pinnedPathQuery: string;
  bindingId: string;
  bindingConfirmed: boolean;
  /** 最近一次绑定确认失败的时间；0 表示无。 */
  bindingConfirmFailedAtMs: number;
}

export enum LoginFailureKind {
  NONE = 'none',
  ADDRESS_MISMATCH = 'address_mismatch',
  EXPIRED = 'expired',
  BIOMETRIC = 'biometric',
  NETWORK = 'network',
  REJECTED = 'rejected',
  RATE_LIMITED = 'rate_limited',
  INVALID_REQUEST = 'invalid_request',
  UNKNOWN = 'unknown'
}
