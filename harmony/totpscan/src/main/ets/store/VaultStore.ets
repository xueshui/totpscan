import { asset } from '@kit.AssetStoreKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { utf8Decode, utf8Encode } from '../core/Bytes';
import { TotpError, TotpErrorCode } from '../core/TotpError';
import { emptyVault, VaultCodec, VaultData } from './Vault';

const ASSET_ALIAS = 'totpscan.vault.v1';
const ERROR_NOT_FOUND = 24000002;

/**
 * 安全存储：Asset Store Kit（HUKS 支持的凭据存储，等价于 HUKS 方案）。
 *
 * - 整个保险库（含所有共享密钥）作为一个 SECRET 条目加密保存；
 * - 访问级别 DEVICE_FIRST_UNLOCKED：开机首次解锁后可读，锁屏重启前不可读；
 * - 不提供明文回退；Asset Store 不可用时宁可失败，也不写入 preferences。
 */
export class VaultStore {
  async read(): Promise<VaultData | null> {
    const secret = await this.readSecret();
    if (secret === null) {
      return null;
    }
    let json = '';
    try {
      json = utf8Decode(secret);
    } catch (error) {
      throw new TotpError(TotpErrorCode.SECURE_STORAGE_ERROR, 'VAULT_DECODE_FAILED', '本地安全数据已损坏，请重新绑定');
    }
    return VaultCodec.decode(json);
  }

  async write(vault: VaultData): Promise<void> {
    const payload = utf8Encode(VaultCodec.encode(vault));
    const attributes: asset.AssetMap = new Map();
    attributes.set(asset.Tag.ALIAS, utf8Encode(ASSET_ALIAS));
    attributes.set(asset.Tag.SECRET, payload);
    attributes.set(asset.Tag.ACCESSIBILITY, asset.Accessibility.DEVICE_FIRST_UNLOCKED);
    try {
      const exists = await this.exists();
      if (exists) {
        await asset.update(attributes);
      } else {
        await asset.add(attributes);
      }
    } catch (error) {
      throw VaultStore.toStorageError(error, 'ASSET_WRITE_FAILED');
    }
  }

  /** 清空保险库。用于“删除全部数据”。 */
  async clear(): Promise<void> {
    const query: asset.AssetMap = new Map();
    query.set(asset.Tag.ALIAS, utf8Encode(ASSET_ALIAS));
    try {
      await asset.remove(query);
    } catch (error) {
      const err = error as BusinessError;
      if (err.code === ERROR_NOT_FOUND) {
        return;
      }
      throw VaultStore.toStorageError(error, 'ASSET_REMOVE_FAILED');
    }
  }

  /** 首次初始化：仅在不存在时写入空保险库。 */
  async ensureInitialized(biometricRequired: boolean): Promise<VaultData> {
    const existing = await this.read();
    if (existing !== null) {
      return existing;
    }
    const vault = emptyVault(biometricRequired);
    await this.write(vault);
    return vault;
  }

  private async readSecret(): Promise<Uint8Array | null> {
    const query: asset.AssetMap = new Map();
    query.set(asset.Tag.ALIAS, utf8Encode(ASSET_ALIAS));
    query.set(asset.Tag.RETURN_TYPE, asset.ReturnType.ALL);
    try {
      const result: Array<asset.AssetMap> = await asset.query(query);
      if (result.length === 0) {
        return null;
      }
      const value = result[0].get(asset.Tag.SECRET);
      if (value === undefined) {
        return null;
      }
      return value as Uint8Array;
    } catch (error) {
      const err = error as BusinessError;
      if (err.code === ERROR_NOT_FOUND) {
        return null;
      }
      throw VaultStore.toStorageError(error, 'ASSET_READ_FAILED');
    }
  }

  private async exists(): Promise<boolean> {
    const query: asset.AssetMap = new Map();
    query.set(asset.Tag.ALIAS, utf8Encode(ASSET_ALIAS));
    query.set(asset.Tag.RETURN_TYPE, asset.ReturnType.ATTRIBUTES);
    try {
      const result: Array<asset.AssetMap> = await asset.query(query);
      return result.length > 0;
    } catch (error) {
      const err = error as BusinessError;
      if (err.code === ERROR_NOT_FOUND) {
        return false;
      }
      throw VaultStore.toStorageError(error, 'ASSET_QUERY_FAILED');
    }
  }

  private static toStorageError(error: Object, tag: string): TotpError {
    if (error instanceof TotpError) {
      return error as TotpError;
    }
    const err = error as BusinessError;
    const code = err === undefined || err.code === undefined ? 'unknown' : String(err.code);
    return new TotpError(TotpErrorCode.SECURE_STORAGE_ERROR, `${tag}:${code}`, '安全存储不可用，无法保存或读取密钥');
  }
}
