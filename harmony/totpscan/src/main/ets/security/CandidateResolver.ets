import { AccountKind, StoredAccount } from '../model/Types';

export interface CandidateMatch {
  account: StoredAccount;
}

/**
 * 登录扫码后的本地候选筛选。
 *
 * 规则：登录二维码的 `url` 推导出注册域名后，只保留同一注册域名的已确认绑定。
 * 不比较路径、issuer、account 或 bindingId，也不做任何网络访问。
 * 多个候选全部落在同一注册域名内，交由宿主选择。
 */
export class CandidateResolver {
  static resolve(accounts: StoredAccount[], registeredDomain: string): CandidateMatch[] {
    const result: CandidateMatch[] = [];
    if (registeredDomain.length === 0) {
      return result;
    }
    for (let i = 0; i < accounts.length; i += 1) {
      const account = accounts[i];
      if (account.kind !== AccountKind.SCAN || !account.bindingConfirmed) {
        continue;
      }
      if (account.pinnedDomain !== registeredDomain) {
        continue;
      }
      result.push({ account: account });
    }
    return result;
  }
}
