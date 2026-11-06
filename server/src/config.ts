import { canonicalizeSubmitUrl, UrlCanonicalizationError } from "./core/canonical-url.ts";

export interface RateLimitRule {
  limit: number;
  windowMs: number;
}

export interface Config {
  host: string;
  port: number;
  /** 服务端对外基地址（仅 scheme://host[:port]），用于生成绑定二维码中的 dom 与 path。 */
  publicBaseUrl: string;
  submitUrl: string;
  adminToken: string;
  secureCookies: boolean;
  tokenTtlSeconds: number;
  sessionTtlSeconds: number;
  bindingTtlSeconds: number;
  maxTokenAttempts: number;
  maxBindingAttempts: number;
  totpWindow: number;
  rates: {
    tokenPerSession: RateLimitRule;
    tokenPerIp: RateLimitRule;
    verifyPerIp: RateLimitRule;
    bindingCreatePerIp: RateLimitRule;
    bindingConfirmPerIp: RateLimitRule;
  };
}

/** 规范硬上限：登录 token 绝对有效期不得超过 60 秒。 */
export const MAX_TOKEN_TTL_SECONDS = 60;

/** 管理令牌最短长度：不足时拒绝启动（S14）。 */
export const MIN_ADMIN_TOKEN_LENGTH = 32;

function readInt(env: NodeJS.ProcessEnv, name: string, fallback: number): number {
  const raw = env[name];
  if (raw === undefined || raw === "") {
    return fallback;
  }
  const parsed = Number.parseInt(raw, 10);
  if (!Number.isFinite(parsed) || parsed <= 0) {
    throw new Error(`配置项 ${name} 必须是正整数`);
  }
  return parsed;
}

function readBool(env: NodeJS.ProcessEnv, name: string, fallback: boolean): boolean {
  const raw = env[name];
  if (raw === undefined || raw === "") {
    return fallback;
  }
  return raw === "1" || raw.toLowerCase() === "true";
}

/** 端口允许 0（由系统分配临时端口），用于演示与测试。 */
function readPort(env: NodeJS.ProcessEnv, name: string, fallback: number): number {
  const raw = env[name];
  if (raw === undefined || raw === "") {
    return fallback;
  }
  const parsed = Number.parseInt(raw, 10);
  if (!Number.isFinite(parsed) || parsed < 0 || parsed > 65535) {
    throw new Error(`配置项 ${name} 必须是 0–65535 之间的整数`);
  }
  return parsed;
}

/** 管理令牌必须由部署方提供：没有默认值，长度不足即拒绝启动（S14）。 */
function readAdminToken(env: NodeJS.ProcessEnv): string {
  const raw = env.ADMIN_TOKEN;
  if (typeof raw !== "string" || raw.trim() === "") {
    throw new Error("ADMIN_TOKEN 未配置：服务端拒绝启动（规范 S14，不提供默认管理令牌）");
  }
  if (raw.length < MIN_ADMIN_TOKEN_LENGTH) {
    throw new Error(
      `ADMIN_TOKEN 长度不足：至少 ${MIN_ADMIN_TOKEN_LENGTH} 个字符（规范 S14）`,
    );
  }
  return raw;
}

/** 从环境变量加载配置，并在启动时校验（失败即拒绝启动）。 */
export function loadConfig(env: NodeJS.ProcessEnv = process.env): Config {
  const host = env.HOST ?? "127.0.0.1";
  const port = readPort(env, "PORT", 8080);
  // 未显式配置时，按实际监听地址推导对外基地址，避免二维码里的 dom/path 指向错误端口。
  const urlHost = host === "0.0.0.0" || host === "::" ? "localhost" : host;
  const publicBaseRaw = env.PUBLIC_BASE_URL ?? `http://${urlHost}:${port}`;
  let publicBaseUrl: string;
  try {
    const canonical = canonicalizeSubmitUrl(publicBaseRaw);
    const url = new URL(canonical);
    publicBaseUrl = url.origin;
  } catch (error) {
    const reason = error instanceof UrlCanonicalizationError ? error.reason : "UNKNOWN";
    throw new Error(`PUBLIC_BASE_URL 非法（${reason}）`);
  }

  const tokenTtlSeconds = readInt(env, "TOKEN_TTL", 60);
  if (tokenTtlSeconds > MAX_TOKEN_TTL_SECONDS) {
    throw new Error(`TOKEN_TTL 不得超过 ${MAX_TOKEN_TTL_SECONDS} 秒`);
  }

  const adminToken = readAdminToken(env);

  return {
    host,
    port,
    publicBaseUrl,
    submitUrl: `${publicBaseUrl}/totp/v1/verify`,
    adminToken,
    secureCookies: readBool(env, "SECURE_COOKIES", publicBaseUrl.startsWith("https://")),
    tokenTtlSeconds,
    sessionTtlSeconds: readInt(env, "SESSION_TTL", 1800),
    bindingTtlSeconds: readInt(env, "BINDING_TTL", 600),
    maxTokenAttempts: 5,
    maxBindingAttempts: 5,
    totpWindow: 1,
    rates: {
      tokenPerSession: { limit: 5, windowMs: 60_000 },
      tokenPerIp: { limit: 30, windowMs: 60_000 },
      verifyPerIp: { limit: 30, windowMs: 60_000 },
      bindingCreatePerIp: { limit: 10, windowMs: 60_000 },
      bindingConfirmPerIp: { limit: 10, windowMs: 60_000 },
    },
  };
}
