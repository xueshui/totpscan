import { Base32 } from '../core/Base32';
import { TotpError, TotpErrorCode } from '../core/TotpError';
import { AccountKind, StoredAccount } from '../model/Types';
import { PinnedUrl } from '../security/PinnedUrl';

export const VAULT_VERSION = 1;

export interface VaultSettings {
  biometricRequired: boolean;
  /** 是否允许在界面显示扫码型账户的动态码（默认关闭）。 */
  revealScanCodes: boolean;
  /** 已校准的服务器时间偏移（毫秒）。 */
  clockOffsetMs: number;
  clockSyncedAtMs: number;
  clockKnown: boolean;
}

export interface VaultData {
  version: number;
  accounts: StoredAccount[];
  settings: VaultSettings;
}

export function emptyVault(biometricRequired: boolean): VaultData {
  return {
    version: VAULT_VERSION,
    accounts: [],
    settings: {
      biometricRequired: biometricRequired,
      revealScanCodes: false,
      clockOffsetMs: 0,
      clockSyncedAtMs: 0,
      clockKnown: false
    }
  };
}

/**
 * 加密保险库的序列化/校验。
 *
 * 保险库整体作为一个 Asset 条目存放；内容损坏时直接报错，不静默丢弃账户。
 */
export class VaultCodec {
  static encode(vault: VaultData): string {
    return JSON.stringify(vault);
  }

  static decode(json: string): VaultData {
    let parsed: Object;
    try {
      parsed = JSON.parse(json);
    } catch (error) {
      throw new TotpError(TotpErrorCode.SECURE_STORAGE_ERROR, 'VAULT_NOT_JSON', '本地安全数据已损坏，请重新绑定');
    }
    if (parsed === null || typeof parsed !== 'object' || Array.isArray(parsed)) {
      throw new TotpError(TotpErrorCode.SECURE_STORAGE_ERROR, 'VAULT_NOT_OBJECT', '本地安全数据已损坏，请重新绑定');
    }
    const root = parsed as Record<string, Object>;
    const version = VaultCodec.readInt(root, 'version');
    if (version !== VAULT_VERSION) {
      throw new TotpError(TotpErrorCode.SECURE_STORAGE_ERROR, 'VAULT_VERSION_UNSUPPORTED', '本地安全数据版本不受支持');
    }

    const settingsRaw = root['settings'];
    if (settingsRaw === undefined || typeof settingsRaw !== 'object' || Array.isArray(settingsRaw)) {
      throw new TotpError(TotpErrorCode.SECURE_STORAGE_ERROR, 'VAULT_SETTINGS_INVALID', '本地安全数据已损坏，请重新绑定');
    }
    const settingsObj = settingsRaw as Record<string, Object>;
    const settings: VaultSettings = {
      biometricRequired: VaultCodec.readBool(settingsObj, 'biometricRequired'),
      revealScanCodes: VaultCodec.readBoolOrDefault(settingsObj, 'revealScanCodes', false),
      clockOffsetMs: VaultCodec.readInt(settingsObj, 'clockOffsetMs'),
      clockSyncedAtMs: VaultCodec.readInt(settingsObj, 'clockSyncedAtMs'),
      clockKnown: VaultCodec.readBool(settingsObj, 'clockKnown')
    };

    const accountsRaw = root['accounts'];
    if (accountsRaw === undefined || !Array.isArray(accountsRaw)) {
      throw new TotpError(TotpErrorCode.SECURE_STORAGE_ERROR, 'VAULT_ACCOUNTS_INVALID', '本地安全数据已损坏，请重新绑定');
    }
    const accounts: StoredAccount[] = [];
    const array = accountsRaw as Object[];
    for (let i = 0; i < array.length; i += 1) {
      accounts.push(VaultCodec.decodeAccount(array[i]));
    }

    return {
      version: VAULT_VERSION,
      accounts: accounts,
      settings: settings
    };
  }

  private static decodeAccount(raw: Object): StoredAccount {
    if (raw === null || typeof raw !== 'object' || Array.isArray(raw)) {
      throw new TotpError(TotpErrorCode.SECURE_STORAGE_ERROR, 'VAULT_ACCOUNT_INVALID', '本地安全数据已损坏，请重新绑定');
    }
    const obj = raw as Record<string, Object>;
    const kindText = VaultCodec.readString(obj, 'kind');
    if (kindText !== AccountKind.STANDARD && kindText !== AccountKind.SCAN) {
      throw new TotpError(TotpErrorCode.SECURE_STORAGE_ERROR, 'VAULT_ACCOUNT_KIND_INVALID', '本地安全数据已损坏，请重新绑定');
    }
    const secretBase32 = VaultCodec.readString(obj, 'secretBase32');
    try {
      Base32.decodeLoose(secretBase32);
    } catch (error) {
      throw new TotpError(TotpErrorCode.SECURE_STORAGE_ERROR, 'VAULT_SECRET_INVALID', '本地安全数据已损坏，请重新绑定');
    }

    let submitUrl = VaultCodec.readString(obj, 'submitUrl');
    let bindingId = VaultCodec.readString(obj, 'bindingId');
    let bindingConfirmed = VaultCodec.readBool(obj, 'bindingConfirmed');
    let pinnedDomain = '';
    let pinnedPathQuery = '';
    if (kindText === AccountKind.SCAN) {
      try {
        const parts = PinnedUrl.parse(submitUrl);
        submitUrl = parts.full;
        pinnedDomain = parts.registeredDomain;
        pinnedPathQuery = parts.pathQuery;
      } catch (error) {
        throw new TotpError(TotpErrorCode.SECURE_STORAGE_ERROR, 'VAULT_SUBMIT_URL_INVALID', '本地提交地址已损坏，请重新绑定');
      }
      if (bindingId.length === 0) {
        throw new TotpError(TotpErrorCode.SECURE_STORAGE_ERROR, 'VAULT_BINDING_INCOMPLETE', '本地绑定数据已损坏，请重新绑定');
      }
    } else {
      submitUrl = '';
      bindingId = '';
      bindingConfirmed = false;
    }

    const account: StoredAccount = {
      localId: VaultCodec.readString(obj, 'localId'),
      kind: kindText as AccountKind,
      issuer: VaultCodec.readString(obj, 'issuer'),
      account: VaultCodec.readString(obj, 'account'),
      displayName: VaultCodec.readString(obj, 'displayName'),
      secretBase32: secretBase32,
      algorithm: VaultCodec.readString(obj, 'algorithm'),
      digits: VaultCodec.readInt(obj, 'digits'),
      period: VaultCodec.readInt(obj, 'period'),
      createdAtMs: VaultCodec.readInt(obj, 'createdAtMs'),
      submitUrl: submitUrl,
      pinnedDomain: pinnedDomain,
      pinnedPathQuery: pinnedPathQuery,
      bindingId: bindingId,
      bindingConfirmed: bindingConfirmed,
      bindingConfirmFailedAtMs: VaultCodec.readInt(obj, 'bindingConfirmFailedAtMs')
    };
    if (account.localId.length === 0 || account.issuer.length > 64 || account.account.length === 0) {
      throw new TotpError(TotpErrorCode.SECURE_STORAGE_ERROR, 'VAULT_ACCOUNT_FIELD_INVALID', '本地安全数据已损坏，请重新绑定');
    }
    if (account.digits !== 6 && account.digits !== 8) {
      throw new TotpError(TotpErrorCode.SECURE_STORAGE_ERROR, 'VAULT_ACCOUNT_DIGITS_INVALID', '本地安全数据已损坏，请重新绑定');
    }
    if (account.period < 1 || account.period > 3600) {
      throw new TotpError(TotpErrorCode.SECURE_STORAGE_ERROR, 'VAULT_ACCOUNT_PERIOD_INVALID', '本地安全数据已损坏，请重新绑定');
    }
    return account;
  }

  private static readString(obj: Record<string, Object>, key: string): string {
    const value: Object | undefined = obj[key];
    if (value === undefined || typeof value !== 'string') {
      throw new TotpError(TotpErrorCode.SECURE_STORAGE_ERROR, `VAULT_FIELD_INVALID:${key}`, '本地安全数据已损坏，请重新绑定');
    }
    return value as string;
  }

  private static readInt(obj: Record<string, Object>, key: string): number {
    const value: Object | undefined = obj[key];
    if (value === undefined || typeof value !== 'number' || !Number.isInteger(value)) {
      throw new TotpError(TotpErrorCode.SECURE_STORAGE_ERROR, `VAULT_FIELD_INVALID:${key}`, '本地安全数据已损坏，请重新绑定');
    }
    return value as number;
  }

  private static readBool(obj: Record<string, Object>, key: string): boolean {
    const value: Object | undefined = obj[key];
    if (value === undefined || typeof value !== 'boolean') {
      throw new TotpError(TotpErrorCode.SECURE_STORAGE_ERROR, `VAULT_FIELD_INVALID:${key}`, '本地安全数据已损坏，请重新绑定');
    }
    return value as boolean;
  }

  /** 用于新增设置的向后兼容读取：旧保险库缺少该字段时取默认值。 */
  private static readBoolOrDefault(obj: Record<string, Object>, key: string, fallback: boolean): boolean {
    const value: Object | undefined = obj[key];
    if (value === undefined) {
      return fallback;
    }
    if (typeof value !== 'boolean') {
      throw new TotpError(TotpErrorCode.SECURE_STORAGE_ERROR, `VAULT_FIELD_INVALID:${key}`, '本地安全数据已损坏，请重新绑定');
    }
    return value as boolean;
  }
}
