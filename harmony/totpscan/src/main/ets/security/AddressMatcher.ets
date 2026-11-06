import { PinnedUrl, PinnedUrlParts } from './PinnedUrl';

/** 比对结论。拒绝时 reason 只用于开发排查，不展示实现细节给用户。 */
export interface MatchDecision {
  matched: boolean;
  reason: string;
  /** 钉住地址的完整形式（含 path+query）。 */
  pinnedCanonical: string;
  /** 登录二维码地址的完整形式；解析失败时为空串。 */
  candidateCanonical: string;
  /** 钉住的是裸源（路径为 `/` 且无查询串）。 */
  looseSource: boolean;
  /** 钉住的注册域名。 */
  pinnedDomain: string;
}

/**
 * 「注册域名 + 提交路径前缀」比对。
 *
 * 规则（与绑定/登录两侧共用，唯一实现）：
 * 1. scheme 与端口必须相同；
 * 2. 候选 host 的注册域名（PSL 级）必须等于钉住域名；
 * 3. 候选 path+query 必须在钉住前缀之内，路径按 `/` 段边界，查询串按参数边界；
 * 4. 不再要求整条 URL 相等，也不使用 host 全等。
 *
 * 相似域名只由绑定确认界面做提示，不在这里拦截。
 */
export class AddressMatcher {
  static evaluate(pinnedRaw: string, candidateRaw: string): MatchDecision {
    let pinnedParts: PinnedUrlParts;
    try {
      pinnedParts = PinnedUrl.parse(pinnedRaw);
    } catch (error) {
      return {
        matched: false,
        reason: 'PINNED_ADDRESS_INVALID',
        pinnedCanonical: '',
        candidateCanonical: '',
        looseSource: false,
        pinnedDomain: ''
      };
    }
    const looseSource = pinnedParts.path === '/' && pinnedParts.query.length === 0;
    let candidateParts: PinnedUrlParts;
    try {
      candidateParts = PinnedUrl.parse(candidateRaw);
    } catch (error) {
      return {
        matched: false,
        reason: 'CANDIDATE_ADDRESS_INVALID',
        pinnedCanonical: pinnedParts.full,
        candidateCanonical: '',
        looseSource: looseSource,
        pinnedDomain: pinnedParts.registeredDomain
      };
    }

    if (pinnedParts.scheme !== candidateParts.scheme) {
      return AddressMatcher.reject('SCHEME_MISMATCH', pinnedParts, candidateParts, looseSource);
    }
    if (pinnedParts.port !== candidateParts.port) {
      return AddressMatcher.reject('PORT_MISMATCH', pinnedParts, candidateParts, looseSource);
    }
    if (pinnedParts.registeredDomain.length === 0 ||
      pinnedParts.registeredDomain !== candidateParts.registeredDomain) {
      return AddressMatcher.reject('REGISTERED_DOMAIN_MISMATCH', pinnedParts, candidateParts, looseSource);
    }
    if (!PinnedUrl.matchesPrefix(pinnedParts, candidateParts)) {
      return AddressMatcher.reject('PATH_OR_QUERY_MISMATCH', pinnedParts, candidateParts, looseSource);
    }
    return {
      matched: true,
      reason: looseSource ? 'MATCH_LOOSE_SOURCE' : 'MATCH_REGISTERED_DOMAIN_AND_PATH',
      pinnedCanonical: pinnedParts.full,
      candidateCanonical: candidateParts.full,
      looseSource: looseSource,
      pinnedDomain: pinnedParts.registeredDomain
    };
  }

  static matches(pinnedRaw: string, candidateRaw: string): boolean {
    return AddressMatcher.evaluate(pinnedRaw, candidateRaw).matched;
  }

  private static reject(
    reason: string,
    pinned: PinnedUrlParts,
    candidate: PinnedUrlParts,
    loose: boolean
  ): MatchDecision {
    return {
      matched: false,
      reason: reason,
      pinnedCanonical: pinned.full,
      candidateCanonical: candidate.full,
      looseSource: loose,
      pinnedDomain: pinned.registeredDomain
    };
  }
}
