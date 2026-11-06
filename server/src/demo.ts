import { randomBytes } from "node:crypto";
import { createServer } from "node:http";
import type { AddressInfo } from "node:net";
import { createApp } from "./app.ts";
import { loadConfig } from "./config.ts";
import { generateTotp, timeStepAt } from "./core/totp.ts";
import { base32Decode } from "./util.ts";

/**
 * 端到端演示：绑定 → 确认 → 签发登录 token → 展示钉住字段 → 提交动态码。
 * 运行：npm run demo
 */
async function main(): Promise<void> {
  // 仅本地演示：每次运行随机生成（32 字符）的管理员令牌，绝不使用固定字符串。
  // 生产部署必须由运维通过 ADMIN_TOKEN 显式配置（S14）。
  const demoAdminToken = randomBytes(24).toString("base64url");
  const config = loadConfig({ ...process.env, ADMIN_TOKEN: demoAdminToken, PORT: "0" });
  console.log(
    JSON.stringify({
      event: "demo_admin_token",
      note: "仅本地演示：运行时随机生成的管理员令牌，不写入任何文件、不可用于生产",
    }),
  );
  const server = createServer();
  await new Promise<void>((resolve) => server.listen(0, "127.0.0.1", resolve));
  const port = (server.address() as AddressInfo).port;
  config.publicBaseUrl = `http://127.0.0.1:${port}`;
  config.submitUrl = `${config.publicBaseUrl}/totp/v1/verify`;

  const app = createApp({ config });
  server.on("request", app.handler);

  const step = (title: string) => console.log(`\n== ${title} ==`);

  let cookie = "";
  async function call(method: string, path: string, body?: unknown, headers: Record<string, string> = {}) {
    const response = await fetch(config.publicBaseUrl + path, {
      method,
      headers: {
        ...(body === undefined ? {} : { "content-type": "application/json" }),
        ...(cookie ? { cookie } : {}),
        ...headers,
      },
      body: body === undefined ? undefined : JSON.stringify(body),
    });
    const setCookie = response.headers.getSetCookie();
    if (setCookie.length > 0) {
      cookie = setCookie[0].split(";")[0];
    }
    const text = await response.text();
    return { status: response.status, body: text ? JSON.parse(text) : null };
  }

  step("1. 服务端创建绑定并展示绑定二维码");
  const created = await call(
    "POST",
    "/totp/v1/bindings",
    { issuer: "Example Corp", account: "alice@example.com" },
    { authorization: `Bearer ${config.adminToken}` },
  );
  if (created.status !== 201) {
    throw new Error(`创建绑定失败：${created.status}`);
  }
  const bindingQr = created.body.binding_qr as {
    bid: string;
    sec: string;
    dom: string;
    path: string;
  };
  console.log(
    JSON.stringify({
      binding_id: created.body.binding_id,
      dom: bindingQr.dom,
      path: bindingQr.path,
      qr: created.body.binding_qr_text,
    }),
  );

  step("2. App 在本地钉住 dom 与 path（绑定载荷不签名）");
  const secret = base32Decode(bindingQr.sec);
  console.log(JSON.stringify({ pinned_dom: bindingQr.dom, pinned_path: bindingQr.path }));

  step("3. App 用本地密钥计算动态码，确认绑定");
  // 确认成功会写入重放记录（S9），因此演示用 t-1 的码确认、用当前时间步的码登录。
  const confirmCode = generateTotp(secret, timeStepAt(Date.now(), 30) - 1);
  const confirmed = await call("POST", `/totp/v1/bindings/${bindingQr.bid}/confirm`, { code: confirmCode });
  console.log(JSON.stringify({ code: confirmCode, status: confirmed.status, body: confirmed.body }));

  step("4. 登录页签发登录 token 与登录二维码");
  await call("GET", "/totp/v1/session");
  const issued = await call("POST", "/totp/v1/login/token", { account: "alice@example.com" });
  if (issued.status !== 200) {
    throw new Error(`签发登录 token 失败：${issued.status}`);
  }
  console.log(JSON.stringify({ expires_in: issued.body.expires_in, qr: issued.body.login_qr_text }));

  step("5. App 自行比对登录二维码 url 与钉住的 dom（服务端不做域名比对）");
  const loginQr = issued.body.login_qr as { url: string; token: string };
  console.log(
    JSON.stringify({
      pinned_dom: bindingQr.dom,
      pinned_path: bindingQr.path,
      login_url: loginQr.url,
      note: "注册域名推导与 pin 校验由客户端完成，参考服务端只输出字段",
    }),
  );

  step("6. App 向钉住的完整地址提交 {code, token}");
  const loginCode = generateTotp(secret, timeStepAt(Date.now(), 30));
  const verified = await call("POST", "/totp/v1/verify", {
    token: loginQr.token,
    code: loginCode,
  });
  console.log(JSON.stringify({ status: verified.status, body: verified.body }));

  step("7. 重复提交同一 token（一次性校验，参考实现）");
  const replayed = await call("POST", "/totp/v1/verify", {
    token: loginQr.token,
    code: loginCode,
  });
  console.log(JSON.stringify({ status: replayed.status, body: replayed.body }));

  step("8. 查询会话状态");
  const session = await call("GET", "/totp/v1/session");
  console.log(JSON.stringify(session.body));

  server.closeAllConnections();
  await new Promise<void>((resolve) => server.close(() => resolve()));
}

main().catch((error: unknown) => {
  console.error(error);
  process.exit(1);
});
