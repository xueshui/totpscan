import totpTest from './Totp.test';
import addressTest from './Address.test';
import otpauthTest from './Otpauth.test';
import payloadTest from './Payload.test';
import candidateTest from './Candidate.test';

export default function testsuite(): void {
  totpTest();
  addressTest();
  otpauthTest();
  payloadTest();
  candidateTest();
}
