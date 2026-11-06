import { http } from '@kit.NetworkKit';
import { TotpError, TotpErrorCode } from '../core/TotpError';

export interface HttpResult {
  status: number;
  body: string;
  /** 响应 Date 头对应的毫秒时间；无法解析时为 0。 */
  serverTimeMs: number;
}

/**
 * HTTPS 客户端。
 *
 * - 使用系统默认证书校验，不提供任何自定义 CA / 信任所有证书的入口；
 * - 不跟随 3xx（调用方只接受 2xx；3xx 一律按失败处理）；
 * - 只接收已固化的 URL（由调用方/Submitter 传入）；
 * - 不打印 URL、请求体或响应体。
 */
export class HttpClient {
  static async postJson(url: string, body: string, timeoutMs: number): Promise<HttpResult> {
    const request = http.createHttp();
    try {
      const response = await request.request(url, {
        method: http.RequestMethod.POST,
        header: {
          'Content-Type': 'application/json',
          'Accept': 'application/json'
        },
        extraData: body,
        connectTimeout: timeoutMs,
        readTimeout: timeoutMs,
        usingCache: false,
        expectDataType: http.HttpDataType.STRING
      });
      return {
        status: response.responseCode,
        body: HttpClient.bodyToString(response.result),
        serverTimeMs: HttpClient.readDateHeader(response.header)
      };
    } catch (error) {
      throw new TotpError(TotpErrorCode.NETWORK_ERROR, 'HTTP_REQUEST_FAILED');
    } finally {
      request.destroy();
    }
  }

  /** 仅用于校时：GET 一个固定路径，不提交任何数据。 */
  static async getServerTime(url: string, timeoutMs: number): Promise<number> {
    const request = http.createHttp();
    try {
      const response = await request.request(url, {
        method: http.RequestMethod.GET,
        header: {
          'Accept': 'application/json'
        },
        connectTimeout: timeoutMs,
        readTimeout: timeoutMs,
        usingCache: false,
        expectDataType: http.HttpDataType.STRING
      });
      return HttpClient.readDateHeader(response.header);
    } catch (error) {
      throw new TotpError(TotpErrorCode.NETWORK_ERROR, 'HTTP_TIME_PROBE_FAILED');
    } finally {
      request.destroy();
    }
  }

  private static bodyToString(result: string | Object | ArrayBuffer): string {
    if (typeof result === 'string') {
      return result as string;
    }
    return '';
  }

  private static readDateHeader(header: Object): number {
    if (header === undefined || header === null || typeof header !== 'object') {
      return 0;
    }
    const record = header as Record<string, string>;
    const candidates: string[] = ['date', 'Date'];
    for (let i = 0; i < candidates.length; i += 1) {
      const value: string | undefined = record[candidates[i]];
      if (value !== undefined && typeof value === 'string') {
        const parsed = Date.parse(value);
        if (Number.isFinite(parsed) && parsed > 0) {
          return parsed;
        }
      }
    }
    return 0;
  }
}
