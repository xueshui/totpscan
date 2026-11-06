import type { IncomingMessage, ServerResponse } from "node:http";

export type ErrorCode =
  | "authentication_failed"
  | "invalid_request"
  | "rate_limited"
  | "forbidden"
  | "not_found"
  | "method_not_allowed"
  | "internal_error";

/**
 * 统一错误文案（规范 §8.5）：不得包含失败原因、字段名、剩余次数或剩余时间。
 */
export const ERROR_MESSAGES: Record<ErrorCode, string> = {
  authentication_failed: "认证失败，请重新发起登录",
  invalid_request: "请求格式无效",
  rate_limited: "请求过于频繁",
  forbidden: "无权访问",
  not_found: "资源不存在",
  method_not_allowed: "请求方法不允许",
  internal_error: "服务暂时不可用",
};

const MAX_BODY_BYTES = 16 * 1024;

/** 携带 HTTP 状态码与统一错误码的异常。 */
export class HttpError extends Error {
  readonly status: number;
  readonly code: ErrorCode;

  constructor(status: number, code: ErrorCode) {
    super(ERROR_MESSAGES[code]);
    this.name = "HttpError";
    this.status = status;
    this.code = code;
  }
}

export interface SendOptions {
  secure: boolean;
  requestId: string;
  extraHeaders?: Record<string, string>;
}

function baseHeaders(options: SendOptions): Record<string, string> {
  const headers: Record<string, string> = {
    "Cache-Control": "no-store",
    "X-Content-Type-Options": "nosniff",
    "Referrer-Policy": "no-referrer",
    "X-Frame-Options": "DENY",
    "Content-Security-Policy": "default-src 'none'; frame-ancestors 'none'",
    "X-Request-Id": options.requestId,
  };
  if (options.secure) {
    headers["Strict-Transport-Security"] = "max-age=31536000; includeSubDomains";
  }
  return headers;
}

export function sendJson(
  res: ServerResponse,
  status: number,
  body: unknown,
  options: SendOptions,
): void {
  if (res.headersSent) {
    res.end();
    return;
  }
  const payload = JSON.stringify(body);
  res.writeHead(status, {
    ...baseHeaders(options),
    "Content-Type": "application/json; charset=utf-8",
    "Content-Length": Buffer.byteLength(payload).toString(),
    ...(options.extraHeaders ?? {}),
  });
  res.end(payload);
}

/** 所有错误响应都经由这里，确保格式完全一致。 */
export function sendError(
  res: ServerResponse,
  status: number,
  code: ErrorCode,
  options: SendOptions,
): void {
  sendJson(
    res,
    status,
    { error: code, message: ERROR_MESSAGES[code], request_id: options.requestId },
    options,
  );
}

/** 读取并解析 JSON 对象；任何格式问题都归一化为 400 invalid_request。 */
export async function readJsonObject(
  req: IncomingMessage,
  options: { optional?: boolean } = {},
): Promise<Record<string, unknown>> {
  const chunks: Buffer[] = [];
  let size = 0;
  for await (const chunk of req) {
    const buffer = Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk);
    size += buffer.length;
    if (size > MAX_BODY_BYTES) {
      throw new HttpError(400, "invalid_request");
    }
    chunks.push(buffer);
  }

  if (size === 0) {
    if (options.optional) {
      return {};
    }
    throw new HttpError(400, "invalid_request");
  }

  const contentType = String(req.headers["content-type"] ?? "").toLowerCase();
  if (!contentType.includes("application/json")) {
    throw new HttpError(400, "invalid_request");
  }

  let parsed: unknown;
  try {
    parsed = JSON.parse(Buffer.concat(chunks).toString("utf8"));
  } catch {
    throw new HttpError(400, "invalid_request");
  }
  if (typeof parsed !== "object" || parsed === null || Array.isArray(parsed)) {
    throw new HttpError(400, "invalid_request");
  }
  return parsed as Record<string, unknown>;
}

/** 请求体只允许 OpenAPI schema 中声明的字段（`additionalProperties: false`）。 */
export function rejectUnknownFields(
  body: Record<string, unknown>,
  allowed: readonly string[],
): void {
  for (const key of Object.keys(body)) {
    if (!allowed.includes(key)) {
      throw new HttpError(400, "invalid_request");
    }
  }
}

/** 重复参数名不属于合法绑定请求，直接拒绝。 */
export function requireString(value: unknown, minLength: number, maxLength: number): string {
  if (typeof value !== "string" || value.length < minLength || value.length > maxLength) {
    throw new HttpError(400, "invalid_request");
  }
  // eslint-disable-next-line no-control-regex
  if (/[\u0000-\u001F\u007F]/.test(value)) {
    throw new HttpError(400, "invalid_request");
  }
  return value.normalize("NFC");
}

export function optionalEnum<T extends string>(value: unknown, allowed: readonly T[], fallback: T): T {
  if (value === undefined) {
    return fallback;
  }
  if (typeof value !== "string" || !allowed.includes(value as T)) {
    throw new HttpError(400, "invalid_request");
  }
  return value as T;
}

export function getCookie(req: IncomingMessage, name: string): string | null {
  const header = req.headers.cookie;
  if (!header) {
    return null;
  }
  for (const part of header.split(";")) {
    const trimmed = part.trim();
    const separator = trimmed.indexOf("=");
    if (separator < 0) {
      continue;
    }
    if (trimmed.slice(0, separator) === name) {
      return trimmed.slice(separator + 1);
    }
  }
  return null;
}

export function buildSessionCookie(name: string, value: string, ttlSeconds: number, secure: boolean): string {
  const parts = [`${name}=${value}`, "Path=/", "HttpOnly", "SameSite=Lax", `Max-Age=${ttlSeconds}`];
  if (secure) {
    parts.push("Secure");
  }
  return parts.join("; ");
}

export function buildExpiredSessionCookie(name: string, secure: boolean): string {
  const parts = [`${name}=`, "Path=/", "HttpOnly", "SameSite=Lax", "Max-Age=0"];
  if (secure) {
    parts.push("Secure");
  }
  return parts.join("; ");
}

export function clientIp(req: IncomingMessage): string {
  return req.socket.remoteAddress ?? "unknown";
}

/** 判断请求是否可以被响应体接受（仅 POST）。 */
export function requireMethod(req: IncomingMessage, method: string): void {
  if (req.method !== method) {
    throw new HttpError(405, "method_not_allowed");
  }
}
