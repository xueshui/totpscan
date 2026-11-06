import { TotpError, TotpErrorCode } from '../core/TotpError';
import { PinnedEndpoint } from '../security/PinnedEndpoint';
import { ClockService } from '../clock/ClockService';
import { HttpClient, HttpResult } from './HttpClient';

export enum SubmitOutcome {
  OK = 'ok',
  REJECTED = 'rejected',
  RATE_LIMITED = 'rate_limited',
  INVALID = 'invalid',
  RETRY_LATER = 'retry_later'
}

export interface SubmitResult {
  outcome: SubmitOutcome;
  status: number;
  serverTimeMs: number;
}

/**
 * 提交层。
 *
 * 只接受 PinnedEndpoint（已确认的固化地址），没有 URL 字符串入参，
 * 因此登录二维码中的 `url` 无法被传入这里。
 */
export class Submitter {
  private readonly clock: ClockService;
  private readonly timeoutMs: number;

  constructor(clock: ClockService, timeoutMs: number) {
    this.clock = clock;
    this.timeoutMs = timeoutMs;
  }

  /**
   * POST 到固化地址本身（不做任何路径拼接/重定向）。
   *
   * body 固定为 `{"code":"123456","token":"..."}`；不再发送 scan_token / account / device_id。
   */
  async verify(pinned: PinnedEndpoint, token: string, code: string): Promise<SubmitResult> {
    if (token.length === 0) {
      throw new TotpError(TotpErrorCode.INVALID_ARGUMENT, 'TOKEN_FIELD_INVALID');
    }
    const body = JSON.stringify({
      code: code,
      token: token
    });
    const response = await HttpClient.postJson(pinned.canonicalUrl, body, this.timeoutMs);
    this.clock.updateFromServer(response.serverTimeMs);
    return Submitter.mapResponse(response);
  }

  /** 绑定确认：固定路径拼在固化地址的 origin 上，绝不使用二维码地址。 */
  async confirmBinding(pinned: PinnedEndpoint, bindingId: string, code: string): Promise<SubmitResult> {
    if (!new RegExp('^b_[A-Za-z0-9_-]{16,64}$').test(bindingId)) {
      throw new TotpError(TotpErrorCode.INVALID_ARGUMENT, 'BINDING_ID_INVALID');
    }
    const url = `${pinned.origin}/totp/v1/bindings/${encodeURIComponent(bindingId)}/confirm`;
    const body = JSON.stringify({ code: code });
    const response = await HttpClient.postJson(url, body, this.timeoutMs);
    this.clock.updateFromServer(response.serverTimeMs);
    return Submitter.mapResponse(response);
  }

  private static mapResponse(response: HttpResult): SubmitResult {
    let outcome = SubmitOutcome.RETRY_LATER;
    if (response.status >= 200 && response.status < 300) {
      outcome = SubmitOutcome.OK;
    } else if (response.status === 400) {
      outcome = SubmitOutcome.INVALID;
    } else if (response.status === 401 || response.status === 403 || response.status === 404) {
      outcome = SubmitOutcome.REJECTED;
    } else if (response.status === 429) {
      outcome = SubmitOutcome.RATE_LIMITED;
    } else if (response.status >= 300 && response.status < 400) {
      // 不跟随重定向：3xx 一律按失败处理。
      outcome = SubmitOutcome.RETRY_LATER;
    }
    return {
      outcome: outcome,
      status: response.status,
      serverTimeMs: response.serverTimeMs
    };
  }
}
