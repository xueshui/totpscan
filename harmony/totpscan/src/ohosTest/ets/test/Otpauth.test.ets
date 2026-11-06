import { describe, expect, it } from '@ohos/hypium';
import { TotpError, TotpErrorCode } from '../../../main/ets/core/TotpError';
import { OtpauthUri } from '../../../main/ets/totp/OtpauthUri';
import { StandardAccountInput } from '../../../main/ets/model/Types';

function expectInvalid(uri: string): void {
  let actual = '';
  try {
    OtpauthUri.parse(uri);
    actual = 'NO_ERROR';
  } catch (error) {
    actual = (error as TotpError).code;
  }
  expect(actual).assertEqual(TotpErrorCode.INVALID_ARGUMENT);
}

/** 规范 §13.2 U1–U8 与 TC-23。 */
export default function otpauthTest(): void {
  describe('OtpauthUri', () => {
    it('parses_full_uri_with_all_parameters', 0, () => {
      const input = OtpauthUri.parse(
        'otpauth://totp/Example%20Corp:alice%40example.com' +
        '?secret=GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ&issuer=Example%20Corp' +
        '&algorithm=SHA256&digits=8&period=60'
      );
      expect(input.issuer).assertEqual('Example Corp');
      expect(input.account).assertEqual('alice@example.com');
      expect(input.secretBase32).assertEqual('GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ');
      expect(input.algorithm).assertEqual('SHA256');
      expect(input.digits).assertEqual(8);
      expect(input.period).assertEqual(60);
    });

    it('applies_defaults', 0, () => {
      const input = OtpauthUri.parse('otpauth://totp/alice?secret=GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ');
      expect(input.issuer).assertEqual('');
      expect(input.account).assertEqual('alice');
      expect(input.algorithm).assertEqual('SHA1');
      expect(input.digits).assertEqual(6);
      expect(input.period).assertEqual(30);
    });

    it('accepts_lowercase_algorithm_and_custom_period', 0, () => {
      const input = OtpauthUri.parse(
        'otpauth://totp/alice?secret=GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ&algorithm=sha512&period=15'
      );
      expect(input.algorithm).assertEqual('SHA512');
      expect(input.period).assertEqual(15);
    });

    it('rejects_issuer_conflict', 0, () => {
      expectInvalid('otpauth://totp/Corp%20A:alice?secret=GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ&issuer=Corp%20B');
    });

    it('rejects_duplicate_parameters', 0, () => {
      expectInvalid('otpauth://totp/alice?secret=GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ&secret=GEZDGNBVGY3TQOJQ');
      expectInvalid('otpauth://totp/alice?secret=GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ&period=30&period=60');
    });

    it('rejects_hotp_counter_and_bad_digits', 0, () => {
      expectInvalid('otpauth://hotp/alice?secret=GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ&counter=1');
      expectInvalid('otpauth://totp/alice?secret=GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ&counter=1');
      expectInvalid('otpauth://totp/alice?secret=GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ&digits=7');
      expectInvalid('otpauth://totp/alice?secret=GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ&digits=abc');
      expectInvalid('otpauth://totp/alice?secret=GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ&period=0');
      expectInvalid('otpauth://totp/alice?secret=GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ&period=3601');
    });

    it('rejects_weak_or_malformed_secret', 0, () => {
      expectInvalid('otpauth://totp/alice?secret=JBSWY3DP');
      expectInvalid('otpauth://totp/alice?secret=!!!!');
      expectInvalid('otpauth://totp/alice');
    });

    it('build_and_parse_roundtrip', 0, () => {
      const input: StandardAccountInput = {
        issuer: 'Example Corp',
        account: 'alice@example.com',
        secretBase32: 'GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ',
        algorithm: 'SHA1',
        digits: 6,
        period: 30,
        note: '公司邮箱'
      };
      const uri = OtpauthUri.build(input);
      // 备注只存本地，绝不进入 otpauth URI。
      expect(uri.indexOf(encodeURIComponent('公司邮箱'))).assertEqual(-1);
      expect(uri.indexOf('note') < 0).assertTrue();
      const parsed = OtpauthUri.parse(uri);
      expect(parsed.issuer).assertEqual('Example Corp');
      expect(parsed.account).assertEqual('alice@example.com');
      expect(parsed.secretBase32).assertEqual('GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ');
      expect(parsed.algorithm).assertEqual('SHA1');
      expect(parsed.digits).assertEqual(6);
      expect(parsed.period).assertEqual(30);
    });
  });
}
