import { Base32 } from '../core/Base32';
import { bytesToHex, randomBytes } from '../core/Bytes';
import { TotpError, TotpErrorCode } from '../core/TotpError';
import { ClockService } from '../clock/ClockService';
import { TotpCalculator } from '../totp/TotpCalculator';
import { OtpauthUri } from '../totp/OtpauthUri';
import { normalizeAlgorithm } from '../totp/TotpOptions';
import { AccountKind, AccountView, LoginFailureKind, StandardAccountInput, StoredAccount } from '../model/Types';
import {
  BindOutcome,
  BindingPreview,
  ClockStatus,
  CodeSnapshot,
  LoginCandidate,
  LoginPreview,
  LoginResult,
  TrustedSite
} from '../model/Models';
import { BindingPayload, ParsedBinding } from '../qr/BindingPayload';
import { LoginPayload } from '../qr/LoginPayload';
import { CandidateMatch, CandidateResolver } from '../security/CandidateResolver';
import { PinnedEndpoint } from '../security/PinnedEndpoint';
import { RegisteredDomain } from '../security/RegisteredDomain';
import { BiometricGate } from '../security/BiometricGate';
import { VaultStore } from '../store/VaultStore';
import { emptyVault, VaultData } from '../store/Vault';
import { Submitter, SubmitOutcome, SubmitResult } from '../net/Submitter';
import { HttpClient } from '../net/HttpClient';
import { DEFAULT_TOTP_SCAN_CONFIG, TotpScanConfig } from './TotpScanConfig';

interface PendingBinding {
  parsed: ParsedBinding;
}

interface PendingLogin {
  loginId: string;
  candidates: LoginCandidate[];
  pinned: Map<string, PinnedEndpoint>;
  /** 会话标识，仅保存在内存，禁止落盘/日志。 */
  token: string;
  expiresAt: number;
  selectedLocalId: string;
}

/**
 * TOTPSCAN/v1 + 标准 TOTP 的宿主入口。
 *
 * 安全边界：
 * - 会话标识 token 只存在于 PendingLogin 内存对象中，不返回给宿主、不落盘、不写日志；
 * - 增强型账户的动态码默认不暴露：`code()` 只服务标准账户，`scanCode()` 仅在用户
 *   显式开启「显示扫码型账户的动态码」后可用；
 * - 提交只通过 Submitter + PinnedEndpoint，二维码中的 `url` 永远不是提交目标；
 * - 0 个域名匹配时在本地终止，零出站请求。
 */
export class TotpScanClient {
  private readonly config: TotpScanConfig;
  private readonly store: VaultStore = new VaultStore();
  private readonly clock: ClockService = new ClockService();
  private readonly submitter: Submitter;
  private readonly pendingBindings: Map<string, PendingBinding> = new Map();
  private readonly pendingLogins: Map<string, PendingLogin> = new Map();
  private vault: VaultData | null = null;
  private initialized = false;

  private constructor(config: TotpScanConfig) {
    this.config = config;
    this.submitter = new Submitter(this.clock, config.requestTimeoutMs);
  }

  /** 创建客户端。SDK 不依赖页面生命周期，可在 Ability onCreate 中创建。 */
  static create(config?: TotpScanConfig): TotpScanClient {
    let merged: TotpScanConfig;
    if (config === undefined) {
      merged = DEFAULT_TOTP_SCAN_CONFIG;
    } else {
      merged = {
        biometricRequired: config.biometricRequired,
        requestTimeoutMs: config.requestTimeoutMs,
        maxAccounts: config.maxAccounts,
        skewWarnSeconds: config.skewWarnSeconds,
        maxNoteLength: config.maxNoteLength
      };
    }
    const client = new TotpScanClient(merged);
    return client;
  }

  async init(): Promise<void> {
    if (this.initialized) {
      return;
    }
    const vault = await this.store.ensureInitialized(this.config.biometricRequired);
    this.vault = vault;
    this.clock.load(vault.settings);
    this.initialized = true;
  }

  // ---------------------------------------------------------------- 账户

  accounts(): AccountView[] {
    const vault = this.requireVault();
    const result: AccountView[] = [];
    for (let i = 0; i < vault.accounts.length; i += 1) {
      result.push(TotpScanClient.toView(vault.accounts[i]));
    }
    return result;
  }

  scanAccounts(): AccountView[] {
    const all = this.accounts();
    const result: AccountView[] = [];
    for (let i = 0; i < all.length; i += 1) {
      if (all[i].kind === AccountKind.SCAN) {
        result.push(all[i]);
      }
    }
    return result;
  }

  account(localId: string): AccountView {
    return TotpScanClient.toView(this.requireAccount(localId));
  }

  async addStandardAccount(input: StandardAccountInput): Promise<AccountView> {
    const vault = this.requireVault();
    if (vault.accounts.length >= this.config.maxAccounts) {
      throw new TotpError(TotpErrorCode.INVALID_ARGUMENT, 'ACCOUNT_LIMIT_REACHED', '账户数量已达上限');
    }

    const issuer = input.issuer.trim();
    const account = input.account.trim();
    TotpScanClient.validateText(issuer, 64, 'STANDARD_ISSUER_INVALID');
    TotpScanClient.validateText(account, 255, 'STANDARD_ACCOUNT_INVALID');
    if (account.length === 0) {
      throw new TotpError(TotpErrorCode.INVALID_ARGUMENT, 'STANDARD_ACCOUNT_EMPTY', '请输入账户名称');
    }
    const secret = Base32.decodeLoose(input.secretBase32);
    if (secret.length < 10 || secret.length > 64) {
      throw new TotpError(TotpErrorCode.INVALID_ARGUMENT, 'STANDARD_SECRET_LENGTH', '密钥长度无效（需 10–64 字节）');
    }
    const secretBase32 = Base32.encode(secret);
    let algorithm = 'SHA1';
    try {
      algorithm = normalizeAlgorithm(input.algorithm);
    } catch (error) {
      throw new TotpError(TotpErrorCode.INVALID_ARGUMENT, 'STANDARD_ALGORITHM_INVALID', '仅支持 SHA1 / SHA256 / SHA512');
    }
    if (input.digits !== 6 && input.digits !== 8) {
      throw new TotpError(TotpErrorCode.INVALID_ARGUMENT, 'STANDARD_DIGITS_INVALID', '仅支持 6 位或 8 位动态码');
    }
    if (!Number.isInteger(input.period) || input.period < 1 || input.period > 3600) {
      throw new TotpError(TotpErrorCode.INVALID_ARGUMENT, 'STANDARD_PERIOD_INVALID', '步长需在 1–3600 秒之间');
    }

    for (let i = 0; i < vault.accounts.length; i += 1) {
      const existing = vault.accounts[i];
      if (existing.kind === AccountKind.STANDARD &&
        existing.issuer === issuer &&
        existing.account === account &&
        existing.secretBase32 === secretBase32) {
        throw new TotpError(TotpErrorCode.DUPLICATE_ACCOUNT, 'STANDARD_ACCOUNT_DUPLICATED');
      }
    }

    const note = TotpScanClient.sanitizeNote(input.note, this.config.maxNoteLength);
    const record: StoredAccount = {
      localId: TotpScanClient.newId('a_'),
      kind: AccountKind.STANDARD,
      issuer: issuer,
      account: account,
      displayName: note.length > 0 ? note : (issuer.length > 0 ? issuer : account),
      secretBase32: secretBase32,
      algorithm: algorithm,
      digits: input.digits,
      period: input.period,
      createdAtMs: Date.now(),
      submitUrl: '',
      pinnedDomain: '',
      pinnedPathQuery: '',
      bindingId: '',
      bindingConfirmed: false,
      bindingConfirmFailedAtMs: 0
    };
    vault.accounts.push(record);
    await this.persist();
    return TotpScanClient.toView(record);
  }

  async importOtpauthUri(uri: string): Promise<AccountView> {
    const input = OtpauthUri.parse(uri);
    return this.addStandardAccount(input);
  }

  buildOtpauthUri(localId: string): string {
    const record = this.requireAccount(localId);
    if (record.kind !== AccountKind.STANDARD) {
      throw new TotpError(TotpErrorCode.NOT_STANDARD_ACCOUNT, 'EXPORT_NOT_ALLOWED_FOR_SCAN_ACCOUNT');
    }
    return OtpauthUri.build({
      issuer: record.issuer,
      account: record.account,
      secretBase32: record.secretBase32,
      algorithm: record.algorithm,
      digits: record.digits,
      period: record.period
    });
  }

  /**
   * 单账户导出 otpauth URI（仅内存字符串，不落盘、不写日志）。
   *
   * 标准账户与增强型账户都允许导出；增强型账户的二次确认由宿主界面负责。
   */
  exportOtpauthUri(localId: string): string {
    const record = this.requireAccount(localId);
    return OtpauthUri.build({
      issuer: record.issuer,
      account: record.account,
      secretBase32: record.secretBase32,
      algorithm: record.algorithm,
      digits: record.digits,
      period: record.period
    });
  }

  /** 仅标准账户可获取动态码；增强型账户一律拒绝，避免即时码外泄。 */
  code(localId: string): CodeSnapshot {
    const record = this.requireAccount(localId);
    if (record.kind !== AccountKind.STANDARD) {
      throw new TotpError(TotpErrorCode.NOT_STANDARD_ACCOUNT, 'CODE_NOT_EXPOSED_FOR_SCAN_ACCOUNT');
    }
    return this.snapshot(record);
  }

  /**
   * 扫码型账户的动态码。
   *
   * 只有用户在设置中显式开启「显示扫码型账户的动态码」后才可用；
   * 未开启时拒绝，避免调用方绕过界面开关拿到即时码。
   */
  scanCode(localId: string): CodeSnapshot {
    const record = this.requireAccount(localId);
    if (record.kind !== AccountKind.SCAN) {
      throw new TotpError(TotpErrorCode.NOT_SCAN_ACCOUNT, 'SCAN_CODE_FOR_STANDARD_ACCOUNT');
    }
    if (!this.requireVault().settings.revealScanCodes) {
      throw new TotpError(TotpErrorCode.SCAN_CODE_HIDDEN, 'SCAN_CODE_REVEAL_DISABLED');
    }
    return this.snapshot(record);
  }

  private snapshot(record: StoredAccount): CodeSnapshot {
    const nowMs = this.clock.nowMs();
    const code = TotpCalculator.generateBase32(record.secretBase32, nowMs, {
      algorithm: record.algorithm,
      digits: record.digits,
      period: record.period
    });
    const status = this.clock.status(this.config.skewWarnSeconds);
    return {
      localId: record.localId,
      code: code,
      digits: record.digits,
      period: record.period,
      remainingSeconds: TotpCalculator.remainingSeconds(nowMs, record.period),
      timeStep: TotpCalculator.timeStep(nowMs, record.period),
      clockOffsetMs: status.offsetMs,
      skewWarning: status.skewWarning
    };
  }

  async renameAccount(localId: string, note: string): Promise<AccountView> {
    const record = this.requireAccount(localId);
    const trimmed = TotpScanClient.normalizeNfc(note).trim();
    if (trimmed.length > this.config.maxNoteLength) {
      throw new TotpError(TotpErrorCode.INVALID_ARGUMENT, 'NOTE_TOO_LONG', `备注最多 ${this.config.maxNoteLength} 个字符`);
    }
    if (TotpScanClient.hasControl(trimmed)) {
      throw new TotpError(TotpErrorCode.INVALID_ARGUMENT, 'NOTE_CONTAINS_CONTROL', '备注不能包含换行或控制字符');
    }
    record.displayName = trimmed.length > 0 ? trimmed : (record.issuer.length > 0 ? record.issuer : record.account);
    await this.persist();
    return TotpScanClient.toView(record);
  }

  async removeAccount(localId: string): Promise<void> {
    const vault = this.requireVault();
    let index = -1;
    for (let i = 0; i < vault.accounts.length; i += 1) {
      if (vault.accounts[i].localId === localId) {
        index = i;
        break;
      }
    }
    if (index < 0) {
      throw new TotpError(TotpErrorCode.ACCOUNT_NOT_FOUND, 'ACCOUNT_NOT_FOUND');
    }
    vault.accounts.splice(index, 1);
    await this.persist();
  }

  async clearAll(): Promise<void> {
    await this.store.clear();
    this.pendingBindings.clear();
    this.pendingLogins.clear();
    const vault = emptyVault(this.vault === null ? this.config.biometricRequired : this.vault.settings.biometricRequired);
    this.vault = vault;
    this.clock.load(vault.settings);
    await this.persist();
  }

  // ---------------------------------------------------------------- 绑定

  async prepareBinding(qrText: string): Promise<BindingPreview> {
    this.requireVault();
    const parsed = BindingPayload.parse(qrText, this.clock.nowSeconds());
    const previewId = TotpScanClient.newId('p_');
    this.prunePending();
    this.pendingBindings.set(previewId, { parsed: parsed });
    return {
      previewId: previewId,
      bindingId: parsed.bindingId,
      issuer: parsed.issuer,
      account: parsed.account,
      submitUrl: parsed.submitUrl,
      pinnedDomain: parsed.registeredDomain,
      pinnedPathQuery: parsed.pathQuery,
      algorithm: parsed.algorithm,
      digits: parsed.digits,
      period: parsed.period,
      expiresAt: parsed.expiresAt,
      looseSource: parsed.pathQuery === '/',
      similarHints: RegisteredDomain.similarTo(
        parsed.registeredDomain,
        this.pinnedDomainsExcept(parsed.registeredDomain)
      )
    };
  }

  /**
   * 确认绑定。备注仅存本地（displayName），不影响二维码定位信息。
   */
  async confirmBinding(previewId: string, note: string): Promise<BindOutcome> {
    const pending = this.pendingBindings.get(previewId);
    if (pending === undefined) {
      throw new TotpError(TotpErrorCode.INTERNAL, 'BINDING_PREVIEW_MISSING', '绑定会话已失效，请重新扫码');
    }
    let parsed: ParsedBinding;
    try {
      parsed = BindingPayload.parse(pending.parsed.rawPayload, this.clock.nowSeconds());
    } catch (error) {
      this.pendingBindings.delete(previewId);
      throw error as TotpError;
    }

    // 规范 §4.1：备注非法时只丢弃备注，不连带拒绝绑定。
    const trimmedNote = TotpScanClient.sanitizeNote(note, this.config.maxNoteLength);

    const pinned = PinnedEndpoint.fromVerifiedBinding(parsed.submitUrl);
    const vault = this.requireVault();
    let existingIndex = -1;
    for (let i = 0; i < vault.accounts.length; i += 1) {
      const account = vault.accounts[i];
      if (account.kind !== AccountKind.SCAN) {
        continue;
      }
      // 新规则：同一注册域名 + 同一 path+query 前缀 + 同一 iss/acc 视为同一绑定。
      if (account.bindingId === parsed.bindingId ||
        (account.pinnedDomain === parsed.registeredDomain &&
          account.pinnedPathQuery === parsed.pathQuery &&
          account.account === parsed.account &&
          account.issuer === parsed.issuer)) {
        existingIndex = i;
        break;
      }
    }

    const previousName = existingIndex >= 0 ? vault.accounts[existingIndex].displayName : '';
    const defaultName = parsed.issuer.length > 0 ? parsed.issuer : parsed.account;
    const record: StoredAccount = {
      localId: existingIndex >= 0 ? vault.accounts[existingIndex].localId : TotpScanClient.newId('a_'),
      kind: AccountKind.SCAN,
      issuer: parsed.issuer,
      account: parsed.account,
      displayName: trimmedNote.length > 0 ? trimmedNote : (previousName.length > 0 ? previousName : defaultName),
      secretBase32: parsed.secretBase32,
      algorithm: parsed.algorithm,
      digits: parsed.digits,
      period: parsed.period,
      createdAtMs: existingIndex >= 0 ? vault.accounts[existingIndex].createdAtMs : Date.now(),
      submitUrl: pinned.canonicalUrl,
      pinnedDomain: parsed.registeredDomain,
      pinnedPathQuery: parsed.pathQuery,
      bindingId: parsed.bindingId,
      bindingConfirmed: false,
      bindingConfirmFailedAtMs: 0
    };
    if (existingIndex >= 0) {
      vault.accounts[existingIndex] = record;
    } else {
      if (vault.accounts.length >= this.config.maxAccounts) {
        throw new TotpError(TotpErrorCode.INVALID_ARGUMENT, 'ACCOUNT_LIMIT_REACHED', '账户数量已达上限');
      }
      vault.accounts.push(record);
    }
    await this.persist();
    this.pendingBindings.delete(previewId);

    return this.performBindingConfirm(record);
  }

  /** 服务器确认失败后手动重试（不改动密钥与固化地址）。 */
  async retryBindingConfirm(localId: string): Promise<BindOutcome> {
    const record = this.requireAccount(localId);
    if (record.kind !== AccountKind.SCAN) {
      throw new TotpError(TotpErrorCode.NOT_SCAN_ACCOUNT, 'NOT_SCAN_ACCOUNT');
    }
    return this.performBindingConfirm(record);
  }

  discardBinding(previewId: string): void {
    this.pendingBindings.delete(previewId);
  }

  private async performBindingConfirm(record: StoredAccount): Promise<BindOutcome> {
    const pinned = PinnedEndpoint.fromStored(record.submitUrl);
    const code = TotpCalculator.generateBase32(record.secretBase32, this.clock.nowMs(), {
      algorithm: record.algorithm,
      digits: record.digits,
      period: record.period
    });
    let confirmed = false;
    let message = '';
    try {
      const result = await this.submitter.confirmBinding(pinned, record.bindingId, code);
      if (result.outcome === SubmitOutcome.OK) {
        confirmed = true;
      } else {
        message = result.outcome === SubmitOutcome.RATE_LIMITED
          ? '已保存到本地，但服务器确认被限流，请稍后重试。'
          : '已保存到本地，但服务器未确认，请检查设备时间后重试确认。';
      }
    } catch (error) {
      message = '已保存到本地，但服务器确认失败（网络不可用），请稍后重试。';
    }
    record.bindingConfirmed = confirmed;
    record.bindingConfirmFailedAtMs = confirmed ? 0 : Date.now();
    await this.persist();
    this.persistClockSafely();
    return {
      account: TotpScanClient.toView(record),
      confirmed: confirmed,
      message: message
    };
  }

  // ---------------------------------------------------------------- 登录

  /**
   * 解析登录二维码，按注册域名筛选候选。
   *
   * 登录二维码只带域名（`url`）、会话标识（`token`）与过期时间（`exp`）；
   * 路径只使用绑定时的 `path`。0 个候选立即抛错（零出站请求）；
   * 1 个自动选中；多个交由宿主在同一注册域名内选择。
   */
  async prepareLogin(qrText: string): Promise<LoginPreview> {
    const vault = this.requireVault();
    const parsed = LoginPayload.parse(qrText, this.clock.nowSeconds());

    const candidates: LoginCandidate[] = [];
    const pinned = new Map<string, PinnedEndpoint>();
    const matches: CandidateMatch[] = CandidateResolver.resolve(vault.accounts, parsed.registeredDomain);
    for (let i = 0; i < matches.length; i += 1) {
      const account = matches[i].account;
      try {
        pinned.set(account.localId, PinnedEndpoint.fromStored(account.submitUrl));
      } catch (error) {
        // 单条固化地址损坏时跳过该账户，不阻断其他候选。
        continue;
      }
      candidates.push({
        localId: account.localId,
        issuer: account.issuer,
        account: account.account,
        displayName: account.displayName.length > 0 ? account.displayName : account.issuer,
        submitUrl: account.submitUrl,
        pinnedDomain: account.pinnedDomain,
        pinnedPathQuery: account.pinnedPathQuery,
        looseSource: account.pinnedPathQuery === '/'
      });
    }

    if (candidates.length === 0) {
      throw new TotpError(TotpErrorCode.ADDRESS_MISMATCH, 'NO_PINNED_DOMAIN_MATCHED');
    }

    const loginId = TotpScanClient.newId('l_');
    this.prunePending();
    this.pendingLogins.set(loginId, {
      loginId: loginId,
      candidates: candidates,
      pinned: pinned,
      token: parsed.token,
      expiresAt: parsed.expiresAt,
      selectedLocalId: candidates.length === 1 ? candidates[0].localId : ''
    });

    return {
      loginId: loginId,
      candidates: candidates,
      selectedLocalId: candidates.length === 1 ? candidates[0].localId : '',
      expiresAt: parsed.expiresAt
    };
  }

  /** 只允许在本次候选集合内选择，绝不跨固化地址混合。 */
  selectLoginCandidate(loginId: string, localId: string): void {
    const pending = this.pendingLogins.get(loginId);
    if (pending === undefined) {
      throw new TotpError(TotpErrorCode.INTERNAL, 'LOGIN_PREVIEW_MISSING', '登录会话已失效，请重新扫码');
    }
    let allowed = false;
    for (let i = 0; i < pending.candidates.length; i += 1) {
      if (pending.candidates[i].localId === localId) {
        allowed = true;
        break;
      }
    }
    if (!allowed) {
      throw new TotpError(TotpErrorCode.ADDRESS_MISMATCH, 'LOGIN_CANDIDATE_NOT_ALLOWED');
    }
    pending.selectedLocalId = localId;
  }

  /**
   * 生物识别 → 用选中账户计算动态码 → 提交到**固化地址**。
   * token 与动态码都不经过宿主，也不写日志。
   */
  async authorizeLogin(loginId: string, localId?: string): Promise<LoginResult> {
    const pending = this.pendingLogins.get(loginId);
    if (pending === undefined) {
      throw new TotpError(TotpErrorCode.INTERNAL, 'LOGIN_PREVIEW_MISSING', '登录会话已失效，请重新扫码');
    }
    if (this.clock.nowSeconds() > pending.expiresAt) {
      this.pendingLogins.delete(loginId);
      throw new TotpError(TotpErrorCode.LOGIN_EXPIRED, 'LOGIN_SESSION_EXPIRED');
    }

    let selected = localId === undefined ? pending.selectedLocalId : localId;
    if (selected.length === 0) {
      throw new TotpError(TotpErrorCode.INVALID_ARGUMENT, 'LOGIN_CANDIDATE_NOT_SELECTED', '请选择要使用的账户');
    }
    let allowed = false;
    for (let i = 0; i < pending.candidates.length; i += 1) {
      if (pending.candidates[i].localId === selected) {
        allowed = true;
        break;
      }
    }
    if (!allowed) {
      throw new TotpError(TotpErrorCode.ADDRESS_MISMATCH, 'LOGIN_CANDIDATE_NOT_ALLOWED');
    }
    pending.selectedLocalId = selected;

    const account = this.requireAccount(selected);
    if (account.kind !== AccountKind.SCAN) {
      throw new TotpError(TotpErrorCode.NOT_SCAN_ACCOUNT, 'STANDARD_ACCOUNT_NOT_SUBMITTABLE');
    }
    // 提交前二次校验：预览后绑定状态可能被撤销或尚未确认。
    if (!account.bindingConfirmed) {
      throw new TotpError(
        TotpErrorCode.NOT_BOUND,
        'BINDING_NOT_CONFIRMED',
        '该账户的绑定尚未被服务器确认，请先在账户详情中重试确认'
      );
    }
    const pinned = pending.pinned.get(selected);
    if (pinned === undefined) {
      throw new TotpError(TotpErrorCode.INTERNAL, 'LOGIN_PINNED_MISSING');
    }

    if (this.requireVault().settings.biometricRequired) {
      await BiometricGate.authenticate('验证身份以提交动态码');
    }

    const code = TotpCalculator.generateBase32(account.secretBase32, this.clock.nowMs(), {
      algorithm: account.algorithm,
      digits: account.digits,
      period: account.period
    });

    let result: SubmitResult;
    try {
      result = await this.submitter.verify(pinned, pending.token, code);
    } catch (error) {
      this.pendingLogins.delete(loginId);
      if (error instanceof TotpError && (error as TotpError).code === TotpErrorCode.NETWORK_ERROR) {
        return {
          success: false,
          kind: LoginFailureKind.NETWORK,
          message: '网络连接失败，请检查网络后重新扫码'
        };
      }
      throw error as TotpError;
    }
    this.pendingLogins.delete(loginId);
    this.persistClockSafely();
    return TotpScanClient.mapLoginResult(result);
  }

  discardLogin(loginId: string): void {
    this.pendingLogins.delete(loginId);
  }

  // ---------------------------------------------------------------- 设置

  biometricRequired(): boolean {
    return this.requireVault().settings.biometricRequired;
  }

  async setBiometricRequired(required: boolean): Promise<void> {
    const vault = this.requireVault();
    vault.settings.biometricRequired = required;
    await this.persist();
  }

  /** 是否允许在界面显示扫码型账户的动态码（默认关闭）。 */
  scanCodeRevealEnabled(): boolean {
    return this.requireVault().settings.revealScanCodes;
  }

  /**
   * 切换「显示扫码型账户的动态码」。
   *
   * 本方法只负责持久化；本地身份验证与风险确认由宿主界面在调用前完成。
   */
  async setScanCodeRevealEnabled(enabled: boolean): Promise<void> {
    const vault = this.requireVault();
    vault.settings.revealScanCodes = enabled;
    await this.persist();
  }

  clockStatus(): ClockStatus {
    return this.clock.status(this.config.skewWarnSeconds);
  }

  /** 用任一已绑定服务器校准设备时间（GET /healthz，不提交任何数据）。 */
  async calibrateClock(): Promise<ClockStatus> {
    const all = this.scanAccounts();
    if (all.length === 0) {
      return this.clock.status(this.config.skewWarnSeconds);
    }
    const pinned = PinnedEndpoint.fromStored(all[0].submitUrl);
    try {
      const serverTime = await HttpClient.getServerTime(`${pinned.origin}/healthz`, this.config.requestTimeoutMs);
      if (serverTime > 0) {
        this.clock.updateFromServer(serverTime);
        await this.persist();
      }
    } catch (error) {
      // 校准失败不改变现有偏移，由 UI 展示网络提示。
    }
    return this.clock.status(this.config.skewWarnSeconds);
  }

  /** 已绑定站点（按注册域名去重）。 */
  trustedSites(): TrustedSite[] {
    const result: TrustedSite[] = [];
    const index = new Map<string, number>();
    const accounts = this.requireVault().accounts;
    for (let i = 0; i < accounts.length; i += 1) {
      const account = accounts[i];
      if (account.kind !== AccountKind.SCAN || account.pinnedDomain.length === 0) {
        continue;
      }
      const existing = index.get(account.pinnedDomain);
      if (existing === undefined) {
        index.set(account.pinnedDomain, result.length);
        result.push({
          domain: account.pinnedDomain,
          firstSeenAtMs: account.createdAtMs,
          accountCount: 1
        });
      } else {
        result[existing].accountCount = result[existing].accountCount + 1;
        if (account.createdAtMs < result[existing].firstSeenAtMs) {
          result[existing].firstSeenAtMs = account.createdAtMs;
        }
      }
    }
    return result;
  }

  maxNoteLength(): number {
    return this.config.maxNoteLength;
  }

  // ---------------------------------------------------------------- 内部

  private requireVault(): VaultData {
    if (this.vault === null) {
      throw new TotpError(TotpErrorCode.INTERNAL, 'CLIENT_NOT_INITIALIZED', '应用尚未初始化');
    }
    return this.vault;
  }

  private requireAccount(localId: string): StoredAccount {
    const vault = this.requireVault();
    for (let i = 0; i < vault.accounts.length; i += 1) {
      if (vault.accounts[i].localId === localId) {
        return vault.accounts[i];
      }
    }
    throw new TotpError(TotpErrorCode.ACCOUNT_NOT_FOUND, 'ACCOUNT_NOT_FOUND');
  }

  /**
   * 列出除指定注册域名之外已绑定的域名，用于相似域名提示。
   */
  private pinnedDomainsExcept(domain: string): string[] {
    const result: string[] = [];
    const seen = new Set<string>();
    const accounts = this.requireVault().accounts;
    for (let i = 0; i < accounts.length; i += 1) {
      const account = accounts[i];
      if (account.kind !== AccountKind.SCAN || account.pinnedDomain.length === 0) {
        continue;
      }
      if (account.pinnedDomain === domain || seen.has(account.pinnedDomain)) {
        continue;
      }
      seen.add(account.pinnedDomain);
      result.push(account.pinnedDomain);
    }
    return result;
  }

  private async persist(): Promise<void> {
    const vault = this.requireVault();
    vault.settings = this.clock.toSettings(vault.settings);
    await this.store.write(vault);
  }

  private persistClockSafely(): void {
    this.persist().catch((error: Object) => {
      // 时钟偏移写入失败不影响已完成/已提交的操作。
    });
  }

  private prunePending(): void {
    const now = this.clock.nowSeconds();
    const expiredLogins: string[] = [];
    this.pendingLogins.forEach((value: PendingLogin, key: string) => {
      if (now > value.expiresAt) {
        expiredLogins.push(key);
      }
    });
    for (let i = 0; i < expiredLogins.length; i += 1) {
      this.pendingLogins.delete(expiredLogins[i]);
    }
    const expiredBindings: string[] = [];
    this.pendingBindings.forEach((value: PendingBinding, key: string) => {
      if (value.parsed.expiresAt >= 0 && now > value.parsed.expiresAt) {
        expiredBindings.push(key);
      }
    });
    for (let i = 0; i < expiredBindings.length; i += 1) {
      this.pendingBindings.delete(expiredBindings[i]);
    }
  }

  private static mapLoginResult(result: SubmitResult): LoginResult {
    switch (result.outcome) {
      case SubmitOutcome.OK:
        return { success: true, kind: LoginFailureKind.NONE, message: '登录成功，已通知网页完成认证' };
      case SubmitOutcome.REJECTED:
        return { success: false, kind: LoginFailureKind.REJECTED, message: '认证失败，请在网页重新发起登录' };
      case SubmitOutcome.RATE_LIMITED:
        return { success: false, kind: LoginFailureKind.RATE_LIMITED, message: '请求过于频繁，请稍后再试' };
      case SubmitOutcome.INVALID:
        return { success: false, kind: LoginFailureKind.INVALID_REQUEST, message: '请求无效，请重新扫码' };
      default:
        return { success: false, kind: LoginFailureKind.UNKNOWN, message: '服务器暂时不可用，请稍后重试' };
    }
  }

  private static toView(record: StoredAccount): AccountView {
    let weakSecret = false;
    if (record.kind === AccountKind.STANDARD) {
      try {
        weakSecret = Base32.decodeLoose(record.secretBase32).length < 16;
      } catch (error) {
        weakSecret = true;
      }
    }
    return {
      localId: record.localId,
      kind: record.kind,
      issuer: record.issuer,
      account: record.account,
      displayName: record.displayName.length > 0
        ? record.displayName
        : (record.issuer.length > 0 ? record.issuer : record.account),
      algorithm: record.algorithm,
      digits: record.digits,
      period: record.period,
      createdAtMs: record.createdAtMs,
      submitUrl: record.submitUrl,
      pinnedDomain: record.pinnedDomain,
      pinnedPathQuery: record.pinnedPathQuery,
      bindingId: record.bindingId,
      bindingConfirmed: record.bindingConfirmed,
      weakSecret: weakSecret
    };
  }

  private static newId(prefix: string): string {
    return prefix + bytesToHex(randomBytes(16));
  }

  private static validateText(value: string, maxLength: number, errorMessage: string): void {
    if (value.length > maxLength) {
      throw new TotpError(TotpErrorCode.INVALID_ARGUMENT, errorMessage);
    }
    if (TotpScanClient.hasControl(value)) {
      throw new TotpError(TotpErrorCode.INVALID_ARGUMENT, errorMessage);
    }
  }

  private static hasControl(value: string): boolean {
    return new RegExp('[\\u0000-\\u001F\\u007F]').test(value);
  }

  private static normalizeNfc(value: string): string {
    try {
      return value.normalize('NFC');
    } catch (error) {
      return value;
    }
  }

  /** 备注规范化：NFC、去首尾空白；超长或含控制字符时返回空串（丢弃备注，不影响账户）。 */
  private static sanitizeNote(value: string | undefined, maxLength: number): string {
    if (value === undefined) {
      return '';
    }
    const text = TotpScanClient.normalizeNfc(value).trim();
    if (text.length === 0 || text.length > maxLength) {
      return '';
    }
    if (TotpScanClient.hasControl(text)) {
      return '';
    }
    return text;
  }
}
