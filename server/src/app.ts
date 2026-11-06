import { randomBytes } from "node:crypto";
import type { IncomingMessage, ServerResponse } from "node:http";
import type { Clock } from "./clock.ts";
import { systemClock } from "./clock.ts";
import type { Config } from "./config.ts";
import { canonicalizeSubmitUrl, normalizeBindDomain, normalizeBindPath, splitCanonicalUrl } from "./core/canonical-url.ts";
import { isTokenShaped, tokenDigest } from "./core/token.ts";
import {
  DEFAULT_TOTP_OPTIONS,
  verifyTotp,
  type TotpOptions,
} from "./core/totp.ts";
import {
  buildExpiredSessionCookie,
  buildSessionCookie,
  clientIp,
  getCookie,
  HttpError,
  optionalEnum,
  readJsonObject,
  rejectUnknownFields,
  requireMethod,
  requireString,
  sendError,
  sendJson,
} from "./http.ts";
import { MemoryStore, type BindingRecord } from "./store.ts";
import {
  base32Encode,
  constantTimeEqualString,
  isNumericCode,
  newRequestId,
  randomToken,
} from "./util.ts";

const SESSION_COOKIE = "tsid";

/** 固定假密钥：token 不存在时也执行一次等价 HMAC，避免计时旁路（§8.5）。 */
const DUMMY_SECRET = Buffer.alloc(20, 0x5a);

export interface AppOptions {
  config: Config;
  clock?: Clock;
  store?: MemoryStore;
}

export interface App {
  handler: (req: IncomingMessage, res: ServerResponse) => void;
  store: MemoryStore;
  config: Config;
  clock: Clock;
}

export function createApp(options: AppOptions): App {
  const config = options.config;
  const clock = options.clock ?? systemClock;
  const store = options.store ?? new MemoryStore(clock);
  const secure = config.secureCookies;

  function sendOptions(requestId: string, extraHeaders?: Record<string, string>) {
    return { secure, requestId, extraHeaders };
  }

  function isAdmin(req: IncomingMessage): boolean {
    if (config.adminToken === "") {
      return false;
    }
    const header = req.headers.authorization;
    if (typeof header !== "string") {
      return false;
    }
    const match = /^Bearer\s+(.+)$/.exec(header);
    if (!match) {
      return false;
    }
    return constantTimeEqualString(match[1], config.adminToken);
  }

  function totpOptions(binding: BindingRecord): TotpOptions {
    return { algorithm: binding.algorithm, digits: binding.digits, period: binding.period };
  }

  /** 认证失败统一出口：不区分未知 / 过期 / 已用 / 跨会话 / 次数耗尽 / 码错误。 */
  function rejectAuthentication(): never {
    throw new HttpError(401, "authentication_failed");
  }

  function runDummyTotp(code: string): void {
    verifyTotp(DUMMY_SECRET, code, clock.now(), DEFAULT_TOTP_OPTIONS, config.totpWindow);
  }

  async function handleCreateBinding(req: IncomingMessage, res: ServerResponse, requestId: string): Promise<void> {
    requireMethod(req, "POST");
    if (!store.hitRate(`bind:create:${clientIp(req)}`, config.rates.bindingCreatePerIp)) {
      throw new HttpError(429, "rate_limited");
    }
    if (!isAdmin(req)) {
      throw new HttpError(401, "forbidden");
    }

    const body = await readJsonObject(req);
    rejectUnknownFields(body, ["issuer", "account", "algorithm", "digits", "period"]);
    const issuer = requireString(body.issuer, 1, 64);
    const account = requireString(body.account, 1, 255);
    const algorithm = optionalEnum(body.algorithm, ["SHA1", "SHA256", "SHA512"] as const, "SHA1");
    const digitsRaw = body.digits === undefined ? 6 : Number(body.digits);
    if (digitsRaw !== 6 && digitsRaw !== 8) {
      throw new HttpError(400, "invalid_request");
    }
    const digits: 6 | 8 = digitsRaw === 6 ? 6 : 8;
    const periodRaw = body.period === undefined ? 30 : Number(body.period);
    if (periodRaw !== 30 && periodRaw !== 60) {
      throw new HttpError(400, "invalid_request");
    }
    const period: 30 | 60 = periodRaw === 30 ? 30 : 60;

    const now = clock.now();
    const iat = Math.floor(now / 1000);
    const bindingId = `b_${randomToken(16)}`;
    const secret = randomBytes(20);
    const submitUrl = canonicalizeSubmitUrl(config.submitUrl);
    const submitParts = splitCanonicalUrl(submitUrl);
    const dom = normalizeBindDomain(
      submitParts.port === "" ? submitParts.host : `${submitParts.host}:${submitParts.port}`,
    );
    const path = normalizeBindPath(submitParts.pathQuery);

    const payload = {
      t: "totp-bind" as const,
      v: 1 as const,
      bid: bindingId,
      iss: issuer,
      acc: account,
      sec: base32Encode(secret),
      alg: algorithm,
      dig: digits,
      per: period,
      dom,
      path,
      iat,
      exp: iat + config.bindingTtlSeconds,
    };

    store.createBinding({
      id: bindingId,
      issuer,
      account,
      secret,
      algorithm,
      digits,
      period,
      submitUrl,
      expiresAt: now + config.bindingTtlSeconds * 1000,
    });
    store.prune();

    sendJson(
      res,
      201,
      {
        binding_id: bindingId,
        status: "pending",
        expires_at: payload.exp,
        binding_qr: payload,
        binding_qr_text: JSON.stringify(payload),
      },
      sendOptions(requestId),
    );
  }

  async function handleConfirmBinding(
    req: IncomingMessage,
    res: ServerResponse,
    requestId: string,
    bindingId: string,
  ): Promise<void> {
    requireMethod(req, "POST");
    if (!store.hitRate(`bind:confirm:${clientIp(req)}`, config.rates.bindingConfirmPerIp)) {
      throw new HttpError(429, "rate_limited");
    }

    const body = await readJsonObject(req);
    rejectUnknownFields(body, ["code"]);
    const code = body.code;
    if (!isNumericCode(code)) {
      throw new HttpError(400, "invalid_request");
    }

    const binding = store.getBinding(bindingId);
    if (!binding || binding.status !== "pending") {
      runDummyTotp(code);
      rejectAuthentication();
    }
    if (clock.now() >= binding.expiresAt) {
      runDummyTotp(code);
      rejectAuthentication();
    }
    if (binding.attempts >= config.maxBindingAttempts) {
      runDummyTotp(code);
      rejectAuthentication();
    }
    if (!isNumericCode(code, binding.digits)) {
      store.registerBindingFailure(binding, config.maxBindingAttempts);
      rejectAuthentication();
    }

    const result = verifyTotp(binding.secret, code, clock.now(), totpOptions(binding), config.totpWindow);
    if (!result.matched || result.timeStep === null) {
      store.registerBindingFailure(binding, config.maxBindingAttempts);
      rejectAuthentication();
    }

    // 确认阶段同样写入重放记录：确认所用的时间步不能再用于登录（S9）。
    store.markReplay(binding.id, result.timeStep);
    store.confirmBinding(binding);
    sendJson(
      res,
      200,
      {
        binding_id: binding.id,
        status: "confirmed",
        confirmed_at: Math.floor(clock.now() / 1000),
      },
      sendOptions(requestId),
    );
  }

  async function handleRevokeBinding(
    req: IncomingMessage,
    res: ServerResponse,
    requestId: string,
    bindingId: string,
  ): Promise<void> {
    requireMethod(req, "POST");
    if (!isAdmin(req)) {
      throw new HttpError(401, "forbidden");
    }
    const binding = store.getBinding(bindingId);
    if (!binding) {
      throw new HttpError(404, "not_found");
    }
    store.revokeBinding(binding);
    sendJson(
      res,
      200,
      {
        binding_id: binding.id,
        status: "revoked",
        revoked_at: Math.floor(clock.now() / 1000),
      },
      sendOptions(requestId),
    );
  }

  async function handleIssueToken(
    req: IncomingMessage,
    res: ServerResponse,
    requestId: string,
  ): Promise<void> {
    requireMethod(req, "POST");
    const ip = clientIp(req);
    if (!store.hitRate(`token:ip:${ip}`, config.rates.tokenPerIp)) {
      throw new HttpError(429, "rate_limited");
    }

    const body = await readJsonObject(req, { optional: true });
    rejectUnknownFields(body, ["account"]);
    const account = requireString(body.account, 1, 255);

    const binding = store.findConfirmedBindingByAccount(account);
    if (!binding) {
      rejectAuthentication();
    }

    const cookieSid = getCookie(req, SESSION_COOKIE);
    let session = cookieSid ? store.getSession(cookieSid) : null;
    let extraHeaders: Record<string, string> | undefined;
    if (!session) {
      session = store.createSession(config.sessionTtlSeconds);
      extraHeaders = {
        "Set-Cookie": buildSessionCookie(SESSION_COOKIE, session.id, config.sessionTtlSeconds, secure),
      };
    }

    if (!store.hitRate(`token:session:${session.id}`, config.rates.tokenPerSession)) {
      throw new HttpError(429, "rate_limited");
    }

    const { token, record } = store.issueToken(session.id, account, config.tokenTtlSeconds);
    const expiresAt = Math.floor(record.expiresAt / 1000);
    const loginQr = {
      t: "totp-login" as const,
      v: 1 as const,
      url: splitCanonicalUrl(canonicalizeSubmitUrl(config.submitUrl)).host,
      token,
      exp: expiresAt,
    };

    store.prune();
    sendJson(
      res,
      200,
      {
        token,
        expires_at: expiresAt,
        expires_in: Math.max(0, Math.ceil((record.expiresAt - clock.now()) / 1000)),
        login_qr: loginQr,
        login_qr_text: JSON.stringify(loginQr),
      },
      sendOptions(requestId, extraHeaders),
    );
  }

  async function handleVerify(req: IncomingMessage, res: ServerResponse, requestId: string): Promise<void> {
    requireMethod(req, "POST");
    const ip = clientIp(req);
    if (!store.hitRate(`verify:ip:${ip}`, config.rates.verifyPerIp)) {
      throw new HttpError(429, "rate_limited");
    }

    const body = await readJsonObject(req);
    rejectUnknownFields(body, ["token", "code"]);
    const token = body.token;
    const code = body.code;
    if (!isTokenShaped(token) || !isNumericCode(code)) {
      throw new HttpError(400, "invalid_request");
    }

    const digest = tokenDigest(token);
    const record = store.getToken(digest);
    const cookieSid = getCookie(req, SESSION_COOKIE);
    const session = cookieSid ? store.getSession(cookieSid) : null;

    // 以下所有失败分支都必须落到同一个 401 响应，且尽量保持等价计算开销。
    if (!record || !session) {
      runDummyTotp(code);
      rejectAuthentication();
    }
    if (record.state !== "issued") {
      runDummyTotp(code);
      rejectAuthentication();
    }
    if (clock.now() >= record.expiresAt) {
      store.expireToken(record);
      runDummyTotp(code);
      rejectAuthentication();
    }
    if (record.sessionId !== session.id) {
      runDummyTotp(code);
      rejectAuthentication();
    }

    const binding = store.findConfirmedBindingByAccount(record.account);
    if (!binding || binding.status !== "confirmed") {
      store.registerTokenFailure(record, config.maxTokenAttempts);
      runDummyTotp(code);
      rejectAuthentication();
    }
    if (record.attempts >= config.maxTokenAttempts) {
      runDummyTotp(code);
      rejectAuthentication();
    }
    if (!isNumericCode(code, binding.digits)) {
      store.registerTokenFailure(record, config.maxTokenAttempts);
      rejectAuthentication();
    }

    const result = verifyTotp(binding.secret, code, clock.now(), totpOptions(binding), config.totpWindow);
    if (!result.matched || result.timeStep === null) {
      store.registerTokenFailure(record, config.maxTokenAttempts);
      rejectAuthentication();
    }
    if (store.hasReplay(binding.id, result.timeStep)) {
      store.registerTokenFailure(record, config.maxTokenAttempts);
      rejectAuthentication();
    }

    store.markReplay(binding.id, result.timeStep);
    store.consumeToken(record);
    session.authenticated = true;
    session.bindingId = binding.id;

    sendJson(res, 200, { status: "ok", authenticated: true }, sendOptions(requestId));
  }

  async function handleSession(req: IncomingMessage, res: ServerResponse, requestId: string): Promise<void> {
    requireMethod(req, "GET");
    const cookieSid = getCookie(req, SESSION_COOKIE);
    let session = cookieSid ? store.getSession(cookieSid) : null;
    let extraHeaders: Record<string, string> | undefined;
    if (!session) {
      session = store.createSession(config.sessionTtlSeconds);
      extraHeaders = {
        "Set-Cookie": buildSessionCookie(SESSION_COOKIE, session.id, config.sessionTtlSeconds, secure),
      };
    }
    sendJson(
      res,
      200,
      {
        authenticated: session.authenticated,
        binding_id: session.bindingId,
        expires_at: Math.floor(session.expiresAt / 1000),
      },
      sendOptions(requestId, extraHeaders),
    );
  }

  async function handleLogout(req: IncomingMessage, res: ServerResponse, requestId: string): Promise<void> {
    requireMethod(req, "POST");
    const cookieSid = getCookie(req, SESSION_COOKIE);
    if (cookieSid) {
      store.deleteSession(cookieSid);
    }
    sendJson(res, 200, { status: "ok" }, sendOptions(requestId, {
      "Set-Cookie": buildExpiredSessionCookie(SESSION_COOKIE, secure),
    }));
  }

  async function route(req: IncomingMessage, res: ServerResponse, requestId: string): Promise<void> {
    const url = new URL(req.url ?? "/", "http://localhost");
    const path = url.pathname;

    if (path === "/healthz") {
      requireMethod(req, "GET");
      sendJson(res, 200, { status: "ok" }, sendOptions(requestId));
      return;
    }

    if (path === "/totp/v1/bindings") {
      await handleCreateBinding(req, res, requestId);
      return;
    }

    const bindingRoute = /^\/totp\/v1\/bindings\/([A-Za-z0-9_-]{2,80})\/(confirm|revoke)$/.exec(path);
    if (bindingRoute) {
      if (bindingRoute[2] === "confirm") {
        await handleConfirmBinding(req, res, requestId, bindingRoute[1]);
      } else {
        await handleRevokeBinding(req, res, requestId, bindingRoute[1]);
      }
      return;
    }

    if (path === "/totp/v1/login/token") {
      await handleIssueToken(req, res, requestId);
      return;
    }

    if (path === "/totp/v1/verify") {
      await handleVerify(req, res, requestId);
      return;
    }

    if (path === "/totp/v1/session") {
      await handleSession(req, res, requestId);
      return;
    }

    if (path === "/totp/v1/logout") {
      await handleLogout(req, res, requestId);
      return;
    }

    throw new HttpError(404, "not_found");
  }

  const handler = (req: IncomingMessage, res: ServerResponse): void => {
    const requestId = newRequestId();
    route(req, res, requestId).catch((error: unknown) => {
      if (res.headersSent) {
        res.end();
        return;
      }
      if (error instanceof HttpError) {
        sendError(res, error.status, error.code, sendOptions(requestId));
        return;
      }
      // 只记录方法、路径与错误类型，不记录请求体（避免密钥/token 进入日志）。
      console.error(
        JSON.stringify({
          ts: new Date(clock.now()).toISOString(),
          event: "unhandled_error",
          method: req.method,
          path: (req.url ?? "").split("?")[0],
          error: error instanceof Error ? error.name : "Unknown",
          request_id: requestId,
        }),
      );
      sendError(res, 500, "internal_error", sendOptions(requestId));
    });
  };

  return { handler, store, config, clock };
}
