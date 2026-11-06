import { PinnedUrl, PinnedUrlParts } from './PinnedUrl';
import { TotpError, TotpErrorCode } from '../core/TotpError';

/**
 * 已确认的固化提交地址。
 *
 * 与旧实现的区别：完整保留 path 与查询串（如 `/dtm/ulr?ma=xxx`），
 * 并附带 PSL 级注册域名，供登录候选与提交前门禁复用。
 *
 * 该类没有公开构造器，也没有接受“任意 URL 字符串”的提交入口：
 * - `fromVerifiedBinding`：仅在绑定二维码解析通过后调用；
 * - `fromStored`：只接受已写入安全存储的完整地址。
 */
export class PinnedEndpoint {
  /** 完整提交地址（含 path+query），提交时原样使用。 */
  readonly canonicalUrl: string;
  readonly origin: string;
  readonly path: string;
  readonly query: string;
  readonly pathQuery: string;
  /** PSL 级注册域名，例如 `example.com`。 */
  readonly registeredDomain: string;
  /** 固化为裸源（路径 `/` 且无查询串）。 */
  readonly looseSource: boolean;

  private constructor(parts: PinnedUrlParts) {
    this.canonicalUrl = parts.full;
    this.origin = parts.origin;
    this.path = parts.path;
    this.query = parts.query;
    this.pathQuery = parts.pathQuery;
    this.registeredDomain = parts.registeredDomain;
    this.looseSource = parts.path === '/' && parts.query.length === 0;
  }

  /** 绑定二维码解析通过后调用；内部再次解析，失败即拒绝。 */
  static fromVerifiedBinding(submitUrl: string): PinnedEndpoint {
    try {
      return new PinnedEndpoint(PinnedUrl.parse(submitUrl));
    } catch (error) {
      throw new TotpError(TotpErrorCode.INSECURE_ADDRESS, 'BINDING_SUBMIT_URL_INVALID', '绑定二维码中的服务器地址不安全，已拒绝');
    }
  }

  /** 从安全存储读取；地址损坏时返回明确错误，绝不降级为其他地址。 */
  static fromStored(fullUrl: string): PinnedEndpoint {
    let parts: PinnedUrlParts;
    try {
      parts = PinnedUrl.parse(fullUrl);
    } catch (error) {
      throw new TotpError(TotpErrorCode.SECURE_STORAGE_ERROR, 'PINNED_ADDRESS_CORRUPTED', '本地固化地址已损坏，请重新绑定');
    }
    const endpoint = new PinnedEndpoint(parts);
    if (endpoint.canonicalUrl !== fullUrl) {
      throw new TotpError(TotpErrorCode.SECURE_STORAGE_ERROR, 'PINNED_ADDRESS_NOT_CANONICAL', '本地固化地址格式异常，请重新绑定');
    }
    return endpoint;
  }
}
