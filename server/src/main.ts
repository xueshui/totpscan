import { createServer } from "node:http";
import { createApp, type App } from "./app.ts";
import { loadConfig, type Config } from "./config.ts";

function failStartup(error: unknown): never {
  console.error(
    JSON.stringify({
      ts: new Date().toISOString(),
      event: "startup_failed",
      error: error instanceof Error ? error.message : "UNKNOWN",
    }),
  );
  process.exit(1);
}

function init(): { config: Config; app: App } {
  try {
    const config = loadConfig();
    return { config, app: createApp({ config }) };
  } catch (error) {
    return failStartup(error);
  }
}

const { config, app } = init();

const server = createServer(app.handler);

server.listen(config.port, config.host, () => {
  // 启动日志只输出公开信息；管理员令牌绝不输出。
  console.log(
    JSON.stringify({
      ts: new Date().toISOString(),
      event: "server_started",
      listen: `http://${config.host}:${config.port}`,
      public_base_url: config.publicBaseUrl,
      submit_url: config.submitUrl,
    }),
  );
});

function shutdown(signal: string): void {
  console.log(JSON.stringify({ ts: new Date().toISOString(), event: "server_stopping", signal }));
  server.close(() => process.exit(0));
}

process.on("SIGINT", () => shutdown("SIGINT"));
process.on("SIGTERM", () => shutdown("SIGTERM"));
