import { describe, expect, it } from '@ohos/hypium';
import { Base32 } from '../../../main/ets/core/Base32';
import { Base64Url } from '../../../main/ets/core/Base64Url';
import { TotpCalculator } from '../../../main/ets/totp/TotpCalculator';

interface RfcVector {
  timeSeconds: number;
  sha1: string;
  sha256: string;
  sha512: string;
}

/** RFC 6238 附录 B 的标准向量（8 位）。 */
const RFC6238: RfcVector[] = [
  { timeSeconds: 59, sha1: '94287082', sha256: '46119246', sha512: '90693936' },
  { timeSeconds: 1111111109, sha1: '07081804', sha256: '68084774', sha512: '25091201' },
  { timeSeconds: 1111111111, sha1: '14050471', sha256: '67062674', sha512: '99943326' },
  { timeSeconds: 1234567890, sha1: '89005924', sha256: '91819424', sha512: '93441116' },
  { timeSeconds: 2000000000, sha1: '69279037', sha256: '90698825', sha512: '38618901' },
  { timeSeconds: 20000000000, sha1: '65353130', sha256: '77737706', sha512: '47863826' }
];

const SHA1_SECRET = 'GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ';
const SHA256_SECRET = 'GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZA';
const SHA512_SECRET =
  'GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZDGNA';

export default function totpTest(): void {
  describe('TotpCalculator', () => {
    it('RFC6238_SHA1_vectors', 0, () => {
      for (let i = 0; i < RFC6238.length; i += 1) {
        const vector = RFC6238[i];
        const actual = TotpCalculator.generateBase32(SHA1_SECRET, vector.timeSeconds * 1000, {
          algorithm: 'SHA1',
          digits: 8,
          period: 30
        });
        expect(actual).assertEqual(vector.sha1);
      }
    });

    it('RFC6238_SHA256_vectors', 0, () => {
      for (let i = 0; i < RFC6238.length; i += 1) {
        const vector = RFC6238[i];
        const actual = TotpCalculator.generateBase32(SHA256_SECRET, vector.timeSeconds * 1000, {
          algorithm: 'SHA256',
          digits: 8,
          period: 30
        });
        expect(actual).assertEqual(vector.sha256);
      }
    });

    it('RFC6238_SHA512_vectors', 0, () => {
      for (let i = 0; i < RFC6238.length; i += 1) {
        const vector = RFC6238[i];
        const actual = TotpCalculator.generateBase32(SHA512_SECRET, vector.timeSeconds * 1000, {
          algorithm: 'SHA512',
          digits: 8,
          period: 30
        });
        expect(actual).assertEqual(vector.sha512);
      }
    });

    it('six_digits_and_custom_period', 0, () => {
      expect(TotpCalculator.generateBase32(SHA1_SECRET, 59000, {
        algorithm: 'SHA1',
        digits: 6,
        period: 30
      })).assertEqual('287082');
      expect(TotpCalculator.generateBase32(SHA1_SECRET, 59000, {
        algorithm: 'SHA1',
        digits: 6,
        period: 60
      })).assertEqual('755224');
      expect(TotpCalculator.generateBase32(SHA1_SECRET, 1210000, {
        algorithm: 'SHA1',
        digits: 6,
        period: 60
      })).assertEqual(TotpCalculator.generateBase32(SHA1_SECRET, 1210000, {
        algorithm: 'SHA1',
        digits: 6,
        period: 60
      }));
    });

    it('time_step_and_remaining_seconds', 0, () => {
      expect(TotpCalculator.timeStep(59000, 30)).assertEqual(1);
      expect(TotpCalculator.timeStep(60000, 30)).assertEqual(2);
      expect(TotpCalculator.remainingSeconds(59000, 30)).assertEqual(1);
      expect(TotpCalculator.remainingSeconds(60000, 30)).assertEqual(30);
      expect(TotpCalculator.remainingSeconds(30000, 30)).assertEqual(30);
      expect(TotpCalculator.remainingSeconds(45000, 60)).assertEqual(45);
    });
  });

  describe('Base32', () => {
    it('rfc4648_vectors', 0, () => {
      expect(Base32.encode(new Uint8Array([102]))).assertEqual('MY');
      expect(Base32.encode(new Uint8Array([102, 111]))).assertEqual('MZXQ');
      expect(Base32.encode(new Uint8Array([102, 111, 111]))).assertEqual('MZXW6');
      expect(Base32.encode(new Uint8Array([102, 111, 111, 98]))).assertEqual('MZXW6YQ');
      expect(Base32.encode(new Uint8Array([102, 111, 111, 98, 97]))).assertEqual('MZXW6YTB');
      expect(Base32.encode(new Uint8Array([102, 111, 111, 98, 97, 114]))).assertEqual('MZXW6YTBOI');
    });

    it('decode_strict_rejects_padding_and_lowercase', 0, () => {
      let paddingRejected = false;
      try {
        Base32.decodeStrict('MZXW6YTB=');
      } catch (error) {
        paddingRejected = true;
      }
      expect(paddingRejected).assertTrue();

      let lowercaseRejected = false;
      try {
        Base32.decodeStrict('mzxw6ytb');
      } catch (error) {
        lowercaseRejected = true;
      }
      expect(lowercaseRejected).assertTrue();
    });

    it('decode_loose_accepts_padding_space_dash', 0, () => {
      const bytes = Base32.decodeLoose('mzxw 6ytb-oi==');
      expect(bytes.length).assertEqual(6);
      expect(Base32.encode(bytes)).assertEqual('MZXW6YTBOI');
    });
  });

  describe('Base64Url', () => {
    it('encode_decode_without_padding', 0, () => {
      const bytes = new Uint8Array([0xfb, 0xff, 0x00, 0x01, 0x02]);
      const text = Base64Url.encode(bytes);
      expect(text).assertEqual('-_8AAQI');
      const decoded = Base64Url.decode(text);
      expect(decoded.length).assertEqual(bytes.length);
      for (let i = 0; i < bytes.length; i += 1) {
        expect(decoded[i]).assertEqual(bytes[i]);
      }
    });

    it('rejects_padding_and_illegal_length', 0, () => {
      let paddingRejected = false;
      try {
        Base64Url.decode('AAAA=');
      } catch (error) {
        paddingRejected = true;
      }
      expect(paddingRejected).assertTrue();

      let lengthRejected = false;
      try {
        Base64Url.decode('A');
      } catch (error) {
        lengthRejected = true;
      }
      expect(lengthRejected).assertTrue();
    });
  });
}
