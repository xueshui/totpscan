import type { Clock } from "./clock.ts";
import type { RateLimitRule } from "./config.ts";
import type { TotpAlgorithm } from "./core/totp.ts";
import { generateToken, tokenDigest } from "./core/token.ts";
import { randomToken } from "./util.ts";

export type BindingStatus = "pending" | "confirmed" | "revoked" | "invalid";

export interface BindingRecord {
  id: string;
  issuer: string;
  account: string;
  secret: Buffer;
  algorithm: TotpAlgorithm;
  digits: 6 | 8;
  period: 30 | 60;
  submitUrl: string;
  status: BindingStatus;
  createdAt: number;
  expiresAt: number;
  confirmedAt: number | null;
  revokedAt: number | null;
  attempts: number;
}

export type TokenState = "issued" | "consumed" | "expired" | "exhausted" | "revoked";

export interface TokenRecord {
  digest: string;
  sessionId: string;
  /** 签发时指定的账户；提交时不再由客户端提供，服务端以该字段定位绑定。 */
  account: string;
  issuedAt: number;
  expiresAt: number;
  attempts: number;
  state: TokenState;
}

export interface SessionRecord {
  id: string;
  createdAt: number;
  lastSeenAt: number;
  expiresAt: number;
  authenticated: boolean;
  bindingId: string | null;
}

export interface CreateBindingInput {
  id: string;
  issuer: string;
  account: string;
  secret: Buffer;
  algorithm: TotpAlgorithm;
  digits: 6 | 8;
  period: 30 | 60;
  submitUrl: string;
  expiresAt: number;
}

/**
 * 内存存储（参考实现）。
 * 生产环境应替换为带唯一约束与原子计数的事务型存储，语义保持与这里一致。
 */
export class MemoryStore {
  private readonly clock: Clock;
  private readonly bindings = new Map<string, BindingRecord>();
  private readonly sessions = new Map<string, SessionRecord>();
  private readonly tokens = new Map<string, TokenRecord>();
  private readonly replay = new Map<string, number>();
  private readonly counters = new Map<string, { count: number; windowStart: number }>();

  constructor(clock: Clock) {
    this.clock = clock;
  }

  // ---------- 绑定 ----------

  createBinding(input: CreateBindingInput): BindingRecord {
    const now = this.clock.now();
    const record: BindingRecord = {
      ...input,
      status: "pending",
      createdAt: now,
      confirmedAt: null,
      revokedAt: null,
      attempts: 0,
    };
    this.bindings.set(record.id, record);
    return record;
  }

  getBinding(id: string): BindingRecord | null {
    return this.bindings.get(id) ?? null;
  }

  /** 按账户查找最近一个已确认绑定。 */
  findConfirmedBindingByAccount(account: string): BindingRecord | null {
    let latest: BindingRecord | null = null;
    for (const binding of this.bindings.values()) {
      if (binding.account !== account || binding.status !== "confirmed") {
        continue;
      }
      if (!latest || binding.createdAt > latest.createdAt) {
        latest = binding;
      }
    }
    return latest;
  }

  registerBindingFailure(binding: BindingRecord, maxAttempts: number): void {
    binding.attempts += 1;
    if (binding.attempts >= maxAttempts) {
      binding.status = "invalid";
    }
  }

  confirmBinding(binding: BindingRecord): void {
    binding.status = "confirmed";
    binding.confirmedAt = this.clock.now();
    binding.attempts = 0;
  }

  revokeBinding(binding: BindingRecord): void {
    binding.status = "revoked";
    binding.revokedAt = this.clock.now();
    this.revokeTokensForAccount(binding.account);
    this.discardReplayForBinding(binding.id);
  }

  // ---------- 会话 ----------

  createSession(ttlSeconds: number): SessionRecord {
    const now = this.clock.now();
    const record: SessionRecord = {
      id: randomToken(32),
      createdAt: now,
      lastSeenAt: now,
      expiresAt: now + ttlSeconds * 1000,
      authenticated: false,
      bindingId: null,
    };
    this.sessions.set(record.id, record);
    return record;
  }

  getSession(id: string): SessionRecord | null {
    const session = this.sessions.get(id);
    if (!session) {
      return null;
    }
    const now = this.clock.now();
    if (now >= session.expiresAt) {
      this.sessions.delete(id);
      this.revokeTokensForSession(id);
      return null;
    }
    session.lastSeenAt = now;
    return session;
  }

  deleteSession(id: string): void {
    this.sessions.delete(id);
    this.revokeTokensForSession(id);
  }

  // ---------- 登录 token ----------

  issueToken(sessionId: string, account: string, ttlSeconds: number): { token: string; record: TokenRecord } {
    const now = this.clock.now();
    const token = generateToken();
    const record: TokenRecord = {
      digest: tokenDigest(token),
      sessionId,
      account,
      issuedAt: now,
      expiresAt: now + ttlSeconds * 1000,
      attempts: 0,
      state: "issued",
    };
    this.tokens.set(record.digest, record);
    return { token, record };
  }

  getToken(digest: string): TokenRecord | null {
    return this.tokens.get(digest) ?? null;
  }

  registerTokenFailure(record: TokenRecord, maxAttempts: number): void {
    record.attempts += 1;
    if (record.attempts >= maxAttempts) {
      record.state = "exhausted";
    }
  }

  consumeToken(record: TokenRecord): void {
    record.state = "consumed";
  }

  expireToken(record: TokenRecord): void {
    record.state = "expired";
  }

  /** 解绑时作废该账户名下未消费的 token。 */
  revokeTokensForAccount(account: string): void {
    for (const record of this.tokens.values()) {
      if (record.account === account && record.state === "issued") {
        record.state = "revoked";
      }
    }
  }

  revokeTokensForSession(sessionId: string): void {
    for (const record of this.tokens.values()) {
      if (record.sessionId === sessionId && record.state === "issued") {
        record.state = "revoked";
      }
    }
  }

  // ---------- 重放防护 ----------

  private replayKey(bindingId: string, timeStep: number): string {
    return `${bindingId}:${timeStep}`;
  }

  hasReplay(bindingId: string, timeStep: number): boolean {
    return this.replay.has(this.replayKey(bindingId, timeStep));
  }

  markReplay(bindingId: string, timeStep: number): void {
    this.replay.set(this.replayKey(bindingId, timeStep), this.clock.now());
  }

  discardReplayForBinding(bindingId: string): void {
    for (const key of this.replay.keys()) {
      if (key.startsWith(bindingId + ":")) {
        this.replay.delete(key);
      }
    }
  }

  // ---------- 限流 ----------

  /** 固定窗口计数；返回是否放行。 */
  hitRate(key: string, rule: RateLimitRule): boolean {
    const now = this.clock.now();
    const counter = this.counters.get(key);
    if (!counter || now - counter.windowStart >= rule.windowMs) {
      this.counters.set(key, { count: 1, windowStart: now });
      return true;
    }
    if (counter.count >= rule.limit) {
      return false;
    }
    counter.count += 1;
    return true;
  }

  // ---------- 维护 ----------

  /** 清理过期 token 与旧重放记录，避免内存无界增长。 */
  prune(): void {
    const now = this.clock.now();
    for (const [digest, record] of this.tokens) {
      if (record.state !== "issued" && now - record.expiresAt > 600_000) {
        this.tokens.delete(digest);
      }
    }
    for (const [key, createdAt] of this.replay) {
      if (now - createdAt > 600_000) {
        this.replay.delete(key);
      }
    }
  }
}
