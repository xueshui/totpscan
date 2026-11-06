import { AccountView, LoginFailureKind } from './Types';

/** 绑定预览：不含密钥，可安全展示。 */
export interface BindingPreview {
  previewId: string;
  bindingId: string;
  issuer: string;
  account: string;
  /** 绑定时的完整提交地址（含 path+query）。 */
  submitUrl: string;
  /** PSL 级注册域名，例如 `example.com`。 */
  pinnedDomain: string;
  /** 钉住的提交路径前缀（含查询串）。 */
  pinnedPathQuery: string;
  algorithm: string;
  digits: number;
  period: number;
  /** 未提供 exp 时为 -1。 */
  expiresAt: number;
  /** 固化为裸源，匹配较宽松，UI 应提示风险。 */
  looseSource: boolean;
  /** 与已绑定站点相似的提示，仅提示、不拦截。 */
  similarHints: string[];
}

export interface BindOutcome {
  account: AccountView;
  /** 服务器确认接口是否成功。 */
  confirmed: boolean;
  /** 已本地保存但服务器确认失败时的提示。 */
  message: string;
}

/** 某个本地增强型账户与本次登录二维码精确匹配的结果。 */
export interface LoginCandidate {
  localId: string;
  issuer: string;
  account: string;
  displayName: string;
  /** 该账户的完整提交地址（提交目标）。 */
  submitUrl: string;
  /** 钉住的 PSL 级注册域名。 */
  pinnedDomain: string;
  /** 钉住的 path+query 前缀。 */
  pinnedPathQuery: string;
  looseSource: boolean;
}

/**
 * 登录预览：SDK 不向宿主暴露会话 token。
 *
 * candidates 只包含注册域名与二维码 `url` 一致的本地账户；
 * 0 个时 prepareLogin 直接抛错，绝不会出现空候选但继续提交的情况。
 */
export interface LoginPreview {
  loginId: string;
  candidates: LoginCandidate[];
  /** 唯一候选时 SDK 自动选中；多候选时为空，需宿主选择。 */
  selectedLocalId: string;
  expiresAt: number;
}

export interface LoginResult {
  success: boolean;
  kind: LoginFailureKind;
  message: string;
}

/** 仅标准账户可获取。增强型账户的即时码不对宿主暴露。 */
export interface CodeSnapshot {
  localId: string;
  code: string;
  digits: number;
  period: number;
  remainingSeconds: number;
  timeStep: number;
  clockOffsetMs: number;
  skewWarning: boolean;
}

export interface ClockStatus {
  known: boolean;
  offsetMs: number;
  syncedAtMs: number;
  /** |offset| 超过告警阈值。 */
  skewWarning: boolean;
  /** 面向用户的短说明。 */
  label: string;
}

/** 已绑定的站点（按注册域名聚合）。 */
export interface TrustedSite {
  domain: string;
  firstSeenAtMs: number;
  accountCount: number;
}
