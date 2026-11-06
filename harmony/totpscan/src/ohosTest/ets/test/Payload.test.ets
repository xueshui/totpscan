import { describe, expect, it } from '@ohos/hypium';
import { TotpError, TotpErrorCode } from '../../../main/ets/core/TotpError';
import { BindingPayload, ParsedBinding } from '../../../main/ets/qr/BindingPayload';
import { LoginPayload, ParsedLogin } from '../../../main/ets/qr/LoginPayload';
import { TotpCalculator } from '../../../main/ets/totp/TotpCalculator';

/**
 * 绑定载荷：`dom` + `path`，不含签名。
 */
const BIND_SHA1 =
  '{"t":"totp-bind","v":1,"bid":"b_3nS0kq9uV2xJ0mQw1sT4aA","iss":"Example Corp","acc":"alice@example.com",' +
  '"sec":"GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ","alg":"SHA1","dig":6,"per":30,' +
  '"dom":"dkn.example.com","path":"/dtm/ulr?ma=xxx","iat":1762396800}';

const BIND_SHA256 =
  '{"t":"totp-bind","v":1,"bid":"b_9xQ2mK7nR4tY1pL8sV5wZ3c","iss":"Example Corp","acc":"bob@example.com",' +
  '"sec":"GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZA","alg":"SHA256","dig":8,"per":60,' +
  '"dom":"auth.example.com","path":"/totp/v1/verify","iat":1762396800}';

const LOGIN_TOKEN_16 = 'AbCdEfGhIjKlMnOp';
const LOGIN_TOKEN_24 = 'AbCdEfGhIjKlMnOpQrStUvWx';
const LOGIN_OK =
  '{"t":"totp-login","v":1,"url":"dkn.example.com","token":"' + LOGIN_TOKEN_16 + '","exp":1762396860}';
const NOW = 1762396800;

function expectCode(action: () => void, code: TotpErrorCode): void {
  let actual = '';
  try {
    action();
    actual = 'NO_ERROR';
  } catch (error) {
    actual = (error as TotpError).code;
  }
  expect(actual).assertEqual(code);
}

export default function payloadTest(): void {
  describe('BindingPayload', () => {
    it('parses_dom_and_path_without_signature', 0, () => {
      const parsed: ParsedBinding = BindingPayload.parse(BIND_SHA1, NOW + 100);
      expect(parsed.bindingId).assertEqual('b_3nS0kq9uV2xJ0mQw1sT4aA');
      expect(parsed.issuer).assertEqual('Example Corp');
      expect(parsed.account).assertEqual('alice@example.com');
      expect(parsed.secretBase32).assertEqual('GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ');
      expect(parsed.algorithm).assertEqual('SHA1');
      expect(parsed.digits).assertEqual(6);
      expect(parsed.period).assertEqual(30);
      expect(parsed.submitUrl).assertEqual('https://dkn.example.com/dtm/ulr?ma=xxx');
      expect(parsed.registeredDomain).assertEqual('example.com');
      expect(parsed.pathQuery).assertEqual('/dtm/ulr?ma=xxx');
      expect(parsed.expiresAt).assertEqual(-1);
    });

    it('derives_code_from_parsed_secret', 0, () => {
      const parsed = BindingPayload.parse(BIND_SHA1, NOW);
      const code = TotpCalculator.generate(parsed.secret, NOW * 1000, {
        algorithm: parsed.algorithm,
        digits: parsed.digits,
        period: parsed.period
      });
      expect(code).assertEqual('425909');
      const parsedSha256 = BindingPayload.parse(BIND_SHA256, NOW);
      expect(TotpCalculator.generate(parsedSha256.secret, NOW * 1000, {
        algorithm: parsedSha256.algorithm,
        digits: parsedSha256.digits,
        period: parsedSha256.period
      })).assertEqual('91878276');
    });

    it('rejects_expired_binding', 0, () => {
      const expired = BIND_SHA1.replace('"iat":1762396800', '"iat":1762396800,"exp":1762396800');
      expectCode(() => BindingPayload.parse(expired, NOW + 1), TotpErrorCode.QR_EXPIRED);
    });

    it('ignores_unknown_fields_including_legacy_sig_and_kid', 0, () => {
      const withExtra = BIND_SHA1.replace('"iat":', '"sig":"ignored","kid":"ignored","sub":"https://evil.example/x","iat":');
      const parsed = BindingPayload.parse(withExtra, NOW);
      expect(parsed.account).assertEqual('alice@example.com');
      expect(parsed.submitUrl).assertEqual('https://dkn.example.com/dtm/ulr?ma=xxx');
    });

    it('rejects_structurally_invalid_payloads', 0, () => {
      expectCode(() => BindingPayload.parse('not json', NOW), TotpErrorCode.INVALID_QR);
      expectCode(() => BindingPayload.parse(BIND_SHA1.replace('"v":1', '"v":2'), NOW),
        TotpErrorCode.UNSUPPORTED_VERSION);
      expectCode(() => BindingPayload.parse(BIND_SHA1.replace('"t":"totp-bind"', '"t":"totp-login"'), NOW),
        TotpErrorCode.INVALID_QR);
      expectCode(() => BindingPayload.parse(BIND_SHA1.replace('"dig":6', '"dig":7'), NOW),
        TotpErrorCode.INVALID_QR);
      expectCode(() => BindingPayload.parse(BIND_SHA1.replace('"per":30', '"per":45'), NOW),
        TotpErrorCode.INVALID_QR);
      expectCode(() => BindingPayload.parse(
        BIND_SHA1.replace('"sec":"GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ"', '"sec":"JBSWY3DPEHPK3PXP"'), NOW),
        TotpErrorCode.INVALID_QR);
    });

    it('rejects_invalid_dom_or_path', 0, () => {
      expectCode(() => BindingPayload.parse(
        BIND_SHA1.replace('"dom":"dkn.example.com"', '"dom":"https://dkn.example.com"'), NOW),
        TotpErrorCode.INVALID_QR);
      expectCode(() => BindingPayload.parse(
        BIND_SHA1.replace('"dom":"dkn.example.com"', '"dom":"dkn.example.com/x"'), NOW),
        TotpErrorCode.INVALID_QR);
      expectCode(() => BindingPayload.parse(
        BIND_SHA1.replace('"path":"/dtm/ulr?ma=xxx"', '"path":"dtm/ulr?ma=xxx"'), NOW),
        TotpErrorCode.INVALID_QR);
    });
  });

  describe('LoginPayload', () => {
    it('parses_url_token_and_exp', 0, () => {
      const parsed: ParsedLogin = LoginPayload.parse(LOGIN_OK, NOW);
      expect(parsed.domain).assertEqual('dkn.example.com');
      expect(parsed.registeredDomain).assertEqual('example.com');
      expect(parsed.token).assertEqual(LOGIN_TOKEN_16);
      expect(parsed.expiresAt).assertEqual(1762396860);
    });

    it('accepts_24_char_token', 0, () => {
      const parsed = LoginPayload.parse(
        LOGIN_OK.replace(LOGIN_TOKEN_16, LOGIN_TOKEN_24), NOW);
      expect(parsed.token).assertEqual(LOGIN_TOKEN_24);
    });

    it('rejects_invalid_token_length', 0, () => {
      expectCode(() => LoginPayload.parse(
        LOGIN_OK.replace(LOGIN_TOKEN_16, 'AbCdEfGhIjKlMnO'), NOW), TotpErrorCode.INVALID_QR);
      expectCode(() => LoginPayload.parse(
        LOGIN_OK.replace(LOGIN_TOKEN_16, 'AbCdEfGhIjKlMnOpQrStUvW'), NOW), TotpErrorCode.INVALID_QR);
    });

    it('rejects_domain_with_scheme_path_or_port', 0, () => {
      expectCode(() => LoginPayload.parse(
        LOGIN_OK.replace('"url":"dkn.example.com"', '"url":"https://dkn.example.com"'), NOW), TotpErrorCode.INVALID_QR);
      expectCode(() => LoginPayload.parse(
        LOGIN_OK.replace('"url":"dkn.example.com"', '"url":"dkn.example.com/login"'), NOW), TotpErrorCode.INVALID_QR);
      expectCode(() => LoginPayload.parse(
        LOGIN_OK.replace('"url":"dkn.example.com"', '"url":"dkn.example.com:8443"'), NOW), TotpErrorCode.INVALID_QR);
      expectCode(() => LoginPayload.parse(
        LOGIN_OK.replace('"url":"dkn.example.com"', '"url":"user@dkn.example.com"'), NOW), TotpErrorCode.INVALID_QR);
    });

    it('rejects_expired_and_overlong_ttl', 0, () => {
      expectCode(() => LoginPayload.parse(LOGIN_OK, NOW + 61), TotpErrorCode.LOGIN_EXPIRED);
      const ttl61 = LOGIN_OK.replace('"exp":1762396860', '"exp":1762396861');
      expectCode(() => LoginPayload.parse(ttl61, NOW), TotpErrorCode.INVALID_QR);
    });

    it('rejects_wrong_type_or_version', 0, () => {
      expectCode(() => LoginPayload.parse(LOGIN_OK.replace('"t":"totp-login"', '"t":"totp-bind"'), NOW),
        TotpErrorCode.INVALID_QR);
      expectCode(() => LoginPayload.parse(LOGIN_OK.replace('"v":1', '"v":2'), NOW),
        TotpErrorCode.UNSUPPORTED_VERSION);
    });
  });
}
