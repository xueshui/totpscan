/**
 * totpscan HAR 公开入口。
 *
 * 第三方集成：在 oh-package.json5 中声明 `"totpscan": "file:../totpscan"`，
 * 然后 `import { TotpScanClient, TotpCalculator, OtpauthUri } from 'totpscan';`。
 */
export { TotpScanClient } from './src/main/ets/client/TotpScanClient';
export { TotpScanConfig, DEFAULT_TOTP_SCAN_CONFIG } from './src/main/ets/client/TotpScanConfig';
export { TotpError, TotpErrorCode } from './src/main/ets/core/TotpError';
export { Base32 } from './src/main/ets/core/Base32';
export { Base64Url } from './src/main/ets/core/Base64Url';
export { TotpCalculator } from './src/main/ets/totp/TotpCalculator';
export { TotpOptions, DEFAULT_TOTP_OPTIONS } from './src/main/ets/totp/TotpOptions';
export { OtpauthUri } from './src/main/ets/totp/OtpauthUri';
export { CanonicalUrl } from './src/main/ets/security/CanonicalUrl';
export { RegisteredDomain } from './src/main/ets/security/RegisteredDomain';
export { PinnedUrl, PinnedUrlParts } from './src/main/ets/security/PinnedUrl';
export { AddressMatcher, MatchDecision } from './src/main/ets/security/AddressMatcher';
export { CandidateResolver, CandidateMatch } from './src/main/ets/security/CandidateResolver';
export { PinnedEndpoint } from './src/main/ets/security/PinnedEndpoint';
export { BindingPayload } from './src/main/ets/qr/BindingPayload';
export { LoginPayload } from './src/main/ets/qr/LoginPayload';
export {
  BindingPreview,
  BindOutcome,
  LoginPreview,
  LoginCandidate,
  LoginResult,
  CodeSnapshot,
  ClockStatus,
  TrustedSite
} from './src/main/ets/model/Models';
export {
  AccountKind,
  AccountView,
  StandardAccountInput,
  StoredAccount,
  LoginFailureKind
} from './src/main/ets/model/Types';
export { BiometricGate } from './src/main/ets/security/BiometricGate';
