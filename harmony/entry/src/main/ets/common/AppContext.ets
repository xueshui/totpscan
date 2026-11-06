import { TotpScanClient } from 'totpscan';

/**
 * 应用级单例。SDK 不依赖页面生命周期，这里只负责创建一次并共享。
 * 初始化失败（例如安全存储暂不可用）时保留错误，允许页面重试。
 */
export class AppContext {
  private static client: TotpScanClient | null = null;
  private static initTask: Promise<void> | null = null;

  static getClient(): TotpScanClient {
    const existing = AppContext.client;
    if (existing !== null) {
      return existing;
    }
    const created = TotpScanClient.create();
    AppContext.client = created;
    return created;
  }

  static async ready(): Promise<TotpScanClient> {
    const client = AppContext.getClient();
    if (AppContext.initTask === null) {
      AppContext.initTask = client.init();
    }
    try {
      await AppContext.initTask;
    } catch (error) {
      AppContext.initTask = null;
      throw error as Error;
    }
    return client;
  }
}
