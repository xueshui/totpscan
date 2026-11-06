import test from "node:test";
import assert from "node:assert/strict";
import { generateTotp, timeStepAt } from "../src/core/totp.ts";
import { tokenDigest } from "../src/core/token.ts";
import {
  bootstrap,
  codeFor,
  confirmBinding,
  createBinding,
  issueToken,
  startHarness,
  submitCode,
  TestClient,
  TEST_ADMIN_TOKEN,
  timeStepAfterConfirm,
  type HttpResult,
} from "./harness.ts";

const AUTHENTICATION_MESSAGE = "认证失败，请重新发起登录";

function wrongCode(valid: string): string {
  return valid === "000000" ? "000001" : "000000";
}

/** 统一错误响应断言（规范 §8.5）。 */
function assertUnifiedFailure(response: HttpResult): void {
  assert.equal(response.status, 401);
  assert.deepEqual(Object.keys(response.body).sort(), ["error", "message", "request_id"]);
  assert.equal(response.body.error, "authentication_failed");
  assert.equal(response.body.message, AUTHENTICATION_MESSAGE);
  assert.match(response.body.request_id, /^req_[A-Za-z0-9]{8,64}$/);
}

test("TC-01 正常绑定与登录：正确码提交成功并置会话已认证", async (t) => {
  const harness = await startHarness();
  t.after(() => harness.close());

  const binding = await bootstrap({ harness });
  const issued = await issueToken(harness.client);

  const response = await submitCode(
    harness.client,
    issued.token,
    codeFor(binding, harness.clock.now()),
  );
  assert.equal(response.status, 200);
  assert.deepEqual(response.body, { status: "ok", authenticated: true });

  const session = await harness.client.request("GET", "/totp/v1/session");
  assert.equal(session.body.authenticated, true);
  assert.equal(session.body.binding_id, binding.bindingId);
});

test("TC-02 一次性：同一 token 第二次提交失败", async (t) => {
  const harness = await startHarness();
  t.after(() => harness.close());

  const binding = await bootstrap({ harness });
  const issued = await issueToken(harness.client);
  const code = codeFor(binding, harness.clock.now());

  assert.equal((await submitCode(harness.client, issued.token, code)).status, 200);
  assertUnifiedFailure(await submitCode(harness.client, issued.token, code));
});

test("TC-03 时效：超过 60 秒后即使动态码正确也失败", async (t) => {
  const harness = await startHarness();
  t.after(() => harness.close());

  const binding = await bootstrap({ harness });
  const issued = await issueToken(harness.client);
  harness.clock.advanceMs(60_000);

  const response = await submitCode(
    harness.client,
    issued.token,
    codeFor(binding, harness.clock.now()),
  );
  assertUnifiedFailure(response);
});

test("TC-04 会话绑定：其他会话不能使用该 token", async (t) => {
  const harness = await startHarness();
  t.after(() => harness.close());

  const binding = await bootstrap({ harness });
  const issued = await issueToken(harness.client);

  const otherClient = new TestClient(harness.baseUrl);
  await otherClient.request("GET", "/totp/v1/session");

  const response = await submitCode(
    otherClient,
    issued.token,
    codeFor(binding, harness.clock.now()),
  );
  assertUnifiedFailure(response);
});

test("TC-05 四次失败后第五次正确码仍可成功", async (t) => {
  const harness = await startHarness();
  t.after(() => harness.close());

  const binding = await bootstrap({ harness });
  const issued = await issueToken(harness.client);
  const valid = codeFor(binding, harness.clock.now());
  const bad = wrongCode(valid);

  for (let i = 0; i < 4; i += 1) {
    assertUnifiedFailure(await submitCode(harness.client, issued.token, bad));
  }

  const success = await submitCode(harness.client, issued.token, valid);
  assert.equal(success.status, 200);
});

test("TC-06 五次失败后 token 作废，正确码也被拒绝", async (t) => {
  const harness = await startHarness();
  t.after(() => harness.close());

  const binding = await bootstrap({ harness });
  const issued = await issueToken(harness.client);
  const valid = codeFor(binding, harness.clock.now());
  const bad = wrongCode(valid);

  for (let i = 0; i < 5; i += 1) {
    assertUnifiedFailure(await submitCode(harness.client, issued.token, bad));
  }

  assertUnifiedFailure(await submitCode(harness.client, issued.token, valid));
  assert.equal(harness.app.store.getToken(tokenDigest(issued.token))?.state, "exhausted");
});

test("TC-07 接受 t-1 / t / t+1 三个时间窗", async (t) => {
  const harness = await startHarness();
  t.after(() => harness.close());

  const binding = await bootstrap({ harness });
  // 绑定确认已占用其时间步；再前进一个周期，保证 t-1 也不落在确认时间步上（S9）。
  harness.clock.advanceMs(binding.options.period * 1000);

  for (const offset of [-1, 0, 1]) {
    const issued = await issueToken(harness.client);
    const response = await submitCode(
      harness.client,
      issued.token,
      codeFor(binding, harness.clock.now(), offset),
    );
    assert.equal(response.status, 200, `offset ${offset}`);
  }
});

test("TC-08 拒绝 t-2 与 t+2", async (t) => {
  const harness = await startHarness();
  t.after(() => harness.close());

  const binding = await bootstrap({ harness });

  for (const offset of [-2, 2]) {
    const issued = await issueToken(harness.client);
    const response = await submitCode(
      harness.client,
      issued.token,
      codeFor(binding, harness.clock.now(), offset),
    );
    assertUnifiedFailure(response);
  }
});

test("TC-09 同一时间窗成功码不能重放（换新 token 也不行）", async (t) => {
  const harness = await startHarness();
  t.after(() => harness.close());

  const binding = await bootstrap({ harness });
  const code = codeFor(binding, harness.clock.now());

  const first = await issueToken(harness.client);
  assert.equal((await submitCode(harness.client, first.token, code)).status, 200);

  const second = await issueToken(harness.client);
  assertUnifiedFailure(await submitCode(harness.client, second.token, code));
});

test("TC-10 所有认证失败响应完全一致（仅 request_id 不同）", async (t) => {
  const harness = await startHarness();
  t.after(() => harness.close());

  const binding = await bootstrap({ harness });

  // 1) 未知 token
  const unknown = await submitCode(
    harness.client,
    "A".repeat(24),
    codeFor(binding, harness.clock.now()),
  );

  // 2) 已过期 token
  const expiring = await issueToken(harness.client);
  harness.clock.advanceMs(61_000);
  const expired = await submitCode(
    harness.client,
    expiring.token,
    codeFor(binding, harness.clock.now()),
  );

  // 3) 跨会话
  const cross = await issueToken(harness.client);
  const otherClient = new TestClient(harness.baseUrl);
  await otherClient.request("GET", "/totp/v1/session");
  const crossSession = await submitCode(
    otherClient,
    cross.token,
    codeFor(binding, harness.clock.now()),
  );

  // 4) 动态码错误
  const wrong = await issueToken(harness.client);
  const wrongCodeResponse = await submitCode(
    harness.client,
    wrong.token,
    wrongCode(codeFor(binding, harness.clock.now())),
  );

  const responses = [unknown, expired, crossSession, wrongCodeResponse];
  for (const response of responses) {
    assertUnifiedFailure(response);
  }
  const shapes = responses.map((response) => ({
    status: response.status,
    error: response.body.error,
    message: response.body.message,
  }));
  for (const shape of shapes) {
    assert.deepEqual(shape, shapes[0]);
  }
  const requestIds = new Set(responses.map((response) => response.body.request_id));
  assert.equal(requestIds.size, responses.length);
});

test("TC-11 绑定确认：错误码 401，正确码 200", async (t) => {
  const harness = await startHarness();
  t.after(() => harness.close());

  const binding = await createBinding(harness.client);
  const valid = codeFor(binding, harness.clock.now());

  const failed = await harness.client.request("POST", `/totp/v1/bindings/${binding.bindingId}/confirm`, {
    code: wrongCode(valid),
  });
  assertUnifiedFailure(failed);

  const confirmed = await harness.client.request("POST", `/totp/v1/bindings/${binding.bindingId}/confirm`, {
    code: valid,
  });
  assert.equal(confirmed.status, 200);
  assert.equal(confirmed.body.status, "confirmed");
});

test("TC-12 未确认绑定不能签发登录 token", async (t) => {
  const harness = await startHarness();
  t.after(() => harness.close());

  await createBinding(harness.client);
  const response = await harness.client.request("POST", "/totp/v1/login/token", {
    account: "alice@example.com",
  });
  assertUnifiedFailure(response);
  assert.equal(response.body.token, undefined);
});

test("TC-13 解绑后已签发 token 失效且无法再签发", async (t) => {
  const harness = await startHarness();
  t.after(() => harness.close());

  const binding = await bootstrap({ harness });
  const issued = await issueToken(harness.client);

  const revoked = await harness.client.request(
    "POST",
    `/totp/v1/bindings/${binding.bindingId}/revoke`,
    {},
    { authorization: `Bearer ${TEST_ADMIN_TOKEN}` },
  );
  assert.equal(revoked.status, 200);

  const verify = await submitCode(
    harness.client,
    issued.token,
    codeFor(binding, harness.clock.now()),
  );
  assertUnifiedFailure(verify);

  const reissue = await harness.client.request("POST", "/totp/v1/login/token", {
    account: "alice@example.com",
  });
  assertUnifiedFailure(reissue);
});

test("TC-18 签发限流：超过阈值返回 429", async (t) => {
  const harness = await startHarness((config) => {
    config.rates.tokenPerIp = { limit: 2, windowMs: 60_000 };
  });
  t.after(() => harness.close());

  await bootstrap({ harness });
  const first = await issueToken(harness.client);
  const second = await issueToken(harness.client);
  assert.equal(first.token.length, 24);
  assert.equal(second.token.length, 24);
  assert.notEqual(first.token, second.token);

  const limited = await harness.client.request("POST", "/totp/v1/login/token", {
    account: "alice@example.com",
  });
  assert.equal(limited.status, 429);
  assert.equal(limited.body.error, "rate_limited");
});

test("TC-19 绑定确认 5 次失败后绑定失效", async (t) => {
  const harness = await startHarness();
  t.after(() => harness.close());

  const binding = await createBinding(harness.client);
  const valid = codeFor(binding, harness.clock.now());
  const bad = wrongCode(valid);

  for (let i = 0; i < 5; i += 1) {
    assertUnifiedFailure(
      await harness.client.request("POST", `/totp/v1/bindings/${binding.bindingId}/confirm`, { code: bad }),
    );
  }

  assertUnifiedFailure(
    await harness.client.request("POST", `/totp/v1/bindings/${binding.bindingId}/confirm`, { code: valid }),
  );
  assert.equal(harness.app.store.getBinding(binding.bindingId)?.status, "invalid");
});

test("TC-20 token 以摘要存储，不以明文检索", async (t) => {
  const harness = await startHarness();
  t.after(() => harness.close());

  const binding = await bootstrap({ harness });
  const issued = await issueToken(harness.client);

  assert.ok(harness.app.store.getToken(tokenDigest(issued.token)));
  assert.equal(harness.app.store.getToken(issued.token), null);

  // 校验阶段使用同一份密钥计算，提交成功说明 token 与绑定正确关联。
  const response = await submitCode(
    harness.client,
    issued.token,
    codeFor(binding, harness.clock.now()),
  );
  assert.equal(response.status, 200);
});

test("请求格式错误返回 400 且不泄露 token 状态", async (t) => {
  const harness = await startHarness();
  t.after(() => harness.close());

  await bootstrap({ harness });

  const missing = await harness.client.request("POST", "/totp/v1/verify", { code: "123456" });
  assert.equal(missing.status, 400);
  assert.equal(missing.body.error, "invalid_request");

  const notJson = await fetch(`${harness.baseUrl}/totp/v1/verify`, {
    method: "POST",
    headers: { "content-type": "text/plain" },
    body: "token=x",
  });
  assert.equal(notJson.status, 400);
});

test("健康检查可用，公钥相关端点已删除", async (t) => {
  const harness = await startHarness();
  t.after(() => harness.close());

  const health = await harness.client.request("GET", "/healthz");
  assert.equal(health.status, 200);
  assert.deepEqual(health.body, { status: "ok" });

  // 服务端不提供任何公钥分发端点。
  assert.equal((await harness.client.request("GET", "/.well-known/totp-scan-binding-key")).status, 404);
  assert.equal((await harness.client.request("GET", "/.well-known/totpscan-keys.json")).status, 404);
});

test("绑定二维码输出 dom 与 path，且不含签名字段", async (t) => {
  const harness = await startHarness();
  t.after(() => harness.close());

  const binding = await createBinding(harness.client);
  assert.equal(binding.qr.t, "totp-bind");
  assert.equal(binding.qr.v, 1);
  assert.equal(binding.qr.dom, "localhost:8080");
  assert.equal(binding.qr.path, "/totp/v1/verify");
  assert.equal("sig" in binding.qr, false);
  assert.equal("kid" in binding.qr, false);
  assert.equal("pub" in binding.qr, false);
});

test("提交路径带查询串时原样写入 path", async (t) => {
  const harness = await startHarness((config) => {
    config.submitUrl = "http://localhost:8080/dtm/ulr?ma=xxx";
  });
  t.after(() => harness.close());

  const binding = await createBinding(harness.client);
  assert.equal(binding.qr.dom, "localhost:8080");
  assert.equal(binding.qr.path, "/dtm/ulr?ma=xxx");
});

test("TC-21 非 SHA1 参数（SHA256 / 8 位 / 60 秒）端到端可用", async (t) => {
  const harness = await startHarness();
  t.after(() => harness.close());

  const binding = await createBinding(harness.client, "bob@example.com", {
    algorithm: "SHA256",
    digits: 8,
    period: 60,
  });
  const confirmAt = harness.clock.now();
  await confirmBinding(harness.client, binding, confirmAt);
  harness.clock.advanceMs(timeStepAfterConfirm(binding, confirmAt) - confirmAt);
  await harness.client.request("GET", "/totp/v1/session");

  const issued = await issueToken(harness.client, "bob@example.com");
  assert.equal(binding.options.algorithm, "SHA256");
  assert.equal(binding.options.digits, 8);
  assert.equal(binding.options.period, 60);

  const code = codeFor(binding, harness.clock.now());
  assert.equal(code.length, 8);

  const response = await submitCode(harness.client, issued.token, code);
  assert.equal(response.status, 200);

  // 用 6 位长度提交同一个 token 的新拷贝应被当作格式错误拒绝，而不是降级按 6 位匹配。
  const second = await issueToken(harness.client, "bob@example.com");
  assertUnifiedFailure(await submitCode(harness.client, second.token, code.slice(0, 6)));
});

test("绑定确认后可用动态码登录：默认 6 位 / 30 秒", async (t) => {
  const harness = await startHarness();
  t.after(() => harness.close());

  const binding = await createBinding(harness.client);
  const confirmAt = harness.clock.now();
  await confirmBinding(harness.client, binding, confirmAt);
  harness.clock.advanceMs(timeStepAfterConfirm(binding, confirmAt) - confirmAt);
  const issued = await issueToken(harness.client);

  const code = generateTotp(binding.secret, timeStepAt(harness.clock.now(), 30));
  assert.equal(code.length, 6);
  const response = await submitCode(harness.client, issued.token, code);
  assert.equal(response.status, 200);
});

test("TC-25 token 绑定账户：用 alice 的 token 提交 bob 的码必须失败", async (t) => {
  const harness = await startHarness();
  t.after(() => harness.close());

  const alice = await bootstrap({ harness, account: "alice@example.com" });
  const bob = await bootstrap({ harness, account: "bob@example.com" });
  assert.equal(alice.qr.dom, bob.qr.dom);
  assert.equal(alice.qr.path, bob.qr.path);

  // 用 alice 的 token 提交 bob 的码 → 服务端按 token 绑定账户取密钥，统一失败。
  const wrong = await issueToken(harness.client, "alice@example.com");
  assertUnifiedFailure(await submitCode(harness.client, wrong.token, codeFor(bob, harness.clock.now())));

  // 正确账户 + 正确码 → 成功。
  const right = await issueToken(harness.client, "alice@example.com");
  assert.equal(
    (await submitCode(harness.client, right.token, codeFor(alice, harness.clock.now()))).status,
    200,
  );
});

test("TC-26 签发 token 时必须指定 account", async (t) => {
  const harness = await startHarness();
  t.after(() => harness.close());

  const binding = await bootstrap({ harness, account: "alice@example.com" });
  const missing = await harness.client.request("POST", "/totp/v1/login/token", {});
  assert.equal(missing.status, 400);

  const issued = await issueToken(harness.client, "alice@example.com");
  assert.equal(
    (await submitCode(harness.client, issued.token, codeFor(binding, harness.clock.now()))).status,
    200,
  );
});

test("TC-28 无钉住地址/无绑定记录的账户不参与扫码提交", async (t) => {
  const harness = await startHarness();
  t.after(() => harness.close());

  const standard = "standard@example.com";
  const issue = await harness.client.request("POST", "/totp/v1/login/token", { account: standard });
  assertUnifiedFailure(issue);
  await bootstrap({ harness, account: "alice@example.com" });
});

test("确认成功写入重放记录：同一时间步的动态码不能立即用于登录", async (t) => {
  const harness = await startHarness();
  t.after(() => harness.close());

  const binding = await createBinding(harness.client);
  const confirmAt = harness.clock.now();
  const code = codeFor(binding, confirmAt);
  const confirmed = await harness.client.request("POST", `/totp/v1/bindings/${binding.bindingId}/confirm`, {
    code,
  });
  assert.equal(confirmed.status, 200);

  await harness.client.request("GET", "/totp/v1/session");
  const sameStep = await issueToken(harness.client);
  assertUnifiedFailure(await submitCode(harness.client, sameStep.token, code));

  // 进入下一个时间步后可以正常登录。
  harness.clock.advanceMs(binding.options.period * 1000);
  const nextStep = await issueToken(harness.client);
  assert.equal(
    (await submitCode(harness.client, nextStep.token, codeFor(binding, harness.clock.now()))).status,
    200,
  );
});

test("请求体拒绝 OpenAPI schema 未声明的字段", async (t) => {
  const harness = await startHarness();
  t.after(() => harness.close());

  const created = await harness.client.request(
    "POST",
    "/totp/v1/bindings",
    { issuer: "Example Corp", account: "alice@example.com", unexpected: true },
    { authorization: `Bearer ${TEST_ADMIN_TOKEN}` },
  );
  assert.equal(created.status, 400);
  assert.equal(created.body.error, "invalid_request");

  const binding = await bootstrap({ harness });
  const issued = await issueToken(harness.client);
  const rejected = await harness.client.request("POST", "/totp/v1/verify", {
    token: issued.token,
    code: codeFor(binding, harness.clock.now()),
    account: "alice@example.com",
    extra: "ignored",
  });
  assert.equal(rejected.status, 400);
  assert.equal(rejected.body.error, "invalid_request");
});
