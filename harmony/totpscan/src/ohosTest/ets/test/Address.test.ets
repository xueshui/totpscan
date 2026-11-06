import { describe, expect, it } from '@ohos/hypium';
import { AddressMatcher } from '../../../main/ets/security/AddressMatcher';
import { CanonicalUrl } from '../../../main/ets/security/CanonicalUrl';
import { PinnedEndpoint } from '../../../main/ets/security/PinnedEndpoint';
import { TotpError, TotpErrorCode } from '../../../main/ets/core/TotpError';

interface MatchCase {
  pinned: string;
  candidate: string;
  expected: boolean;
  reason: string;
}

/**
 * 注册域名 + path/query 前缀判定（path 原样保留，不做归一化）。
 */
const MATCH_CASES: MatchCase[] = [
  {
    pinned: 'https://auth.example.com/totp/v1/verify',
    candidate: 'https://Auth.Example.com:443/totp/v1/verify/',
    expected: true,
    reason: 'host 小写、去默认端口；路径段前缀允许尾斜杠'
  },
  {
    pinned: 'https://auth.example.com/totp/v1',
    candidate: 'https://auth.example.com/totp/v1/verify',
    expected: true,
    reason: '路径段前缀'
  },
  {
    pinned: 'https://auth.example.com/totp/v1',
    candidate: 'https://auth.example.com/totp/v10/verify',
    expected: false,
    reason: '非 / 段边界'
  },
  {
    pinned: 'https://auth.example.com/totp/v1',
    candidate: 'https://auth.example.com.evil.com/totp/v1',
    expected: false,
    reason: '注册域名不等'
  },
  {
    pinned: 'https://auth.example.com/totp/v1',
    candidate: 'http://auth.example.com/totp/v1',
    expected: false,
    reason: 'scheme 不等'
  },
  {
    pinned: 'https://auth.example.com/totp/v1',
    candidate: 'https://auth.example.com:8443/totp/v1',
    expected: false,
    reason: '端口不等'
  },
  {
    pinned: 'https://auth.example.com/totp/v1',
    candidate: 'https://auth.example.com/totp/v1/../v2',
    expected: true,
    reason: 'path 原样保留，不消解 . / ..'
  },
  {
    pinned: 'https://auth.example.com/totp/v1',
    candidate: 'https://auth.example.com//totp//v1/',
    expected: false,
    reason: 'path 原样保留，不合并斜杠'
  },
  {
    pinned: 'https://auth.example.com',
    candidate: 'https://auth.example.com/anything',
    expected: true,
    reason: '裸源宽松'
  },
  {
    pinned: 'https://auth.example.com/totp/v1',
    candidate: 'https://user:pw@auth.example.com/totp/v1',
    expected: false,
    reason: 'userinfo 拒绝'
  },
  {
    pinned: 'https://auth.example.com/totp/v1',
    candidate: 'https://auth.example.com/totp/v1?x=1',
    expected: true,
    reason: '钉住无查询串时允许追加查询串'
  },
  {
    pinned: 'https://auth.example.com/totp/v1?x=1',
    candidate: 'https://auth.example.com/totp/v1?x=1&y=2',
    expected: true,
    reason: '查询串按参数边界扩展'
  },
  {
    pinned: 'https://auth.example.com/totp/v1?x=1',
    candidate: 'https://auth.example.com/totp/v1?x=12',
    expected: false,
    reason: '查询参数值不同'
  },
  {
    pinned: 'https://dkn.example.com/dtm/ulr?ma=xxx',
    candidate: 'https://other.example.com/dtm/ulr?ma=xxx',
    expected: true,
    reason: '同注册域名、路径相同'
  },
  {
    pinned: 'https://dkn.example.com/dtm/ulr?ma=xxx',
    candidate: 'https://dkn.example.com/dtm/ulr?ma=xxx&n=1',
    expected: true,
    reason: '同注册域名、路径前缀 + 查询串扩展'
  }
];

interface CanonicalCase {
  input: string;
  expected: string;
}

const CANONICAL_OK: CanonicalCase[] = [
  { input: 'https://Auth.Example.com:443/totp/v1/verify/', expected: 'https://auth.example.com/totp/v1/verify' },
  { input: 'https://auth.example.com', expected: 'https://auth.example.com/' },
  { input: 'https://auth.example.com:8443/a', expected: 'https://auth.example.com:8443/a' },
  { input: 'https://auth.example.com//totp//v1/', expected: 'https://auth.example.com/totp/v1' },
  { input: 'https://auth.example.com/totp/v1/../v2', expected: 'https://auth.example.com/totp/v2' },
  { input: 'https://auth.example.com/totp/./v1', expected: 'https://auth.example.com/totp/v1' },
  { input: 'https://auth.example.com/%7euser/%2f', expected: 'https://auth.example.com/~user/%2F' },
  { input: 'https://[0:0:0:0:0:0:0:1]:443/x', expected: 'https://[::1]/x' },
  { input: 'https://例子.测试/a', expected: 'https://xn--fsqu00a.xn--0zwm56d/a' },
  { input: 'http://localhost:8080/totp', expected: 'http://localhost:8080/totp' },
  { input: 'http://127.0.0.1/totp', expected: 'http://127.0.0.1/totp' }
];

const INVALID_URLS: string[] = [
  '',
  ' https://a.example/x',
  'https://a.example/x ',
  'https://a.example/a b',
  'https://a.example\\x',
  'ftp://a.example/x',
  'http://a.example/x',
  'https://user:pw@a.example/x',
  'https://a.example/x?y=1',
  'https://a.example/x#frag',
  'https://a.example:0/x',
  'https://a.example:99999/x',
  'https://a.example:abc/x',
  'https://a.example/%zz',
  'https://a.example/%2',
  'https:///x',
  'https://a.example:'
];

export default function addressTest(): void {
  describe('CanonicalUrl', () => {
    it('C1_C7_canonical_forms', 0, () => {
      for (let i = 0; i < CANONICAL_OK.length; i += 1) {
        expect(CanonicalUrl.canonicalize(CANONICAL_OK[i].input)).assertEqual(CANONICAL_OK[i].expected);
      }
    });

    it('C1_C7_rejects_ambiguous_inputs', 0, () => {
      for (let i = 0; i < INVALID_URLS.length; i += 1) {
        let rejected = false;
        try {
          CanonicalUrl.canonicalize(INVALID_URLS[i]);
        } catch (error) {
          rejected = true;
        }
        expect(rejected).assertTrue();
      }
    });
  });

  describe('AddressMatcher', () => {
    it('registered_domain_and_path_prefix', 0, () => {
      for (let i = 0; i < MATCH_CASES.length; i += 1) {
        const item = MATCH_CASES[i];
        const actual = AddressMatcher.matches(item.pinned, item.candidate);
        expect(actual).assertEqual(item.expected);
      }
    });

    it('never_uses_suffix_or_contains_matching', 0, () => {
      expect(AddressMatcher.matches(
        'https://auth.example.com/totp/v1',
        'https://auth.example.com/totp/v1.evil.com'
      )).assertFalse();
      expect(AddressMatcher.matches(
        'https://auth.example.com/totp/v1',
        'https://auth.example.com/totp/v1-other'
      )).assertFalse();
      expect(AddressMatcher.matches(
        'https://auth.example.com/totp/v1',
        'https://auth.example.com/totp'
      )).assertFalse();
      expect(AddressMatcher.matches(
        'https://auth.example.com/totp/v1',
        'https://auth.example.com/totp/v1/verify?x=1'
      )).assertTrue();
    });

    it('loose_source_only_when_pinned_path_is_root', 0, () => {
      const loose = AddressMatcher.evaluate('https://auth.example.com/', 'https://auth.example.com/a/b');
      expect(loose.matched).assertTrue();
      expect(loose.looseSource).assertTrue();

      const strict = AddressMatcher.evaluate('https://auth.example.com/totp', 'https://auth.example.com/a/b');
      expect(strict.matched).assertFalse();
    });
  });

  describe('PinnedEndpoint', () => {
    it('from_stored_requires_canonical_form', 0, () => {
      let rejected = false;
      try {
        PinnedEndpoint.fromStored('https://Auth.Example.com/totp/v1');
      } catch (error) {
        rejected = (error as TotpError).code === TotpErrorCode.SECURE_STORAGE_ERROR;
      }
      expect(rejected).assertTrue();
    });

    it('keeps_path_and_query_verbatim', 0, () => {
      const endpoint = PinnedEndpoint.fromStored('https://dkn.example.com/dtm/ulr?ma=xxx');
      expect(endpoint.canonicalUrl).assertEqual('https://dkn.example.com/dtm/ulr?ma=xxx');
      expect(endpoint.registeredDomain).assertEqual('example.com');
      expect(endpoint.pathQuery).assertEqual('/dtm/ulr?ma=xxx');
    });
  });
}
