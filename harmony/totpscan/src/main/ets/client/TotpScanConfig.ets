export interface TotpScanConfig {
  /** 提交前是否强制生物识别；默认 true，可由用户在设置中关闭。 */
  biometricRequired: boolean;
  /** 单次 HTTP 连接/读取超时（毫秒）。 */
  requestTimeoutMs: number;
  /** 本地账户数量上限。 */
  maxAccounts: number;
  /** 时间偏差告警阈值（秒）。 */
  skewWarnSeconds: number;
  /** 本地备注最大长度（规范 §4.1：≤64 字符）。 */
  maxNoteLength: number;
}

export const DEFAULT_TOTP_SCAN_CONFIG: TotpScanConfig = {
  biometricRequired: true,
  requestTimeoutMs: 8000,
  maxAccounts: 50,
  skewWarnSeconds: 30,
  maxNoteLength: 64
};
