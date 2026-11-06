import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { TotpError, TotpErrorCode } from '../core/TotpError';
import { Base32 } from '../core/Base32';
import { DEFAULT_TOTP_OPTIONS, normalizeAlgorithm, TotpOptions } from './TotpOptions';

/**
 * RFC 6238 TOTP / RFC 4226 HOTP。
 *
 * HMAC 由 @kit.CryptoArchitectureKit 提供（HMAC-SHA1/256/512），
 * 不在 SDK 内自实现哈希，避免侧信道与实现偏差。
 */
export class TotpCalculator {
  /** 当前 Unix 毫秒对应的时间步。 */
  static timeStep(epochMs: number, period: number): number {
    TotpCalculator.validatePeriod(period);
    return Math.floor(epochMs / 1000 / period);
  }

  /** 当前时间步剩余秒数（1..period）。 */
  static remainingSeconds(epochMs: number, period: number): number {
    TotpCalculator.validatePeriod(period);
    const seconds = Math.floor(epochMs / 1000);
    const remainder = seconds % period;
    return remainder === 0 ? period : period - remainder;
  }

  /** 按时间戳生成动态码。 */
  static generate(secret: Uint8Array, epochMs: number, options: TotpOptions = DEFAULT_TOTP_OPTIONS): string {
    const step = TotpCalculator.timeStep(epochMs, options.period);
    return TotpCalculator.generateAtStep(secret, step, options);
  }

  /** 按 Base32 密钥生成动态码。 */
  static generateBase32(secretBase32: string, epochMs: number, options: TotpOptions = DEFAULT_TOTP_OPTIONS): string {
    const secret = Base32.decodeLoose(secretBase32);
    return TotpCalculator.generate(secret, epochMs, options);
  }

  /** 指定时间步生成动态码（单测与 RFC 向量使用）。 */
  static generateAtStep(secret: Uint8Array, timeStep: number, options: TotpOptions = DEFAULT_TOTP_OPTIONS): string {
    if (!Number.isInteger(timeStep) || timeStep < 0) {
      throw new TotpError(TotpErrorCode.INVALID_ARGUMENT, 'INVALID_TIME_STEP');
    }
    TotpCalculator.validateOptions(options);
    const digest = TotpCalculator.hmac(secret, TotpCalculator.counterBytes(timeStep), options.algorithm);
    return TotpCalculator.truncate(digest, options.digits);
  }

  /** HMAC 单次计算，供测试与高级调用方使用。 */
  static hmac(secret: Uint8Array, message: Uint8Array, algorithm: string): Uint8Array {
    if (secret.length === 0) {
      throw new TotpError(TotpErrorCode.INVALID_ARGUMENT, 'EMPTY_SECRET');
    }
    const alg = normalizeAlgorithm(algorithm);
    try {
      const keyGenerator = cryptoFramework.createSymKeyGenerator('HMAC');
      const key = keyGenerator.convertKeySync({ data: secret });
      const mac = cryptoFramework.createMac(alg);
      mac.initSync(key);
      mac.updateSync({ data: message });
      return mac.doFinalSync().data;
    } catch (error) {
      throw new TotpError(TotpErrorCode.INTERNAL, 'HMAC_UNAVAILABLE');
    }
  }

  static validateOptions(options: TotpOptions): void {
    normalizeAlgorithm(options.algorithm);
    if (!Number.isInteger(options.digits) || options.digits < 6 || options.digits > 10) {
      throw new TotpError(TotpErrorCode.INVALID_ARGUMENT, 'INVALID_DIGITS');
    }
    TotpCalculator.validatePeriod(options.period);
  }

  private static validatePeriod(period: number): void {
    if (!Number.isInteger(period) || period < 1 || period > 3600) {
      throw new TotpError(TotpErrorCode.INVALID_ARGUMENT, 'INVALID_PERIOD');
    }
  }

  private static counterBytes(timeStep: number): Uint8Array {
    const out = new Uint8Array(8);
    let value = timeStep;
    for (let i = 7; i >= 0; i -= 1) {
      out[i] = value % 256;
      value = Math.floor(value / 256);
    }
    return out;
  }

  /** RFC 4226 §5.3 动态截断。 */
  private static truncate(digest: Uint8Array, digits: number): string {
    const offset = digest[digest.length - 1] & 0x0f;
    const binary =
      ((digest[offset] & 0x7f) * 16777216) +
      ((digest[offset + 1] & 0xff) * 65536) +
      ((digest[offset + 2] & 0xff) * 256) +
      (digest[offset + 3] & 0xff);
    let modulus = 1;
    for (let i = 0; i < digits; i += 1) {
      modulus *= 10;
    }
    let code = String(binary % modulus);
    while (code.length < digits) {
      code = '0' + code;
    }
    return code;
  }
}
