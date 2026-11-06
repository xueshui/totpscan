import { createServer } from "node:http";
import type { Server } from "node:http";
import type { AddressInfo } from "node:net";
import { createApp, type App } from "../src/app.ts";
import { ManualClock } from "../src/clock.ts";
import { loadConfig, type Config } from "../src/config.ts";
import { generateTotp, timeStepAt, type TotpOptions } from "../src/core/totp.ts";
import { base32Decode } from "../src/util.ts";

/** 测试用管理员令牌（≥32 字符，满足 S14 的启动校验）。 */
export const TEST_ADMIN_TOKEN = "test-admin-token-0123456789abcdef";

export interface HttpResult {
  status: number;
  // 测试里为了方便直接 JSON.parse，用 any。
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  body: any;
  setCookie: string[];
}

/** 带 Cookie 容器的测试客户端。 */
export class TestClient {
  readonly baseUrl: string;
  cookie: string | null = null;

  constructor(baseUrl: string) {
    this.baseUrl = baseUrl;
    this.cookie = null;
  }

  async request(
    method: string,
    path: string,
    body?: unknown,
    headers: Record<string, string> = {},
  ): Promise<HttpResult> {
    const requestHeaders: Record<string, string> = { ...headers };
    if (body !== undefined) {
      requestHeaders["content-type"] = "application/json";
    }
    if (this.cookie) {
      requestHeaders.cookie = this.cookie;
    }
    const response = await fetch(this.baseUrl + path, {
      method,
      headers: requestHeaders,
      body: body === undefined ? undefined : JSON.stringify(body),
    });
    const setCookie = response.headers.getSetCookie();
    if (setCookie.length > 0) {
      this.cookie = setCookie[0].split(";")[0];
    }
    const text = await response.text();
    return { status: response.status, body: text ? JSON.parse(text) : null, setCookie };
  }
}

export interface Harness {
  app: App;
  server: Server;
  clock: ManualClock;
  config: Config;
  client: TestClient;
  baseUrl: string;
  close: () => Promise<void>;
}

/** 在随机端口启动参考实现；时钟可手动推进，配置可覆盖。 */
export async function startHarness(configure?: (config: Config) => void): Promise<Harness> {
  const clock = new ManualClock();
  const config = loadConfig({
    PUBLIC_BASE_URL: "http://localhost:8080",
    ADMIN_TOKEN: TEST_ADMIN_TOKEN,
  });
  if (configure) {
    configure(config);
  }

  // 绑定载荷不签名，服务端不持有任何签名密钥。
  const app = createApp({ config, clock });
  const server = createServer(app.handler);
  await new Promise<void>((resolve) => server.listen(0, "127.0.0.1", resolve));
  const port = (server.address() as AddressInfo).port;
  const baseUrl = `http://127.0.0.1:${port}`;

  return {
    app,
    server,
    clock,
    config,
    client: new TestClient(baseUrl),
    baseUrl,
    close: async () => {
      server.closeAllConnections();
      await new Promise<void>((resolve) => server.close(() => resolve()));
    },
  };
}

export interface BindingQrFixture {
  t: "totp-bind";
  v: 1;
  bid: string;
  iss: string;
  acc: string;
  sec: string;
  alg: "SHA1" | "SHA256" | "SHA512";
  dig: 6 | 8;
  per: 30 | 60;
  dom: string;
  path: string;
  iat: number;
  exp?: number;
}

export interface BindingFixture {
  bindingId: string;
  qr: BindingQrFixture;
  secret: Buffer;
  options: TotpOptions;
}

export async function createBinding(
  client: TestClient,
  account = "alice@example.com",
  options: { algorithm?: "SHA1" | "SHA256" | "SHA512"; digits?: 6 | 8; period?: 30 | 60 } = {},
): Promise<BindingFixture> {
  const response = await client.request(
    "POST",
    "/totp/v1/bindings",
    { issuer: "Example Corp", account, ...options },
    { authorization: `Bearer ${TEST_ADMIN_TOKEN}` },
  );
  if (response.status !== 201) {
    throw new Error(`创建绑定失败：${response.status} ${JSON.stringify(response.body)}`);
  }
  const qr = response.body.binding_qr as BindingQrFixture;
  return {
    bindingId: response.body.binding_id,
    qr,
    secret: base32Decode(qr.sec),
    options: { algorithm: qr.alg, digits: qr.dig, period: qr.per },
  };
}

export function codeFor(binding: BindingFixture, epochMs: number, stepOffset = 0): string {
  const step = timeStepAt(epochMs, binding.options.period) + stepOffset;
  return generateTotp(binding.secret, step, binding.options);
}

export async function confirmBinding(client: TestClient, binding: BindingFixture, epochMs: number): Promise<void> {
  const response = await client.request("POST", `/totp/v1/bindings/${binding.bindingId}/confirm`, {
    code: codeFor(binding, epochMs),
  });
  if (response.status !== 200) {
    throw new Error(`确认绑定失败：${response.status} ${JSON.stringify(response.body)}`);
  }
}

/**
 * 确认成功会写入该时间步的重放记录（S9），因此后续登录必须换到下一个时间步。
 * 返回确认后应使用的时钟毫秒数（推进一个完整周期）。
 */
export function timeStepAfterConfirm(binding: BindingFixture, epochMs: number): number {
  return epochMs + binding.options.period * 1000;
}

/** 建好绑定 + 会话，返回可直接用于登录测试的上下文。 */
export async function bootstrap(options: {
  harness: Harness;
  account?: string;
  confirm?: boolean;
}): Promise<BindingFixture> {
  const account = options.account ?? "alice@example.com";
  const binding = await createBinding(options.harness.client, account);
  if (options.confirm !== false) {
    const now = options.harness.clock.now();
    await confirmBinding(options.harness.client, binding, now);
    // 确认时间步已写入重放记录，登录必须使用下一个时间步。
    options.harness.clock.advanceMs(timeStepAfterConfirm(binding, now) - now);
  }
  await options.harness.client.request("GET", "/totp/v1/session");
  return binding;
}

export interface LoginQrFixture {
  t: "totp-login";
  v: 1;
  url: string;
  token: string;
  exp: number;
}

export async function issueToken(
  client: TestClient,
  account = "alice@example.com",
): Promise<{ token: string; expiresAt: number; url: string; qr: LoginQrFixture }> {
  const response = await client.request("POST", "/totp/v1/login/token", { account });
  if (response.status !== 200) {
    throw new Error(`签发 token 失败：${response.status} ${JSON.stringify(response.body)}`);
  }
  return {
    token: response.body.token,
    expiresAt: response.body.expires_at,
    url: response.body.login_qr.url,
    qr: response.body.login_qr as LoginQrFixture,
  };
}

/** 提交动态码：只带 token 与 code，不带 account / device_id（§6.1）。 */
export async function submitCode(
  client: TestClient,
  token: string,
  code: string,
): Promise<HttpResult> {
  return client.request("POST", "/totp/v1/verify", { token, code });
}
