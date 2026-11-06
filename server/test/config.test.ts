import test from "node:test";
import assert from "node:assert/strict";
import { loadConfig, MIN_ADMIN_TOKEN_LENGTH } from "../src/config.ts";

const VALID_TOKEN = "a".repeat(MIN_ADMIN_TOKEN_LENGTH);

test("S14：ADMIN_TOKEN 未配置时拒绝启动", () => {
  assert.throws(() => loadConfig({}), /ADMIN_TOKEN 未配置/);
  assert.throws(() => loadConfig({ ADMIN_TOKEN: "   " }), /ADMIN_TOKEN 未配置/);
});

test("S14：ADMIN_TOKEN 长度不足时拒绝启动", () => {
  const short = "b".repeat(MIN_ADMIN_TOKEN_LENGTH - 1);
  assert.throws(() => loadConfig({ ADMIN_TOKEN: short }), /长度不足/);
});

test("S14：ADMIN_TOKEN 达到最小长度即可启动", () => {
  const config = loadConfig({ ADMIN_TOKEN: VALID_TOKEN });
  assert.equal(config.adminToken, VALID_TOKEN);
});
