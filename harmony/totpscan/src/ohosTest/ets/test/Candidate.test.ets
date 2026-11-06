import { describe, expect, it } from '@ohos/hypium';
import { AccountKind, StoredAccount } from '../../../main/ets/model/Types';
import { CandidateMatch, CandidateResolver } from '../../../main/ets/security/CandidateResolver';

function scanAccount(
  localId: string, submitUrl: string, pinnedDomain: string, pinnedPathQuery: string
): StoredAccount {
  return {
    localId: localId,
    kind: AccountKind.SCAN,
    issuer: 'Example Corp',
    account: `${localId}@example.com`,
    displayName: '',
    secretBase32: 'GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ',
    algorithm: 'SHA1',
    digits: 6,
    period: 30,
    createdAtMs: 1762396800000,
    submitUrl: submitUrl,
    pinnedDomain: pinnedDomain,
    pinnedPathQuery: pinnedPathQuery,
    bindingId: 'b_3nS0kq9uV2xJ0mQw1sT4aA',
    bindingConfirmed: true,
    bindingConfirmFailedAtMs: 0
  };
}

function standardAccount(localId: string): StoredAccount {
  return {
    localId: localId,
    kind: AccountKind.STANDARD,
    issuer: 'Example Corp',
    account: 'alice@example.com',
    displayName: '',
    secretBase32: 'GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ',
    algorithm: 'SHA1',
    digits: 6,
    period: 30,
    createdAtMs: 1762396800000,
    submitUrl: '',
    pinnedDomain: '',
    pinnedPathQuery: '',
    bindingId: '',
    bindingConfirmed: false,
    bindingConfirmFailedAtMs: 0
  };
}

function ids(matches: CandidateMatch[]): string[] {
  const result: string[] = [];
  for (let i = 0; i < matches.length; i += 1) {
    result.push(matches[i].account.localId);
  }
  return result;
}

/**
 * 登录扫码候选：只按注册域名筛选，候选全部落在同一注册域名内。
 */
export default function candidateTest(): void {
  describe('CandidateResolver', () => {
    const accounts: StoredAccount[] = [];
    accounts.push(scanAccount('alice', 'https://auth.example.com/totp/v1/verify', 'example.com', '/totp/v1/verify'));
    accounts.push(scanAccount('bob', 'https://auth.example.com/totp/v1/verify', 'example.com', '/totp/v1/verify'));
    accounts.push(scanAccount('carol', 'https://auth.example.com/totp/v1', 'example.com', '/totp/v1'));
    accounts.push(scanAccount('dave', 'https://other.example.com/totp/v1/verify', 'example.com', '/totp/v1/verify'));
    accounts.push(scanAccount('root', 'https://root.example.com/', 'example.com', '/'));
    accounts.push(scanAccount('frank', 'https://frank.example.org/totp/v1/verify', 'example.org', '/totp/v1/verify'));
    accounts.push(standardAccount('standard'));

    it('zero_candidates_terminates_locally', 0, () => {
      expect(CandidateResolver.resolve(accounts, 'example.net').length).assertEqual(0);
      expect(CandidateResolver.resolve(accounts, '').length).assertEqual(0);
    });

    it('single_candidate_is_selected_automatically', 0, () => {
      const matches = CandidateResolver.resolve(accounts, 'example.org');
      expect(matches.length).assertEqual(1);
      expect(matches[0].account.localId).assertEqual('frank');
    });

    it('multiple_accounts_in_same_registered_domain', 0, () => {
      const matches = CandidateResolver.resolve(accounts, 'example.com');
      const result = ids(matches);
      expect(matches.length).assertEqual(5);
      expect(result.indexOf('alice') >= 0).assertTrue();
      expect(result.indexOf('bob') >= 0).assertTrue();
      expect(result.indexOf('carol') >= 0).assertTrue();
      expect(result.indexOf('dave') >= 0).assertTrue();
      expect(result.indexOf('root') >= 0).assertTrue();
      // 不同注册域名不混列。
      expect(result.indexOf('frank')).assertEqual(-1);
      expect(result.indexOf('standard')).assertEqual(-1);
    });

    it('never_mixes_different_registered_domains', 0, () => {
      const others = CandidateResolver.resolve(accounts, 'example.org');
      expect(ids(others).indexOf('alice')).assertEqual(-1);
      expect(ids(others).indexOf('frank') >= 0).assertTrue();
    });

    it('standard_accounts_never_become_candidates', 0, () => {
      const onlyStandard: StoredAccount[] = [];
      onlyStandard.push(standardAccount('standard'));
      expect(CandidateResolver.resolve(onlyStandard, 'example.com').length).assertEqual(0);
    });

    it('unconfirmed_binding_is_not_a_candidate', 0, () => {
      const mixed: StoredAccount[] = [];
      const pending = scanAccount('pending', 'https://auth.example.com/totp/v1/verify', 'example.com', '/totp/v1/verify');
      pending.bindingConfirmed = false;
      mixed.push(pending);
      mixed.push(scanAccount('confirmed', 'https://auth.example.com/totp/v1/verify', 'example.com', '/totp/v1/verify'));
      const matches = CandidateResolver.resolve(mixed, 'example.com');
      expect(matches.length).assertEqual(1);
      expect(matches[0].account.localId).assertEqual('confirmed');
    });

    it('does_not_use_issuer_or_account_to_match', 0, () => {
      // 即使 issuer/account 相同，只要注册域名不同就不进入候选。
      const lookalike = scanAccount('lookalike', 'https://phish.example.net/totp/v1/verify', 'example.net', '/totp/v1/verify');
      const pool: StoredAccount[] = [];
      pool.push(lookalike);
      expect(CandidateResolver.resolve(pool, 'example.com').length).assertEqual(0);
    });
  });
}
